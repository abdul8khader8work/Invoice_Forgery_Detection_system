"""
Invoice OCR Pipeline - OCR Extraction Module
Phase 2: Extraction Engine (The "Eyes")
"""

import numpy as np
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass
from paddleocr import PaddleOCR
import logging

logger = logging.getLogger(__name__)


@dataclass
class OCRResult:
    """Single OCR detection result"""
    text: str
    confidence: float
    bbox: List[List[int]]  # [[x1, y1], [x2, y2], [x3, y3], [x4, y4]]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'text': self.text,
            'confidence': self.confidence,
            'bbox': self.bbox
        }


@dataclass
class OCROutput:
    """Complete OCR output with all results"""
    results: List[OCRResult]
    image_shape: Tuple[int, int]
    filtered_count: int
    
    def get_high_confidence_results(self, threshold: float = 0.85) -> List[OCRResult]:
        """Get results above confidence threshold"""
        return [r for r in self.results if r.confidence >= threshold]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'results': [r.to_dict() for r in self.results],
            'image_shape': self.image_shape,
            'filtered_count': self.filtered_count,
            'total_detected': len(self.results)
        }


class PaddleOCRExtractor:
    """
    PaddleOCR-based text extraction with confidence filtering.
    Initialized with use_angle_cls=True to handle rotated text.
    """
    
    def __init__(self, 
                 use_angle_cls: bool = True,
                 lang: str = 'en',
                 confidence_threshold: float = 0.85,
                 show_log: bool = False):
        """
        Initialize PaddleOCR engine.
        
        Args:
            use_angle_cls: Enable angle classification for rotated text
            lang: Language code ('en', 'ch', etc.)
            confidence_threshold: Minimum confidence to keep results
            show_log: Whether to show PaddleOCR logs
        """
        self.confidence_threshold = confidence_threshold
        
        try:
            self.ocr = PaddleOCR(
                use_angle_cls=use_angle_cls,
                lang=lang,
                show_log=show_log,
                use_gpu=False  # CPU for compatibility
            )
            logger.info(f"PaddleOCR initialized (lang={lang}, angle_cls={use_angle_cls})")
        except Exception as e:
            logger.error(f"Failed to initialize PaddleOCR: {e}")
            raise
    
    def extract(self, image: np.ndarray) -> OCROutput:
        """
        Perform OCR on preprocessed image.
        
        Args:
            image: Preprocessed image (numpy array)
            
        Returns:
            OCROutput with filtered results
            
        Raises:
            ValueError: If no text detected
        """
        image_shape = image.shape[:2]
        
        try:
            # PaddleOCR inference
            result = self.ocr.ocr(image, cls=True)
            
            if result is None or len(result) == 0:
                raise ValueError("No text detected in image")
            
            # Parse results (PaddleOCR returns list of lists)
            ocr_results = []
            filtered_count = 0
            
            # Handle different PaddleOCR output formats
            if isinstance(result, list):
                for line in result:
                    if line is None:
                        continue
                    for item in line:
                        if item is None:
                            continue
                        # Parse bbox and text
                        bbox, text_info = item
                        text = text_info[0]
                        confidence = text_info[1]
                        
                        ocr_result = OCRResult(
                            text=text,
                            confidence=confidence,
                            bbox=bbox
                        )
                        
                        # Filter low confidence
                        if confidence >= self.confidence_threshold:
                            ocr_results.append(ocr_result)
                        else:
                            filtered_count += 1
                            logger.debug(f"Filtered low confidence: '{text}' ({confidence:.2f})")
            
            if not ocr_results:
                logger.warning(f"All {filtered_count} detections filtered out (threshold: {self.confidence_threshold})")
                raise ValueError("No text met confidence threshold")
            
            logger.info(f"OCR complete: {len(ocr_results)} results, {filtered_count} filtered")
            
            return OCROutput(
                results=ocr_results,
                image_shape=image_shape,
                filtered_count=filtered_count
            )
            
        except Exception as e:
            logger.error(f"OCR extraction failed: {e}")
            raise
    
    def extract_raw(self, image: np.ndarray) -> List[Dict[str, Any]]:
        """
        Extract raw OCR results without filtering.
        Useful for debugging.
        """
        result = self.ocr.ocr(image, cls=True)
        raw_results = []
        
        if result and isinstance(result, list):
            for line in result:
                if line is None:
                    continue
                for item in line:
                    if item is None:
                        continue
                    bbox, text_info = item
                    raw_results.append({
                        'text': text_info[0],
                        'confidence': text_info[1],
                        'bbox': bbox
                    })
        
        return raw_results


# Convenience function
def extract_text(image: np.ndarray, 
                  confidence_threshold: float = 0.85) -> OCROutput:
    """Quick OCR extraction"""
    extractor = PaddleOCRExtractor(confidence_threshold=confidence_threshold)
    return extractor.extract(image)
