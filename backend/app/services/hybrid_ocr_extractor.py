"""
Hybrid OCR Pipeline - Tries PaddleOCR first, falls back to EasyOCR
Best of both worlds: PaddleOCR accuracy with EasyOCR reliability
"""

import cv2
import numpy as np
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)


@dataclass
class HybridOCRResult:
    """Unified OCR result from any engine"""
    text: str
    confidence: float
    bbox: List[List[int]]  # [[x1, y1], [x2, y2], [x3, y3], [x4, y4]]
    engine: str  # 'paddle' or 'easyocr'
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'text': self.text,
            'confidence': self.confidence,
            'bbox': self.bbox,
            'engine': self.engine
        }


@dataclass
class HybridOCROutput:
    """Complete hybrid OCR output"""
    results: List[HybridOCRResult]
    engine_used: str
    fallback_triggered: bool
    preprocessing_applied: bool = False
    
    def get_high_confidence_results(self, threshold: float = 0.7) -> List[HybridOCRResult]:
        """Get results above confidence threshold"""
        return [r for r in self.results if r.confidence >= threshold]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'results': [r.to_dict() for r in self.results],
            'engine_used': self.engine_used,
            'fallback_triggered': self.fallback_triggered,
            'preprocessing_applied': self.preprocessing_applied,
            'total_results': len(self.results)
        }


