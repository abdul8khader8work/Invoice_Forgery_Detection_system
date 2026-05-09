"""
Extraction Engine - Advanced OCR with Bounding Boxes and Confidence Scoring
"""
import numpy as np
import cv2
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional
from dataclasses import dataclass
from PIL import Image
import logging
from datetime import datetime

from .advanced_extraction import extract_invoice_data, SmartInvoiceExtractor
from .ocr_service import OCRService
from .hybrid_ocr_extractor import HybridOCRExtractor, HybridOCRResult, HybridOCROutput

# Try to import OCR engines
try:
    import easyocr
    EASYOCR_AVAILABLE = True
except ImportError:
    EASYOCR_AVAILABLE = False
    logging.warning("EasyOCR not available")

try:
    import pytesseract
    TESSERACT_AVAILABLE = True
except ImportError:
    TESSERACT_AVAILABLE = False
    logging.warning("Tesseract not available")

# Initialize logger
logger = logging.getLogger(__name__)


@dataclass
class OcrWord:
    """Single OCR result with metadata"""
    text: str
    confidence: float
    bbox: List[int]  # [x1, y1, x2, y2]
    center: Tuple[float, float] = None
    
    def __post_init__(self):
        if self.center is None:
            self.center = (
                (self.bbox[0] + self.bbox[2]) / 2,
                (self.bbox[1] + self.bbox[3]) / 2
            )


@dataclass
class ExtractedField:
    """Extracted field with confidence scoring"""
    field: str
    value: str
    confidence: float
    bbox: List[int]
    ocr_confidence: float
    pattern_match_score: float
    requires_manual_check: bool = False
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "field": self.field,
            "value": self.value,
            "confidence": round(self.confidence, 2),
            "bbox": self.bbox,
            "ocr_confidence": round(self.ocr_confidence, 2),
            "pattern_match_score": round(self.pattern_match_score, 2),
            "requires_manual_check": self.requires_manual_check
        }


