"""
PaddleOCR Extraction Engine
Converts PaddleOCR output into structured key-value pairs
"""

import os
import cv2
import numpy as np
from typing import Dict, List, Optional, Tuple, Any, Union
from pathlib import Path
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)


@dataclass
class PaddleOCRResult:
    """Structured PaddleOCR output"""
    boxes: List[Dict[str, Any]]  # Bounding boxes with text
    text_lines: List[str]       # Detected text lines
    confidences: List[float]    # Confidence scores
    full_text: str              # Concatenated text
    
    def to_spatial_boxes(self) -> List[Dict[str, Any]]:
        """Convert to format expected by SpatialIntelligenceEngine"""
        spatial_boxes = []
        for i, box in enumerate(self.boxes):
            spatial_boxes.append({
                'x': box['x'],
                'y': box['y'],
                'width': box['width'],
                'height': box['height'],
                'text': box['text'],
                'confidence': box.get('confidence', 0.95)
            })
        return spatial_boxes


class PaddleOCREngine:
    """
    Production-ready PaddleOCR wrapper
    Handles image preprocessing, OCR, and result structuring
    """
    
    def __init__(self, 
                 use_gpu: bool = False,
                 lang: str = 'en',
                 det_db_thresh: float = 0.3,
                 det_db_box_thresh: float = 0.5,
                 rec_batch_num: int = 6):
        """
        Initialize PaddleOCR engine
        
        Args:
            use_gpu: Whether to use GPU acceleration
            lang: Language code (en, ch, etc.)
            det_db_thresh: Text detection threshold
            det_db_box_thresh: Text box detection threshold
            rec_batch_num: Batch size for recognition
        """
        self.use_gpu = use_gpu
        self.lang = lang
        self.det_db_thresh = det_db_thresh
        self.det_db_box_thresh = det_db_box_thresh
        self.rec_batch_num = rec_batch_num
        
        self._ocr = None
        self._is_initialized = False
        
    def _initialize(self):
        """Lazy initialization of OCR engine - tries PaddleOCR, falls back to EasyOCR"""
        if self._is_initialized:
            return
        
        # Try PaddleOCR first
        try:
            from paddleocr import PaddleOCR
            
            logger.info("Initializing PaddleOCR engine...")
            
            self._ocr = PaddleOCR(
                use_angle_cls=True,
                lang=self.lang,
                use_gpu=self.use_gpu,
                det_db_thresh=self.det_db_thresh,
                det_db_box_thresh=self.det_db_box_thresh,
                rec_batch_num=self.rec_batch_num,
                show_log=False
            )
            
            self._ocr_type = 'paddle'
            self._is_initialized = True
            logger.info("PaddleOCR initialized successfully")
            return
            
        except ImportError:
            logger.warning("PaddleOCR not available, falling back to EasyOCR")
        
        # Fall back to EasyOCR
        try:
            import easyocr
            
            logger.info("Initializing EasyOCR engine...")
            
            self._ocr = easyocr.Reader(
                ['en'],
                gpu=self.use_gpu,
                verbose=False
            )
            
            self._ocr_type = 'easy'
            self._is_initialized = True
            logger.info("EasyOCR initialized successfully")
            
        except ImportError:
            logger.error("No OCR engine available. Install paddleocr or easyocr.")
            raise
    
    def preprocess_image(self, image_path: Union[str, Path]) -> np.ndarray:
        """
        Preprocess image for better OCR results
        
        Steps:
        1. Deskew (correct rotation)
        2. Denoise
        3. Contrast enhancement
        4. Binarization (optional)
        """
        image = cv2.imread(str(image_path))
        if image is None:
            raise ValueError(f"Could not load image: {image_path}")
        
        # Convert to grayscale
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
        
        # Deskew using Hough Transform
        gray = self._deskew(gray)
        
        # Denoise
        denoised = cv2.fastNlMeansDenoising(gray, None, 10, 7, 21)
        
        # Contrast enhancement using CLAHE
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(denoised)
        
        return enhanced
    
    def _deskew(self, image: np.ndarray, max_skew: float = 5.0) -> np.ndarray:
        """
        Correct image rotation
        
        Args:
            image: Grayscale image
            max_skew: Maximum allowed skew angle in degrees
        
        Returns:
            Deskewed image
        """
        # Detect edges
        edges = cv2.Canny(image, 50, 150, apertureSize=3)
        
        # Detect lines using Hough Transform
        lines = cv2.HoughLinesP(edges, 1, np.pi/180, 100, minLineLength=100, maxLineGap=10)
        
        if lines is None or len(lines) == 0:
            return image
        
        # Calculate dominant angle
        angles = []
        for line in lines:
            x1, y1, x2, y2 = line[0]
            angle = np.degrees(np.arctan2(y2 - y1, x2 - x1))
            # Normalize angle to [-90, 90]
            if angle > 90:
                angle -= 180
            elif angle < -90:
                angle += 180
            # Only consider near-horizontal lines
            if abs(angle) < max_skew:
                angles.append(angle)
        
        if not angles:
            return image
        
        # Get median angle (robust to outliers)
        median_angle = np.median(angles)
        
        if abs(median_angle) < 0.5:
            return image  # Already straight
        
        # Rotate image
        height, width = image.shape[:2]
        center = (width // 2, height // 2)
        rotation_matrix = cv2.getRotationMatrix2D(center, median_angle, 1.0)
        rotated = cv2.warpAffine(image, rotation_matrix, (width, height), 
                                  flags=cv2.INTER_CUBIC, 
                                  borderMode=cv2.BORDER_CONSTANT,
                                  borderValue=255)
        
        return rotated
    
    def extract_text(self, image_path: Union[str, Path], preprocess: bool = True) -> PaddleOCRResult:
        """
        Extract text from image using PaddleOCR
        
        Args:
            image_path: Path to image file
            preprocess: Whether to apply preprocessing
        
        Returns:
            PaddleOCRResult with structured output
        """
        self._initialize()
        
        if preprocess:
            # Save preprocessed image temporarily
            preprocessed = self.preprocess_image(image_path)
            temp_path = str(image_path) + ".temp.png"
            cv2.imwrite(temp_path, preprocessed)
            image_path = temp_path
        
        try:
            boxes = []
            text_lines = []
            confidences = []
            
            if self._ocr_type == 'paddle':
                # Run PaddleOCR
                result = self._ocr.ocr(str(image_path), cls=True)
                
                # Parse PaddleOCR results
                if result and result[0]:
                    for line in result[0]:
                        if line:
                            bbox_coords = line[0]
                            text, confidence = line[1]
                            
                            x_coords = [p[0] for p in bbox_coords]
                            y_coords = [p[1] for p in bbox_coords]
                            
                            x = min(x_coords)
                            y = min(y_coords)
                            width = max(x_coords) - x
                            height = max(y_coords) - y
                            
                            box_data = {
                                'x': x,
                                'y': y,
                                'width': width,
                                'height': height,
                                'text': text,
                                'confidence': confidence,
                                'raw_bbox': bbox_coords
                            }
                            
                            boxes.append(box_data)
                            text_lines.append(text)
                            confidences.append(confidence)
            
            else:
                # Run EasyOCR
                result = self._ocr.readtext(str(image_path))
                
                # Parse EasyOCR results: [(bbox, text, confidence), ...]
                for detection in result:
                    bbox, text, confidence = detection
                    
                    # bbox is [[x1,y1], [x2,y1], [x2,y2], [x1,y2]]
                    x_coords = [p[0] for p in bbox]
                    y_coords = [p[1] for p in bbox]
                    
                    x = min(x_coords)
                    y = min(y_coords)
                    width = max(x_coords) - x
                    height = max(y_coords) - y
                    
                    box_data = {
                        'x': x,
                        'y': y,
                        'width': width,
                        'height': height,
                        'text': text,
                        'confidence': confidence,
                        'raw_bbox': bbox
                    }
                    
                    boxes.append(box_data)
                    text_lines.append(text)
                    confidences.append(confidence)
            
            # Clean up temp file
            if preprocess and os.path.exists(temp_path):
                os.remove(temp_path)
            
            full_text = ' '.join(text_lines)
            
            return PaddleOCRResult(
                boxes=boxes,
                text_lines=text_lines,
                confidences=confidences,
                full_text=full_text
            )
            
        except Exception as e:
            logger.error(f"OCR extraction failed: {e}")
            # Clean up on error
            if preprocess and 'temp_path' in locals() and os.path.exists(temp_path):
                os.remove(temp_path)
            raise
    
    def extract_text_from_bytes(self, image_bytes: bytes, preprocess: bool = True) -> PaddleOCRResult:
        """
        Extract text from image bytes (for API use)
        
        Args:
            image_bytes: Raw image bytes
            preprocess: Whether to apply preprocessing
        
        Returns:
            PaddleOCRResult
        """
        # Convert bytes to numpy array
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            raise ValueError("Could not decode image bytes")
        
        # Save to temp file (PaddleOCR requires file path)
        import tempfile
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
            temp_path = tmp.name
            cv2.imwrite(temp_path, image)
        
        try:
            result = self.extract_text(temp_path, preprocess=preprocess)
            return result
        finally:
            # Clean up temp file
            if os.path.exists(temp_path):
                os.remove(temp_path)
    
    def get_engine_info(self) -> Dict[str, Any]:
        """Get information about the OCR engine"""
        return {
            'engine': 'PaddleOCR' if getattr(self, '_ocr_type', None) == 'paddle' else 'EasyOCR',
            'initialized': self._is_initialized,
            'language': self.lang,
            'use_gpu': self.use_gpu,
            'detection_threshold': self.det_db_thresh
        }


class ActiveLearningExtractor:
    """
    Main extraction class that combines:
    - PaddleOCR for text detection
    - Template Registry for vendor matching
    - Spatial Intelligence for field extraction
    """
    
    def __init__(self, db_session=None):
        self.ocr_engine = PaddleOCREngine()
        from app.services.template_registry import TemplateRegistryManager
        from app.services.spatial_intelligence import SpatialIntelligenceEngine
        
        self.template_manager = TemplateRegistryManager(db_session)
        self.spatial_engine_class = SpatialIntelligenceEngine
    
    def process_invoice(
        self,
        image_path: Union[str, Path],
        style_hint: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Process invoice through complete pipeline
        
        Flow:
        1. OCR extraction (PaddleOCR)
        2. Vendor fingerprinting
        3. Template matching
        4. Spatial field extraction
        5. Confidence scoring
        
        Args:
            image_path: Path to invoice image
            style_hint: Optional style tag to force specific template
        
        Returns:
            Complete extraction result
        """
        import time
        start_time = time.time()
        
        # Step 1: OCR
        logger.info(f"Starting OCR on {image_path}")
        ocr_result = self.ocr_engine.extract_text(image_path)
        
        # Step 2: Vendor fingerprinting
        logger.info("Extracting vendor fingerprint...")
        fingerprint = self.template_manager.extract_vendor_fingerprint(
            ocr_result.to_spatial_boxes()
        )
        fp_hash = fingerprint.compute_hash()
        
        # Step 3: Template matching
        template = None
        is_new_template = False
        
        if style_hint:
            # Try to find by style tag
            template = self.template_manager.db.query(
                self.template_manager.db.query(
                    TemplateRegistry
                ).filter(
                    TemplateRegistry.style_tag == style_hint
                ).first()
            )
        
        if not template:
            # Get or create by fingerprint
            template, is_new_template = self.template_manager.get_or_create_template(
                fingerprint
            )
        
        logger.info(f"Using template: {template.style_tag} (new={is_new_template})")
        
        # Step 4: Spatial extraction
        logger.info("Running spatial field extraction...")
        spatial_engine = self.spatial_engine_class(ocr_result.to_spatial_boxes())
        
        field_map = template.field_map or {}
        extracted_data, confidence_scores, extraction_metadata = \
            spatial_engine.extract_all_fields(field_map)
        
        # Step 5: Calculate overall confidence
        overall_confidence = self._calculate_overall_confidence(
            confidence_scores,
            template.confidence_score,
            is_new_template
        )
        
        # Step 6: Determine if verification needed
        needs_verification = self._determine_verification_need(
            extracted_data,
            confidence_scores,
            overall_confidence
        )
        
        processing_time = int((time.time() - start_time) * 1000)
        
        # Build result
        result = {
            'success': True,
            'file_id': None,  # Will be set by caller
            'vendor_fingerprint': fp_hash,
            'template_id': template.id,
            'style_tag': template.style_tag,
            'is_new_template': is_new_template,
            'extracted_data': extracted_data,
            'confidence_scores': confidence_scores,
            'overall_confidence': overall_confidence,
            'needs_verification': needs_verification,
            'verification_fields': [
                f for f, score in confidence_scores.items() 
                if score < 0.7 or f not in extracted_data
            ],
            'processing_time_ms': processing_time,
            'ocr_output': {
                'text': ocr_result.full_text,
                'boxes': ocr_result.to_spatial_boxes()
            },
            'extraction_metadata': extraction_metadata
        }
        
        # Log extraction
        self._log_extraction(result, template.id, ocr_result.to_spatial_boxes())
        
        return result
    
    def _calculate_overall_confidence(
        self,
        field_scores: Dict[str, float],
        template_confidence: float,
        is_new_template: bool
    ) -> float:
        """Calculate overall extraction confidence"""
        if not field_scores:
            return 0.0
        
        # Average field confidence
        avg_field_conf = sum(field_scores.values()) / len(field_scores)
        
        # Weight by critical fields
        critical_fields = ['total', 'date', 'vendor_name']
        critical_scores = [
            field_scores.get(f, 0.0) for f in critical_fields
        ]
        critical_avg = sum(critical_scores) / len(critical_scores) if critical_scores else 0.0
        
        # Combine: 40% overall fields, 40% critical fields, 20% template confidence
        overall = (avg_field_conf * 0.4 + critical_avg * 0.4 + template_confidence * 0.2)
        
        # Penalty for new templates
        if is_new_template:
            overall *= 0.85
        
        return round(min(1.0, overall), 3)
    
    def _determine_verification_need(
        self,
        extracted_data: Dict[str, Any],
        confidence_scores: Dict[str, float],
        overall_confidence: float
    ) -> bool:
        """Determine if human verification is required"""
        # Critical fields that must be present
        critical_fields = ['total', 'date']
        
        # Check if critical fields missing or low confidence
        for field in critical_fields:
            if field not in extracted_data:
                return True
            if confidence_scores.get(field, 0.0) < 0.6:
                return True
        
        # Check overall confidence
        if overall_confidence < 0.7:
            return True
        
        # Check for any field below threshold
        low_confidence_count = sum(1 for s in confidence_scores.values() if s < 0.5)
        if low_confidence_count >= 2:
            return True
        
        return False
    
    def _log_extraction(
        self,
        result: Dict[str, Any],
        template_id: int,
        raw_ocr_boxes: List[Dict]
    ):
        """Log extraction to database for audit trail"""
        from app.models.active_learning_models import ExtractionLog
        
        log = ExtractionLog(
            file_id=result.get('file_id', 'unknown'),
            template_id=template_id,
            ocr_engine='paddleocr',
            raw_ocr_output={'boxes': raw_ocr_boxes},
            extracted_data=result['extracted_data'],
            confidence_scores=result['confidence_scores'],
            template_match_score=result['overall_confidence'],
            vendor_fingerprint=result['vendor_fingerprint'],
            processing_time_ms=result['processing_time_ms'],
            was_corrected=False
        )
        
        self.template_manager.db.add(log)
        self.template_manager.db.commit()
        
        # Store log ID in result
        result['log_id'] = log.id


# Convenience function for API use
def process_invoice_image(
    image_path: Union[str, Path],
    style_hint: Optional[str] = None,
    db_session=None
) -> Dict[str, Any]:
    """
    Process invoice image through active learning pipeline
    
    Args:
        image_path: Path to invoice image
        style_hint: Optional style tag to force specific template
        db_session: Database session (optional)
    
    Returns:
        Extraction result dictionary
    """
    extractor = ActiveLearningExtractor(db_session)
    return extractor.process_invoice(image_path, style_hint)
