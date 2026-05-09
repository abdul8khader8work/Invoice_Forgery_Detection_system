"""
Simple Invoice Extraction using pdf2image + OCR + Coordinate Registry
No PyMuPDF, no complex ML - just reliable business rules
"""

import os
import cv2
import numpy as np
from typing import Dict, List, Optional, Any, Union
from pathlib import Path
import logging
from pdf2image import convert_from_path
import tempfile

from app.services.coordinate_registry import get_coordinate_registry, CoordinateRegistry
from app.services.field_discovery import SmartExtractionEngine, extract_smart

logger = logging.getLogger(__name__)


class SimpleInvoiceExtractor:
    """
    Smart invoice extraction pipeline:
    1. PDF → Image (pdf2image at 300 DPI)
    2. OCR (EasyOCR/Tesseract)
    3. Dynamic field discovery (finds what's actually present)
    4. Validation (checksum rules)
    """
    
    def __init__(self, db_session=None, dpi: int = 300):
        self.db = db_session
        self.dpi = dpi
        self.smart_engine = SmartExtractionEngine()
        self._ocr_engine = None
    
    def _get_ocr_engine(self):
        """Lazy init OCR engine"""
        if self._ocr_engine is None:
            try:
                import easyocr
                self._ocr_engine = easyocr.Reader(['en'], gpu=False, verbose=False)
                logger.info("EasyOCR engine initialized")
            except Exception as e:
                logger.error(f"Failed to init EasyOCR: {e}")
                raise
        return self._ocr_engine
    
    def pdf_to_image(self, pdf_path: Union[str, Path]) -> str:
        """
        Convert PDF to high-res image using pdf2image
        
        Returns:
            Path to temporary image file
        """
        try:
            images = convert_from_path(
                pdf_path,
                dpi=self.dpi,
                first_page=1,
                last_page=1,
                fmt='PNG'
            )
            
            if not images:
                raise ValueError("No images extracted from PDF")
            
            # Save to temp file
            temp_file = tempfile.NamedTemporaryFile(suffix='.png', delete=False)
            images[0].save(temp_file.name, 'PNG')
            temp_file.close()
            
            logger.info(f"PDF converted to image: {temp_file.name} at {self.dpi} DPI")
            return temp_file.name
            
        except Exception as e:
            logger.error(f"PDF conversion failed: {e}")
            raise
    
    def preprocess_image(self, image_path: str) -> np.ndarray:
        """Simple preprocessing for better OCR"""
        image = cv2.imread(image_path)
        if image is None:
            raise ValueError(f"Cannot read image: {image_path}")
        
        # Convert to grayscale
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Denoise
        denoised = cv2.fastNlMeansDenoising(gray, None, 10, 7, 21)
        
        # Enhance contrast
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(denoised)
        
        return enhanced
    
    def run_ocr(self, image_path: str) -> List[Dict]:
        """
        Run OCR and return standardized box format
        
        Returns:
            List of dicts: {'x', 'y', 'width', 'height', 'text', 'confidence'}
        """
        # Preprocess
        processed = self.preprocess_image(image_path)
        
        # Save processed temp
        temp_path = image_path + '.processed.png'
        cv2.imwrite(temp_path, processed)
        
        try:
            reader = self._get_ocr_engine()
            results = reader.readtext(temp_path)
            
            boxes = []
            for detection in results:
                bbox, text, confidence = detection
                
                # bbox format: [[x1,y1], [x2,y1], [x2,y2], [x1,y2]]
                x_coords = [p[0] for p in bbox]
                y_coords = [p[1] for p in bbox]
                
                x = min(x_coords)
                y = min(y_coords)
                width = max(x_coords) - x
                height = max(y_coords) - y
                
                boxes.append({
                    'x': x,
                    'y': y,
                    'width': width,
                    'height': height,
                    'text': text,
                    'confidence': confidence
                })
            
            logger.info(f"OCR detected {len(boxes)} text regions")
            return boxes
            
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)
    
    def extract_invoice(self,
                       file_path: Union[str, Path],
                       style_hint: Optional[str] = None) -> Dict[str, Any]:
        """
        Main extraction pipeline
        
        Args:
            file_path: Path to PDF or image
            style_hint: Optional vendor template to use
        
        Returns:
            Dict with extracted data, validation warnings, metadata
        """
        import time
        start_time = time.time()
        
        file_path = Path(file_path)
        
        # Step 1: Convert to image if PDF
        if file_path.suffix.lower() == '.pdf':
            image_path = self.pdf_to_image(file_path)
            is_temp = True
        else:
            image_path = str(file_path)
            is_temp = False
        
        try:
            # Step 2: OCR
            ocr_boxes = self.run_ocr(image_path)
            
            # Step 3: Dynamic field discovery - finds what's actually present
            logger.info("Running dynamic field discovery...")
            extracted = self.smart_engine.extract_invoice(ocr_boxes)
            
            # Step 4: Validation (already done by smart engine)
            warnings = extracted.get('validation', [])
            
            # Calculate confidence from discovery
            confidence = extracted.get('metadata', {}).get('discovery_confidence', 0)
            
            processing_time = int((time.time() - start_time) * 1000)
            
            return {
                'success': True,
                'style_tag': style_hint or 'discovered',
                'extracted_data': extracted,
                'validation_warnings': warnings,
                'overall_confidence': confidence,
                'needs_verification': len(warnings) > 0 or confidence < 0.6,
                'processing_time_ms': processing_time,
                'ocr_count': len(ocr_boxes),
                'field_coverage': extracted.get('metadata', {}).get('field_coverage', {}),
                'is_new_template': True  # Always true with discovery approach
            }
            
        finally:
            if is_temp and os.path.exists(image_path):
                os.remove(image_path)
    
    def _identify_vendor(self, ocr_boxes: List[Dict]) -> str:
        """Simple vendor identification from OCR text"""
        full_text = ' '.join([box['text'] for box in ocr_boxes]).lower()
        
        # Check for known vendor names
        vendors = {
            'amazon': 'amazon_invoice',
            'flipkart': 'flipkart_invoice',
            'zomato': 'zomato_invoice',
            'swiggy': 'swiggy_invoice',
            'uber': 'uber_invoice',
            'ola': 'ola_invoice'
        }
        
        for keyword, style_tag in vendors.items():
            if keyword in full_text:
                return style_tag
        
        # Default: generic
        return 'generic_invoice'
    
    def _heuristic_extraction(self, ocr_boxes: List[Dict]) -> Dict[str, Any]:
        """
        Fallback extraction when no template exists
        Uses regex patterns to find common fields
        """
        import re
        
        extracted = {}
        full_text = ' '.join([box['text'] for box in ocr_boxes])
        
        # Invoice number patterns
        inv_patterns = [
            r'(?:INV|Invoice|Bill|Order)[\s#:-]*(\d{4,})',
            r'#(\d{6,})',
            r'INV[A-Z0-9]{4,}'
        ]
        for pattern in inv_patterns:
            match = re.search(pattern, full_text, re.IGNORECASE)
            if match:
                extracted['invoice_number'] = {
                    'value': match.group(0),
                    'confidence': 0.7,
                    'method': 'heuristic_regex'
                }
                break
        
        # Date patterns (DD/MM/YYYY, DD-MM-YYYY, etc.)
        date_patterns = [
            r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
            r'(\d{1,2}\s+[A-Za-z]{3,}\s+\d{2,4})'
        ]
        for pattern in date_patterns:
            match = re.search(pattern, full_text)
            if match:
                extracted['invoice_date'] = {
                    'value': match.group(0),
                    'confidence': 0.6,
                    'method': 'heuristic_regex'
                }
                break
        
        # Amount patterns (look for $, ₹, or followed by Total/Grand)
        amount_pattern = r'(?:Total|Grand|Amount|Sum)[\s:]*[$₹]?\s*([\d,]+\.?\d*)'
        matches = re.finditer(amount_pattern, full_text, re.IGNORECASE)
        amounts = []
        for match in matches:
            try:
                amt = float(match.group(1).replace(',', ''))
                amounts.append((amt, match.group(0)))
            except:
                pass
        
        if amounts:
            # Usually the largest amount is the total
            max_amount = max(amounts, key=lambda x: x[0])
            extracted['total'] = {
                'value': max_amount[1],
                'confidence': 0.65,
                'method': 'heuristic_pattern'
            }
        
        return extracted
    
    def update_template_from_correction(self,
                                       style_tag: str,
                                       corrections: Dict[str, Any],
                                       ocr_boxes: List[Dict]):
        """
        Update coordinate registry with user corrections
        
        Args:
            corrections: Dict of field_name -> {correct_value, correct_bbox}
        """
        for field_name, correction in corrections.items():
            anchor_texts = self.coordinate_registry.COMMON_ANCHORS.get(
                field_name, [field_name]
            )
            
            # Use first anchor text
            anchor_text = anchor_texts[0]
            
            self.coordinate_registry.update_from_correction(
                style_tag=style_tag,
                field_name=field_name,
                anchor_text=anchor_text,
                correction_data=correction,
                ocr_boxes=ocr_boxes
            )


# Convenience function
def extract_invoice(file_path: Union[str, Path], 
                   style_hint: Optional[str] = None,
                   db_session=None) -> Dict[str, Any]:
    """Quick extraction function"""
    extractor = SimpleInvoiceExtractor(db_session)
    return extractor.extract_invoice(file_path, style_hint)
