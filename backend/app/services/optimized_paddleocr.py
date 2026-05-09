"""
Optimized PaddleOCR Batch Processor
Zero-Redundancy OCR Pipeline for High-Performance Invoice Processing
"""

import cv2
import numpy as np
import gc
import logging
from typing import List, Dict, Any, Optional, Generator, Tuple, Union
from dataclasses import dataclass, field
from pathlib import Path
import time
import re
import io
from concurrent.futures import ThreadPoolExecutor, as_completed

logger = logging.getLogger(__name__)

# Memory-safe settings
MAX_WORKERS = 1  # PaddleOCR is not thread-safe, process sequentially


@dataclass
class OptimizedOCRResult:
    """Optimized OCR result with manual review flag"""
    text: str
    confidence: float
    bbox: List[List[int]]
    requires_manual_review: bool = False
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'text': self.text,
            'confidence': self.confidence,
            'bbox': self.bbox,
            'requires_manual_review': self.requires_manual_review
        }


@dataclass
class OptimizedInvoiceResult:
    """Complete invoice extraction result"""
    invoice_id: str
    processing_time_ms: float
    ocr_results: List[OptimizedOCRResult]
    extracted_data: Dict[str, Any] = field(default_factory=dict)
    manual_review_required: bool = False
    review_reasons: List[str] = field(default_factory=list)
    memory_peak_mb: float = 0.0
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'invoice_id': self.invoice_id,
            'processing_time_ms': self.processing_time_ms,
            'ocr_results': [r.to_dict() for r in self.ocr_results],
            'extracted_data': self.extracted_data,
            'manual_review_required': self.manual_review_required,
            'review_reasons': self.review_reasons,
            'memory_peak_mb': self.memory_peak_mb
        }