class ExtractionProcessor:
    """
    Advanced OCR processor with bounding boxes and confidence scoring
    """
    
    # Anchor patterns for different fields
    ANCHORS = {
        "vendor_name": {
            "keywords": ["vendor", "seller", "from", "billed by", "sold by", "company", "business"],
            "patterns": [
                r"^[A-Z][A-Za-z0-9\s&.,]+(?:Inc|LLC|Ltd|Corp|Company|Co\.?)?$",
                r"^[A-Z][A-Za-z\s]+(?:Technologies|Solutions|Services|Group)"
            ],
            "location_hints": ["top", "header"]
        },
        "invoice_number": {
            "keywords": ["invoice", "inv #", "inv no", "invoice #", "invoice no", "bill #", "ref"],
            "patterns": [
                r"(?:INV|INV-|IN|BILL|REF)[-\s]?#?\s*(\d+)",
                r"(?:Invoice|Bill)\s*(?:#|No\.?|Number)?\s*[:]?\s*(\d+)",
                r"#\s*(\d{4,})"
            ]
        },
        "invoice_date": {
            "keywords": ["date", "invoice date", "date issued", "issued on"],
            "patterns": [
                r"(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})",
                r"(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{2,4})",
                r"((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4})"
            ]
        },
        "subtotal": {
            "keywords": ["subtotal", "sub-total", "sub total", "net", "amount", "before tax"],
            "patterns": [
                r"(?:Subtotal|Sub-total|Net)\s*[:]?\s*[$]?\s*([\d,]+\.?\d{0,2})",
                r"[$]\s*([\d,]+\.\d{2})"
            ],
            "proximity_to": ["total", "tax"]
        },
        "tax": {
            "keywords": ["tax", "gst", "vat", "sales tax", "hst"],
            "patterns": [
                r"(?:Tax|GST|VAT|HST)\s*(?:@?\s*\d+%?)?\s*[:]?\s*[$]?\s*([\d,]+\.?\d{0,2})",
                r"[$]\s*([\d,]+\.\d{2})\s*(?:GST|VAT|Tax)"
            ]
        },
        "total": {
            "keywords": ["total", "grand total", "amount due", "balance", "total due", "payable", "final amount"],
            "patterns": [
                r"(?:Grand\s+Total|Total\s+Amount|Amount\s+Due|Balance\s+Due|Total\s+Payable)\s*[:]?\s*[$]?\s*([\d,]+\.?\d{0,2})",
                r"Total\s*[:]?\s*[$]?\s*([\d,]+\.\d{2})",
                r"[$]\s*([\d,]+\.\d{2})\s*(?:Total|Due)"
            ],
            "priority": 10
        }
    }
    
    def __init__(self, use_hybrid_ocr: bool = True):
        self.easyocr_reader = None
        self._init_engines()
        self.smart_extractor = SmartInvoiceExtractor()
        
        # Initialize hybrid OCR extractor (tries PaddleOCR first, falls back to EasyOCR)
        self.use_hybrid_ocr = use_hybrid_ocr
        if use_hybrid_ocr:
            try:
                self.hybrid_extractor = HybridOCRExtractor(
                    confidence_threshold=0.7,
                    enable_preprocessing=True
                )
                print("Hybrid OCR extractor initialized (PaddleOCR + EasyOCR fallback)")
            except Exception as e:
                print(f"Hybrid OCR initialization failed: {e}")
                self.hybrid_extractor = None
                self.use_hybrid_ocr = False
        
    def _init_engines(self):
        """Initialize OCR engines"""
        if EASYOCR_AVAILABLE:
            try:
                self.easyocr_reader = easyocr.Reader(['en'], gpu=False)
                print("EasyOCR initialized successfully")
            except Exception as e:
                print(f"EasyOCR initialization failed: {e}")
                self.easyocr_reader = None
                
    def process_image(self, image_path: Path) -> Dict[str, Any]:
        """
        Process an image and extract structured fields
        """
        print(f"Processing image: {image_path}")
        
        # Step 1: Load and preprocess image
        img = self._load_image(image_path)
        if img is None:
            raise ValueError(f"Could not load image: {image_path}")
            
        # Step 2: Run OCR with bounding boxes
        ocr_words = self._extract_text_with_boxes(img)
        print(f"OCR found {len(ocr_words)} words")
        
        # Step 3: Extract fields using anchor-based mapping (basic extraction)
        extracted_fields = self._extract_fields(ocr_words, img.shape)
        
        # Step 3b: Also run smart extraction on raw OCR text for enhanced results
        raw_text = ' '.join([w.text for w in ocr_words])
        smart_result = self.extract_with_smart_extractor(raw_text)
        
        # Merge smart extraction results with basic extraction
        merged_fields = self._merge_extraction_results(extracted_fields, smart_result)
        
        # Step 4: Build response
        return {
            "fields": [f.to_dict() for f in merged_fields],
            "raw_ocr": [
                {"text": w.text, "confidence": w.confidence, "bbox": w.bbox}
                for w in ocr_words
            ],
            "image_dimensions": img.shape[:2],
            "requires_manual_check": any(f.requires_manual_check for f in extracted_fields)
        }
        
    def extract_with_smart_extractor(self, raw_text: str) -> Dict[str, Any]:
        """
        Use SmartInvoiceExtractor for enhanced field extraction.
        Falls back to basic extraction if smart extraction fails.
        """
        try:
            # Use the new advanced extraction system
            result = self.smart_extractor.extract_all(raw_text)
            
            # Log successful extraction
            extracted_fields = [k for k, v in result['extracted_data'].items() if v is not None]
            logger.info(f"Smart extraction successful. Fields found: {extracted_fields}")
            
            return result
            
        except Exception as e:
            logger.error(f"Smart extraction failed: {e}")
            # Return empty result - will fall back to basic extraction
            return {
                'extracted_data': {},
                'confidence_scores': {},
                'raw_text': raw_text[:1000]
            }
    
    def _merge_extraction_results(self, basic_fields: List[Any], smart_result: Dict[str, Any]) -> List[Any]:
        """
        Merge smart extraction results with basic extraction.
        Prefer smart extraction when confidence is higher.
        """
        if not smart_result.get('extracted_data'):
            return basic_fields
        
        # Convert basic fields to dict for easier merging
        field_dict = {f.field: f for f in basic_fields}
        
        # Add smart extraction results
        for field_type, value in smart_result['extracted_data'].items():
            if value is not None:
                confidence = smart_result.get('confidence_scores', {}).get(field_type, 0.0)
                
                # If field not in basic or smart has higher confidence, use smart
                if field_type not in field_dict or confidence > field_dict[field_type].confidence:
                    field_dict[field_type] = ExtractedField(
                        field=field_type,
                        value=str(value),
                        confidence=confidence,
                        bbox=[0, 0, 0, 0],
                        ocr_confidence=confidence,
                        pattern_match_score=confidence,
                        requires_manual_check=confidence < 0.7
                    )
        
        return list(field_dict.values())
    
    def _load_image(self, image_path: Path) -> Optional[np.ndarray]:
        """Load image from path"""
        try:
            img = cv2.imread(str(image_path))
            if img is None:
                # Try PIL fallback
                pil_img = Image.open(image_path)
                img = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
            return img
        except Exception as e:
            print(f"Error loading image: {e}")
            return None
            
    def _extract_text_with_boxes(self, img: np.ndarray) -> List[OcrWord]:
        """
        Advanced OCR extraction using hybrid approach.
        Tries PaddleOCR first (with preprocessing), falls back to EasyOCR/Tesseract.
        """
        words = []
        
        # Primary: Hybrid OCR (PaddleOCR -> EasyOCR fallback)
        if self.use_hybrid_ocr and self.hybrid_extractor is not None:
            try:
                print("Attempting hybrid OCR extraction...")
                hybrid_output = self.hybrid_extractor.extract(img)
                
                print(f"Hybrid OCR used engine: {hybrid_output.engine_used}, "
                      f"results: {len(hybrid_output.results)}, "
                      f"fallback_triggered: {hybrid_output.fallback_triggered}")
                
                # Convert HybridOCRResult to OcrWord
                for result in hybrid_output.results:
                    # Convert bbox to simple [x1, y1, x2, y2] format
                    bbox = result.bbox
                    x_coords = [p[0] for p in bbox]
                    y_coords = [p[1] for p in bbox]
                    x1, y1, x2, y2 = min(x_coords), min(y_coords), max(x_coords), max(y_coords)
                    
                    words.append(OcrWord(
                        text=result.text.strip(),
                        confidence=float(result.confidence),
                        bbox=[int(x1), int(y1), int(x2), int(y2)]
                    ))
                
                print(f"Hybrid OCR extracted {len(words)} words")
                
                # If we got good results, return them
                if len(words) >= 5:
                    return words
                else:
                    print(f"Hybrid OCR gave only {len(words)} words, trying legacy engines...")
                    words = []  # Reset and try legacy
                    
            except Exception as e:
                print(f"Hybrid OCR failed: {e}, falling back to legacy engines...")
                words = []  # Reset and try legacy
        
        # Fallback 1: EasyOCR
        if self.easyocr_reader is not None:
            try:
                results = self.easyocr_reader.readtext(img)
                for (bbox, text, conf) in results:
                    x_coords = [p[0] for p in bbox]
                    y_coords = [p[1] for p in bbox]
                    x1, y1, x2, y2 = min(x_coords), min(y_coords), max(x_coords), max(y_coords)
                    
                    words.append(OcrWord(
                        text=text.strip(),
                        confidence=float(conf),
                        bbox=[int(x1), int(y1), int(x2), int(y2)]
                    ))
                print(f"EasyOCR extracted {len(words)} words")
            except Exception as e:
                print(f"EasyOCR failed: {e}")
                
        # Fallback 2: Tesseract
        if len(words) == 0 and TESSERACT_AVAILABLE:
            try:
                data = pytesseract.image_to_data(img, output_type=pytesseract.Output.DICT)
                
                for i in range(len(data['text'])):
                    text = data['text'][i].strip()
                    conf = int(data['conf'][i])
                    
                    if text and conf > 30:
                        x, y, w, h = data['left'][i], data['top'][i], data['width'][i], data['height'][i]
                        words.append(OcrWord(
                            text=text,
                            confidence=conf / 100.0,
                            bbox=[x, y, x + w, y + h]
                        ))
                print(f"Tesseract extracted {len(words)} words")
            except Exception as e:
                print(f"Tesseract failed: {e}")
                
        return words
        
    def _extract_fields(self, words: List[OcrWord], img_shape: Tuple) -> List[ExtractedField]:
        """
        Extract fields using anchor-based geometric proximity
        """
        fields = []
        img_height, img_width = img_shape[:2]
        
        # Create word lookup by position
        word_index = self._build_spatial_index(words)
        
        # Extract each field
        for field_name, config in self.ANCHORS.items():
            field = self._extract_single_field(
                field_name, config, words, word_index, img_height, img_width
            )
            if field:
                fields.append(field)
                
        return fields
        
    def _build_spatial_index(self, words: List[OcrWord]) -> Dict:
        """Build spatial index for fast proximity lookups"""
        # Simple grid-based spatial index
        return {
            'words': words,
            'by_text': {w.text.lower(): w for w in words}
        }
        
    def _extract_single_field(
        self, 
        field_name: str, 
        config: Dict, 
        words: List[OcrWord],
        word_index: Dict,
        img_height: int,
        img_width: int
    ) -> Optional[ExtractedField]:
        """Extract a single field using anchor keywords and proximity"""
        
        best_match = None
        best_score = 0
        
        # Find anchor words
        keywords = config.get('keywords', [])
        patterns = config.get('patterns', [])
        
        for word in words:
            word_lower = word.text.lower()
            
            # Check if word matches any keyword
            is_anchor = any(kw in word_lower for kw in keywords)
            
            if is_anchor:
                # Look for value near this anchor
                # Search within 100px radius
                nearby_value = self._find_nearby_value(
                    word, words, patterns, radius_x=100, radius_y=50
                )
                
                if nearby_value:
                    score = self._calculate_field_score(
                        word, nearby_value, patterns, field_name
                    )
                    
                    if score > best_score:
                        best_score = score
                        best_match = (word, nearby_value, score)
                        
        # Also try direct pattern matching on all words
        if not best_match:
            for word in words:
                for pattern in patterns:
                    match = re.search(pattern, word.text, re.IGNORECASE)
                    if match:
                        value = match.group(1) if match.groups() else word.text
                        score = self._calculate_field_score(
                            word, {'text': value, 'word': word}, 
                            patterns, field_name
                        )
                        if score > best_score:
                            best_score = score
                            best_match = (word, {'text': value, 'word': word}, score)
                            
        if best_match:
            anchor, value_info, score = best_match
            value = value_info['text']
            value_word = value_info.get('word', anchor)
            
            # Calculate weighted confidence
            ocr_conf = value_word.confidence
            pattern_score = 1.0 if self._matches_pattern(value, patterns) else 0.5
            weighted_conf = (ocr_conf * 0.6) + (pattern_score * 0.4)
            
            return ExtractedField(
                field=field_name,
                value=value,
                confidence=weighted_conf,
                bbox=value_word.bbox,
                ocr_confidence=ocr_conf,
                pattern_match_score=pattern_score,
                requires_manual_check=weighted_conf < 0.75 or field_name == "total"
            )
            
        return None
        
    def _find_nearby_value(
        self, 
        anchor: OcrWord, 
        words: List[OcrWord], 
        patterns: List[str],
        radius_x: int = 100,
        radius_y: int = 50
    ) -> Optional[Dict]:
        """Find a value word near the anchor word"""
        
        anchor_cx, anchor_cy = anchor.center
        
        for word in words:
            if word == anchor:
                continue
                
            # Calculate distance
            word_cx, word_cy = word.center
            dx = abs(word_cx - anchor_cx)
            dy = abs(word_cy - anchor_cy)
            
            # Check if within radius (prefer right and below)
            in_radius = (dx <= radius_x and dy <= radius_y)
            
            # Also check if it's to the right or below
            is_right_or_below = (word_cx > anchor_cx or word_cy > anchor_cy)
            
            if in_radius and is_right_or_below:
                # Check if word matches any pattern
                for pattern in patterns:
                    match = re.search(pattern, word.text, re.IGNORECASE)
                    if match:
                        return {
                            'text': match.group(1) if match.groups() else word.text,
                            'word': word
                        }
                        
        return None
        
    def _calculate_field_score(
        self, 
        anchor: OcrWord, 
        value: Dict, 
        patterns: List[str],
        field_name: str
    ) -> float:
        """Calculate extraction confidence score"""
        value_word = value.get('word', anchor)
        
        # OCR confidence (0-1)
        ocr_score = value_word.confidence
        
        # Pattern match score
        text = value['text']
        pattern_score = 1.0 if self._matches_pattern(text, patterns) else 0.3
        
        # Proximity score (closer is better)
        anchor_cx, anchor_cy = anchor.center
        value_cx, value_cy = value_word.center
        distance = np.sqrt((value_cx - anchor_cx)**2 + (value_cy - anchor_cy)**2)
        proximity_score = max(0, 1 - (distance / 200))  # Normalize to 200px
        
        # Weighted combination
        total_score = (ocr_score * 0.4) + (pattern_score * 0.4) + (proximity_score * 0.2)
        
        # Boost for critical fields
        if field_name == "total":
            total_score *= 1.1
            
        return min(1.0, total_score)
        
    def _matches_pattern(self, text: str, patterns: List[str]) -> bool:
        """Check if text matches any of the patterns"""
        for pattern in patterns:
            if re.search(pattern, text, re.IGNORECASE):
                return True
        return False


# Singleton instance
_extraction_processor = None

def get_extraction_processor() -> ExtractionProcessor:
    """Get or create singleton extraction processor"""
    global _extraction_processor
    if _extraction_processor is None:
        _extraction_processor = ExtractionProcessor()
    return _extraction_processor