class HybridOCRExtractor:
    """
    Hybrid OCR that tries PaddleOCR first, falls back to EasyOCR.
    Also includes advanced image preprocessing for better accuracy.
    """
    
    def __init__(self, 
                 confidence_threshold: float = 0.7,
                 enable_preprocessing: bool = True,
                 min_text_length: int = 3):
        """
        Initialize hybrid OCR extractor.
        
        Args:
            confidence_threshold: Minimum confidence to accept results
            enable_preprocessing: Apply DPI scaling, binarization, perspective correction
            min_text_length: Minimum text length to keep
        """
        self.confidence_threshold = confidence_threshold
        self.enable_preprocessing = enable_preprocessing
        self.min_text_length = min_text_length
        
        # Initialize engines (lazy loading)
        self._paddle_ocr = None
        self._easy_ocr = None
        
        logger.info("HybridOCRExtractor initialized")
    
    def _get_paddle_ocr(self):
        """Lazy initialization of PaddleOCR"""
        if self._paddle_ocr is None:
            try:
                from paddleocr import PaddleOCR
                self._paddle_ocr = PaddleOCR(
                    use_angle_cls=True,
                    lang='en',
                    show_log=False,
                    use_gpu=False
                )
                logger.info("PaddleOCR initialized")
            except Exception as e:
                logger.error(f"Failed to initialize PaddleOCR: {e}")
                raise
        return self._paddle_ocr
    
    def _get_easy_ocr(self):
        """Lazy initialization of EasyOCR"""
        if self._easy_ocr is None:
            try:
                import easyocr
                self._easy_ocr = easyocr.Reader(['en'], gpu=False)
                logger.info("EasyOCR initialized")
            except Exception as e:
                logger.error(f"Failed to initialize EasyOCR: {e}")
                raise
        return self._easy_ocr
    
    def extract(self, image: np.ndarray) -> HybridOCROutput:
        """
        Extract text using hybrid approach.
        
        Strategy:
        1. Try PaddleOCR with preprocessing
        2. If poor results, try PaddleOCR without preprocessing
        3. If still poor, fall back to EasyOCR
        
        Args:
            image: Input image (BGR format from OpenCV)
            
        Returns:
            HybridOCROutput with results and metadata
        """
        results = []
        engine_used = "none"
        fallback_triggered = False
        preprocessing_applied = False
        
        # Try 1: PaddleOCR with preprocessing
        if self.enable_preprocessing:
            try:
                from .image_processor import ImageProcessor
                processor = ImageProcessor(target_dpi=300)
                processed = processor.process(image)
                preprocessing_applied = True
                
                results = self._extract_with_paddle(processed.image)
                
                if self._is_good_result(results):
                    engine_used = "paddle (preprocessed)"
                    logger.info(f"PaddleOCR with preprocessing: {len(results)} results")
                    
                    return HybridOCROutput(
                        results=results,
                        engine_used=engine_used,
                        fallback_triggered=False,
                        preprocessing_applied=True
                    )
                else:
                    logger.warning("PaddleOCR with preprocessing gave poor results, trying without...")
                    
            except Exception as e:
                logger.warning(f"PaddleOCR with preprocessing failed: {e}")
        
        # Try 2: PaddleOCR without preprocessing
        try:
            results = self._extract_with_paddle(image)
            
            if self._is_good_result(results):
                engine_used = "paddle (raw)"
                logger.info(f"PaddleOCR raw: {len(results)} results")
                
                return HybridOCROutput(
                    results=results,
                    engine_used=engine_used,
                    fallback_triggered=preprocessing_applied,  # Fell back from preprocessed
                    preprocessing_applied=False
                )
            else:
                logger.warning("PaddleOCR gave poor results, falling back to EasyOCR...")
                
        except Exception as e:
            logger.warning(f"PaddleOCR failed: {e}, falling back to EasyOCR...")
        
        # Try 3: EasyOCR fallback
        try:
            results = self._extract_with_easyocr(image)
            engine_used = "easyocr (fallback)"
            fallback_triggered = True
            logger.info(f"EasyOCR fallback: {len(results)} results")
            
            return HybridOCROutput(
                results=results,
                engine_used=engine_used,
                fallback_triggered=True,
                preprocessing_applied=False
            )
            
        except Exception as e:
            logger.error(f"EasyOCR also failed: {e}")
            raise ValueError(f"All OCR engines failed: {e}")
    
    def _extract_with_paddle(self, image: np.ndarray) -> List[HybridOCRResult]:
        """Extract text using PaddleOCR"""
        ocr = self._get_paddle_ocr()
        
        # Convert to RGB if needed (PaddleOCR expects RGB)
        if len(image.shape) == 3 and image.shape[2] == 3:
            # Check if grayscale (all channels equal)
            if np.all(image[:, :, 0] == image[:, :, 1]):
                rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            else:
                rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        else:
            rgb_image = cv2.cvtColor(image, cv2.COLOR_GRAY2RGB) if len(image.shape) == 2 else image
        
        result = ocr.ocr(rgb_image, cls=True)
        
        results = []
        if result and isinstance(result, list):
            for line in result:
                if line is None:
                    continue
                for item in line:
                    if item is None:
                        continue
                    bbox, text_info = item
                    text = text_info[0]
                    confidence = text_info[1]
                    
                    if len(text) >= self.min_text_length:
                        results.append(HybridOCRResult(
                            text=text,
                            confidence=confidence,
                            bbox=bbox,
                            engine='paddle'
                        ))
        
        return results
    
    def _extract_with_easyocr(self, image: np.ndarray) -> List[HybridOCRResult]:
        """Extract text using EasyOCR"""
        reader = self._get_easy_ocr()
        
        # EasyOCR expects RGB
        if len(image.shape) == 3:
            rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        else:
            rgb_image = cv2.cvtColor(image, cv2.COLOR_GRAY2RGB)
        
        result = reader.readtext(rgb_image)
        
        results = []
        for detection in result:
            bbox, text, confidence = detection
            
            if len(text) >= self.min_text_length:
                results.append(HybridOCRResult(
                    text=text,
                    confidence=confidence,
                    bbox=bbox.tolist() if hasattr(bbox, 'tolist') else bbox,
                    engine='easyocr'
                ))
        
        return results
    
    def _is_good_result(self, results: List[HybridOCRResult]) -> bool:
        """
        Determine if OCR results are good enough.
        
        Criteria:
        - At least 5 text regions detected
        - Average confidence > 0.6
        - At least one high-confidence result (>0.8)
        """
        if len(results) < 5:
            return False
        
        avg_confidence = np.mean([r.confidence for r in results])
        if avg_confidence < 0.6:
            return False
        
        has_high_confidence = any(r.confidence > 0.8 for r in results)
        if not has_high_confidence:
            return False
        
        return True


# Convenience function
def extract_text_hybrid(image: np.ndarray, 
                         confidence_threshold: float = 0.7) -> HybridOCROutput:
    """Quick hybrid OCR extraction"""
    extractor = HybridOCRExtractor(confidence_threshold=confidence_threshold)
    return extractor.extract(image)