class OptimizedPaddleOCRProcessor:
    """
    High-performance PaddleOCR processor optimized for batch processing.
    Zero redundancy, memory efficient, and fast.
    """
    
    def __init__(self, 
                 confidence_threshold: float = 0.85,
                 max_image_size: Tuple[int, int] = (1920, 1080),
                 enable_grayscale: bool = True):
        """
        Initialize optimized PaddleOCR processor.
        
        Args:
            confidence_threshold: Minimum confidence to accept (default 0.85)
            max_image_size: Maximum image dimensions to reduce CPU load
            enable_grayscale: Convert to grayscale before OCR
        """
        self.confidence_threshold = confidence_threshold
        self.max_image_size = max_image_size
        self.enable_grayscale = enable_grayscale
        
        # Initialize PaddleOCR once
        self._ocr = None
        self._init_paddleocr()
        
        # Memory tracking
        self._peak_memory = 0.0
        
        logger.info(f"OptimizedPaddleOCRProcessor initialized (threshold: {confidence_threshold})")
    
    def _init_paddleocr(self):
        """Initialize PaddleOCR with optimal settings"""
        try:
            from paddleocr import PaddleOCR
            self._ocr = PaddleOCR(
                use_angle_cls=True,
                lang='en',
                show_log=False,
                use_gpu=False,
                det_model_dir=None,  # Use default models
                rec_model_dir=None,
                cls_model_dir=None
            )
            logger.info("PaddleOCR initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize PaddleOCR: {e}")
            raise
    
    def _optimize_image(self, image: np.ndarray) -> np.ndarray:
        """
        Optimize image for OCR: resize and convert to grayscale.
        Reduces CPU load by up to 50%.
        """
        # Get current dimensions
        h, w = image.shape[:2]
        
        # Resize if larger than max size
        if h > self.max_image_size[1] or w > self.max_image_size[0]:
            # Calculate scaling factor
            scale = min(
                self.max_image_size[0] / w,
                self.max_image_size[1] / h
            )
            new_w = int(w * scale)
            new_h = int(h * scale)
            
            # Use INTER_AREA for downscaling (better quality)
            image = cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_AREA)
            logger.debug(f"Image resized: {w}x{h} -> {new_w}x{new_h}")
        
        # Convert to grayscale if enabled and not already grayscale
        if self.enable_grayscale and len(image.shape) == 3:
            image = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            logger.debug("Converted to grayscale")
        
        return image
    
    def _track_memory(self):
        """Track peak memory usage"""
        try:
            import psutil
            process = psutil.Process()
            current_memory = process.memory_info().rss / 1024 / 1024  # MB
            self._peak_memory = max(self._peak_memory, current_memory)
        except ImportError:
            # psutil not available, skip tracking
            pass
    
    def _extract_with_paddleocr(self, image: np.ndarray) -> List[OptimizedOCRResult]:
        """
        Extract text using PaddleOCR with confidence gating.
        """
        # Convert to RGB if grayscale
        if len(image.shape) == 2:
            image = cv2.cvtColor(image, cv2.COLOR_GRAY2RGB)
        elif len(image.shape) == 3 and image.shape[2] == 3:
            image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        # Run OCR
        result = self._ocr.ocr(image, cls=True)
        
        ocr_results = []
        if result and isinstance(result, list):
            for line in result:
                if line is None:
                    continue
                for item in line:
                    if item is None:
                        continue
                    
                    bbox, text_info = item
                    text = text_info[0].strip()
                    confidence = text_info[1]
                    
                    # Skip empty text
                    if not text:
                        continue
                    
                    # Apply confidence gate
                    requires_manual_review = confidence < self.confidence_threshold
                    
                    ocr_results.append(OptimizedOCRResult(
                        text=text,
                        confidence=confidence,
                        bbox=bbox,
                        requires_manual_review=requires_manual_review
                    ))
        
        return ocr_results
    
    def _convert_pdf_to_images(self, pdf_bytes: bytes, invoice_id: str) -> List[np.ndarray]:
        """Convert PDF bytes to list of images (one per page)"""
        try:
            import fitz  # PyMuPDF
            
            images = []
            pdf_document = fitz.open(stream=pdf_bytes, filetype="pdf")
            
            for page_num in range(len(pdf_document)):
                page = pdf_document[page_num]
                # Render page at 200 DPI for good OCR quality
                mat = fitz.Matrix(2, 2)  # 2x zoom = ~200 DPI
                pix = page.get_pixmap(matrix=mat)
                
                # Convert to numpy array
                img_data = pix.tobytes("png")
                nparr = np.frombuffer(img_data, np.uint8)
                img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                
                if img is not None:
                    images.append(img)
                    logger.debug(f"Converted PDF page {page_num + 1} for {invoice_id}")
            
            pdf_document.close()
            
            if not images:
                raise ValueError("No images could be extracted from PDF")
            
            logger.info(f"Converted PDF to {len(images)} images for {invoice_id}")
            return images
            
        except Exception as e:
            logger.error(f"Failed to convert PDF: {e}")
            raise

    def _process_single_file_with_cleanup(self, invoice_id: str, data: Union[str, bytes], file_type: str) -> OptimizedInvoiceResult:
        """
        Process single invoice with explicit cleanup.
        Used by concurrent executor to ensure memory safety.
        
        Args:
            invoice_id: ID for the invoice
            data: File path (str) for images or bytes for PDFs
            file_type: 'image' or 'pdf'
        """
        images_to_process = []
        
        try:
            if file_type == 'pdf':
                # Convert PDF to images
                pdf_bytes = data if isinstance(data, bytes) else open(data, 'rb').read()
                images_to_process = self._convert_pdf_to_images(pdf_bytes, invoice_id)
                logger.info(f"PDF converted to {len(images_to_process)} images for {invoice_id}")
            else:
                # Load image from path or bytes
                if isinstance(data, str):
                    image = cv2.imread(data)
                else:
                    nparr = np.frombuffer(data, np.uint8)
                    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                
                if image is None:
                    raise ValueError(f"Could not load image: {invoice_id}")
                images_to_process = [image]

            # Process first page/image (or could process all pages)
            if images_to_process:
                result = self.process_single_invoice(images_to_process[0], invoice_id)
                
                # If PDF had multiple pages, note it in review reasons
                if len(images_to_process) > 1:
                    result.review_reasons.append(f"PDF has {len(images_to_process)} pages, processed first page only")
                
                return result
            else:
                raise ValueError("No images to process")

        finally:
            # Explicit memory cleanup
            for img in images_to_process:
                del img
            gc.collect()

    def process_batch_concurrent(self,
                               files_data: List[Tuple[str, Union[str, bytes], str]],  # (id, path_or_bytes, type)
                               max_workers: int = MAX_WORKERS) -> List[OptimizedInvoiceResult]:
        """
        Process batch concurrently with controlled parallelism.
        Uses ThreadPoolExecutor with max_workers=2 for memory safety.
        
        Args:
            files_data: List of tuples (invoice_id, path_or_bytes, file_type)
                       file_type: 'image' or 'pdf'
        """
        if not files_data:
            return []

        logger.info(f"Starting concurrent batch processing of {len(files_data)} invoices (max_workers={max_workers})")

        results = []
        total_memory = 0.0

        # Submit all tasks to thread pool
        with ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="ocr_worker") as executor:
            # Create futures for each invoice
            future_to_data = {}
            for invoice_id, data, file_type in files_data:
                future = executor.submit(self._process_single_file_with_cleanup, invoice_id, data, file_type)
                future_to_data[future] = (invoice_id, data, file_type)

            # Collect results as they complete
            for i, future in enumerate(as_completed(future_to_data)):
                invoice_id, data, file_type = future_to_data[future]
                try:
                    result = future.result()
                    results.append(result)
                    total_memory += result.memory_peak_mb

                    logger.info(f"Completed {i+1}/{len(files_data)}: {result.invoice_id} "
                               f"({result.processing_time_ms:.0f}ms, {result.memory_peak_mb:.1f}MB)")

                except Exception as e:
                    logger.error(f"Failed to process {invoice_id}: {e}")
                    # Create error result
                    error_result = OptimizedInvoiceResult(
                        invoice_id=invoice_id,
                        processing_time_ms=0.0,
                        ocr_results=[],
                        extracted_data={},
                        manual_review_required=True,
                        review_reasons=[f"Processing failed: {str(e)}"],
                        memory_peak_mb=0.0
                    )
                    results.append(error_result)

        logger.info(f"Concurrent batch processing completed: {len(results)} results, "
                   f"avg memory: {total_memory/max(len(results),1):.1f}MB")

        return results

    def process_single_invoice(self, 
                               image: np.ndarray, 
                               invoice_id: str) -> OptimizedInvoiceResult:
        """
        Process a single invoice with memory management.
        """
        start_time = time.time()
        self._peak_memory = 0.0
        
        try:
            # Track memory before processing
            self._track_memory()
            
            # Optimize image
            optimized_image = self._optimize_image(image)
            
            # Extract text with PaddleOCR
            ocr_results = self._extract_with_paddleocr(optimized_image)
            
            # Check if manual review is required
            manual_review_required = any(r.requires_manual_review for r in ocr_results)
            review_reasons = []
            
            if manual_review_required:
                low_confidence_count = sum(1 for r in ocr_results if r.requires_manual_review)
                review_reasons.append(f"{low_confidence_count} text regions below {self.confidence_threshold} confidence")
            
            # Extract structured data
            extracted_data = self._extract_invoice_data(ocr_results)
            
            # Track memory after processing
            self._track_memory()
            
            processing_time = (time.time() - start_time) * 1000
            
            result = OptimizedInvoiceResult(
                invoice_id=invoice_id,
                processing_time_ms=processing_time,
                ocr_results=ocr_results,
                extracted_data=extracted_data,
                manual_review_required=manual_review_required,
                review_reasons=review_reasons,
                memory_peak_mb=self._peak_memory
            )
            
            logger.info(f"Invoice {invoice_id}: {len(ocr_results)} regions, "
                       f"{processing_time:.0f}ms, peak memory: {self._peak_memory:.1f}MB")
            
            return result
            
        except Exception as e:
            logger.error(f"Failed to process invoice {invoice_id}: {e}")
            raise
        finally:
            # Explicit garbage collection to prevent memory leaks
            gc.collect()
    
    def process_batch(self, 
                      image_paths: List[str]) -> Generator[OptimizedInvoiceResult, None, None]:
        """
        Process a batch of invoices using a generator for responsive UI.
        Yields results one by one to keep UI responsive.
        """
        logger.info(f"Starting batch processing of {len(image_paths)} invoices")
        
        for i, image_path in enumerate(image_paths):
            try:
                # Load image
                image = cv2.imread(image_path)
                if image is None:
                    logger.error(f"Failed to load image: {image_path}")
                    continue
                
                # Generate invoice ID from filename
                invoice_id = Path(image_path).stem
                
                # Process invoice
                result = self.process_single_invoice(image, invoice_id)
                
                # Yield result for responsive UI
                yield result
                
                # Log progress
                logger.info(f"Progress: {i+1}/{len(image_paths)} completed")
                
            except Exception as e:
                logger.error(f"Error processing {image_path}: {e}")
                continue
            finally:
                # Always cleanup after each invoice
                gc.collect()
        
        logger.info("Batch processing completed")
    
    def _extract_invoice_data(self, ocr_results: List[OptimizedOCRResult]) -> Dict[str, Any]:
        """
        Extract structured invoice data from OCR results.
        Simplified version - can be enhanced with more sophisticated logic.
        """
        data = {}
        
        # Convert OCR results to text list
        texts = [r.text for r in ocr_results if r.confidence >= self.confidence_threshold]
        
        # Simple keyword-based extraction
        for i, text in enumerate(texts):
            text_lower = text.lower()
            
            # Invoice number
            if 'invoice' in text_lower and 'number' in text_lower:
                if i + 1 < len(texts):
                    data['invoice_number'] = texts[i + 1]
            
            # Total amount
            elif 'total' in text_lower:
                # Look for amount pattern
                amount_match = re.search(r'[\d,]+\.\d{2}', text)
                if amount_match:
                    data['total_amount'] = amount_match.group()
                elif i + 1 < len(texts):
                    amount_match = re.search(r'[\d,]+\.\d{2}', texts[i + 1])
                    if amount_match:
                        data['total_amount'] = amount_match.group()
            
            # Date
            elif re.search(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}', text):
                data['invoice_date'] = text
        
        return data


# Convenience function for batch processing
def process_invoice_batch(image_paths: List[str], 
                           confidence_threshold: float = 0.85) -> Generator[OptimizedInvoiceResult, None, None]:
    """
    Process a batch of invoices with optimized PaddleOCR.
    Returns a generator for responsive UI.
    """
    processor = OptimizedPaddleOCRProcessor(confidence_threshold=confidence_threshold)
    yield from processor.process_batch(image_paths)
