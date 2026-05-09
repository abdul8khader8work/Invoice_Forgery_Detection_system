"""
Spatial Intelligence Layer
Implements proximity-based field extraction with relative positioning
"""

import re
import math
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass
from difflib import SequenceMatcher
import numpy as np


@dataclass
class BoundingBox:
    """Represents a bounding box with spatial coordinates"""
    x: float  # Top-left x
    y: float  # Top-left y
    width: float
    height: float
    text: str = ""
    confidence: float = 1.0
    
    @property
    def center_x(self) -> float:
        return self.x + self.width / 2
    
    @property
    def center_y(self) -> float:
        return self.y + self.height / 2
    
    @property
    def right(self) -> float:
        return self.x + self.width
    
    @property
    def bottom(self) -> float:
        return self.y + self.height
    
    def distance_to(self, other: 'BoundingBox') -> float:
        """Euclidean distance between box centers"""
        return math.sqrt(
            (self.center_x - other.center_x) ** 2 + 
            (self.center_y - other.center_y) ** 2
        )
    
    def is_horizontally_aligned(self, other: 'BoundingBox', tolerance: int = 5) -> bool:
        """Check if boxes are horizontally aligned (same Y range)"""
        return abs(self.center_y - other.center_y) <= tolerance
    
    def is_vertically_aligned(self, other: 'BoundingBox', tolerance: int = 5) -> bool:
        """Check if boxes are vertically aligned (same X range)"""
        return abs(self.center_x - other.center_x) <= tolerance
    
    def to_dict(self) -> Dict:
        return {
            'x': self.x,
            'y': self.y,
            'width': self.width,
            'height': self.height,
            'text': self.text,
            'confidence': self.confidence
        }


class SpatialProximitySearch:
    """
    Finds values relative to anchor labels using spatial relationships
    Instead of fixed coordinates, uses directional proximity
    """
    
    def __init__(self, ocr_boxes: List[Dict[str, Any]]):
        """
        Initialize with PaddleOCR output
        ocr_boxes: List of {x, y, width, height, text, confidence}
        """
        self.boxes = []
        for box in ocr_boxes:
            bbox = BoundingBox(
                x=float(box.get('x', 0)),
                y=float(box.get('y', 0)),
                width=float(box.get('width', box.get('w', 0))),
                height=float(box.get('height', box.get('h', 0))),
                text=str(box.get('text', '')).strip(),
                confidence=float(box.get('confidence', 1.0))
            )
            self.boxes.append(bbox)
        
        # Index for faster lookup
        self._build_spatial_index()
    
    def _build_spatial_index(self):
        """Build spatial index for faster neighbor queries"""
        # Sort by Y position (row-major order)
        self.boxes_by_y = sorted(self.boxes, key=lambda b: b.center_y)
        # Sort by X position
        self.boxes_by_x = sorted(self.boxes, key=lambda b: b.center_x)
    
    def find_neighbor(
        self,
        anchor_bbox: BoundingBox,
        direction: str,
        y_tolerance: int = 5,
        x_max_distance: Optional[int] = None,
        constraint_regex: Optional[str] = None,
        exclude_patterns: Optional[List[str]] = None
    ) -> Optional[BoundingBox]:
        """
        Find neighboring box in specified direction
        
        Args:
            anchor_bbox: The anchor label box
            direction: 'right', 'left', 'above', 'below'
            y_tolerance: Max Y difference for horizontal alignment
            x_max_distance: Max X distance to search
            constraint_regex: Pattern the value must match
            exclude_patterns: Text patterns to exclude
        
        Returns:
            Best matching neighbor box or None
        """
        candidates = []
        
        for box in self.boxes:
            if box == anchor_bbox:
                continue
            
            # Check if box is in the right direction
            is_match = False
            
            if direction == 'right':
                # Box is to the right and horizontally aligned
                is_match = (box.x > anchor_bbox.right and 
                           abs(box.center_y - anchor_bbox.center_y) <= y_tolerance)
            
            elif direction == 'left':
                # Box is to the left and horizontally aligned
                is_match = (box.right < anchor_bbox.x and 
                           abs(box.center_y - anchor_bbox.center_y) <= y_tolerance)
            
            elif direction == 'below':
                # Box is below and vertically aligned
                is_match = (box.y > anchor_bbox.bottom and 
                           abs(box.center_x - anchor_bbox.center_x) <= y_tolerance * 2)
            
            elif direction == 'above':
                # Box is above and vertically aligned
                is_match = (box.bottom < anchor_bbox.y and 
                           abs(box.center_x - anchor_bbox.center_x) <= y_tolerance * 2)
            
            if is_match:
                # Check distance constraint
                if x_max_distance:
                    dist = anchor_bbox.distance_to(box)
                    if dist > x_max_distance:
                        continue
                
                # Check exclude patterns
                if exclude_patterns:
                    if any(pattern.lower() in box.text.lower() for pattern in exclude_patterns):
                        continue
                
                # Check regex constraint
                if constraint_regex:
                    if not re.search(constraint_regex, box.text):
                        continue
                
                candidates.append(box)
        
        if not candidates:
            return None
        
        # Sort by distance and return closest
        candidates.sort(key=lambda b: anchor_bbox.distance_to(b))
        return candidates[0]
    
    def find_by_learned_offset(
        self,
        anchor_bbox: BoundingBox,
        offset_x: float,
        offset_y: float,
        tolerance: int = 20
    ) -> Optional[BoundingBox]:
        """
        Find box at learned offset from anchor
        This is the core "learning" - we remember where values are relative to labels
        """
        expected_x = anchor_bbox.center_x + offset_x
        expected_y = anchor_bbox.center_y + offset_y
        
        best_match = None
        best_distance = float('inf')
        
        for box in self.boxes:
            if box == anchor_bbox:
                continue
            
            # Calculate distance to expected position
            dist = math.sqrt(
                (box.center_x - expected_x) ** 2 + 
                (box.center_y - expected_y) ** 2
            )
            
            if dist <= tolerance and dist < best_distance:
                best_distance = dist
                best_match = box
        
        return best_match
    
    def find_all_in_row(self, y_position: float, tolerance: int = 10) -> List[BoundingBox]:
        """Find all boxes in a horizontal row"""
        return [b for b in self.boxes if abs(b.center_y - y_position) <= tolerance]
    
    def find_all_in_column(self, x_position: float, tolerance: int = 10) -> List[BoundingBox]:
        """Find all boxes in a vertical column"""
        return [b for b in self.boxes if abs(b.center_x - x_position) <= tolerance]


class MultiEngineVoting:
    """
    Combines results from template-based and heuristic extraction
    Returns the most confident result
    """
    
    # Heuristic patterns for common fields
    HEURISTIC_PATTERNS = {
        'total': [
            r'(?:Total|Grand Total|Amount Due|Balance|Gross Total)[:\s]*\$?([\d,]+\.\d{2})',
            r'\$([\d,]+\.\d{2})\s*(?:USD|EUR|GBP)?\s*$'
        ],
        'date': [
            r'(?:Date|Invoice Date)[:\s]*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
            r'(\d{1,2}[/-]\d{1,2}[/-]\d{4})'
        ],
        'invoice_number': [
            r'(?:Invoice|Bill|Ref)(?:\s*#|:)\s*([A-Z0-9\-]+)',
            r'(?:INV|BILL)[-\s]*([0-9]+)'
        ],
        'tax': [
            r'(?:Tax|VAT|GST)[:\s]*\$?([\d,]+\.\d{2})',
            r'Tax\s*Amount[:\s]*\$?([\d,]+\.\d{2})'
        ]
    }
    
    def __init__(self, ocr_text: str, ocr_boxes: List[BoundingBox]):
        self.ocr_text = ocr_text
        self.ocr_boxes = ocr_boxes
    
    def run_heuristic_scan(self, field_name: str) -> Tuple[Optional[str], float]:
        """
        Run heuristic regex patterns to find field
        Returns: (value, confidence)
        """
        patterns = self.HEURISTIC_PATTERNS.get(field_name, [])
        
        for pattern in patterns:
            matches = re.finditer(pattern, self.ocr_text, re.IGNORECASE)
            for match in matches:
                if match.groups():
                    # Calculate confidence based on pattern specificity
                    confidence = self._calculate_heuristic_confidence(pattern, match.group(0))
                    return match.group(1), confidence
        
        return None, 0.0
    
    def _calculate_heuristic_confidence(self, pattern: str, match_text: str) -> float:
        """Calculate confidence score for heuristic match"""
        base_confidence = 0.6
        
        # Boost confidence for longer, more specific patterns
        if len(pattern) > 30:
            base_confidence += 0.1
        
        # Boost for patterns with named groups or specific keywords
        if 'Total' in pattern or 'Amount' in pattern or 'Date' in pattern:
            base_confidence += 0.1
        
        # Penalize if match is very short (might be noise)
        if len(match_text) < 3:
            base_confidence -= 0.2
        
        return min(0.95, max(0.4, base_confidence))
    
    def vote(
        self,
        field_name: str,
        template_result: Optional[Tuple[str, BoundingBox, float]],
        heuristic_result: Optional[Tuple[str, float]]
    ) -> Tuple[Optional[str], float, str]:
        """
        Vote between template and heuristic results
        Returns: (value, confidence, source)
        """
        template_value, template_conf = None, 0.0
        heuristic_value, heuristic_conf = None, 0.0
        
        if template_result:
            template_value, _, template_conf = template_result
        
        if heuristic_result:
            heuristic_value, heuristic_conf = heuristic_result
        
        # If only one has result, use it
        if template_value and not heuristic_value:
            return template_value, template_conf, 'template'
        
        if heuristic_value and not template_value:
            return heuristic_value, heuristic_conf, 'heuristic'
        
        # If both have results
        if template_value and heuristic_value:
            # Check if they agree
            values_similar = self._values_similar(template_value, heuristic_value)
            
            if values_similar:
                # Boost confidence when both agree
                avg_confidence = (template_conf + heuristic_conf) / 2
                boosted_confidence = min(0.98, avg_confidence + 0.15)
                return template_value, boosted_confidence, 'both_agree'
            else:
                # Pick the one with higher confidence
                if template_conf >= heuristic_conf:
                    return template_value, template_conf, 'template_wins'
                else:
                    return heuristic_value, heuristic_conf, 'heuristic_wins'
        
        return None, 0.0, 'none'
    
    def _values_similar(self, v1: str, v2: str) -> bool:
        """Check if two extracted values are similar"""
        # Clean values
        clean1 = re.sub(r'[^\w\d\.]', '', v1.lower())
        clean2 = re.sub(r'[^\w\d\.]', '', v2.lower())
        
        # Exact match after cleaning
        if clean1 == clean2:
            return True
        
        # Check similarity ratio
        similarity = SequenceMatcher(None, clean1, clean2).ratio()
        return similarity > 0.8


class SpatialIntelligenceEngine:
    """
    Main engine that orchestrates spatial extraction
    Combines template-based, learned offset, and heuristic approaches
    """
    
    def __init__(self, ocr_boxes: List[Dict[str, Any]]):
        self.proximity_search = SpatialProximitySearch(ocr_boxes)
        self.ocr_text = ' '.join([b.text for b in self.proximity_search.boxes])
        self.voting = MultiEngineVoting(self.ocr_text, self.proximity_search.boxes)
    
    def extract_field(
        self,
        field_name: str,
        field_map: Dict[str, Any],
        use_learned_offset: bool = True
    ) -> Tuple[Optional[str], float, Optional[BoundingBox], Dict[str, Any]]:
        """
        Extract a single field using all available methods
        
        Returns:
            (value, confidence, bbox, metadata)
        """
        metadata = {
            'methods_tried': [],
            'template_used': False,
            'heuristic_used': False,
            'learned_offset_used': False
        }
        
        anchor_patterns = field_map.get('anchor_patterns', [field_map.get('anchor_label', '')])
        direction = field_map.get('direction', 'right')
        y_tolerance = field_map.get('y_tolerance', 5)
        x_max_distance = field_map.get('x_max_distance', 200)
        regex_pattern = field_map.get('regex_pattern')
        
        # Step 1: Try learned offset if available
        if use_learned_offset:
            offset_x = field_map.get('learned_offset_x')
            offset_y = field_map.get('learned_offset_y')
            
            if offset_x is not None and offset_y is not None:
                # Find anchor first
                anchor_box = self._find_anchor_box(anchor_patterns, y_tolerance)
                if anchor_box:
                    learned_box = self.proximity_search.find_by_learned_offset(
                        anchor_box, offset_x, offset_y
                    )
                    if learned_box:
                        metadata['methods_tried'].append('learned_offset')
                        metadata['learned_offset_used'] = True
                        
                        confidence = self._validate_extraction(
                            learned_box.text, 
                            field_map.get('expected_type', 'text'),
                            regex_pattern
                        )
                        
                        return learned_box.text, confidence, learned_box, metadata
        
        # Step 2: Try template-based proximity search
        anchor_box = self._find_anchor_box(anchor_patterns, y_tolerance)
        template_result = None
        
        if anchor_box:
            neighbor = self.proximity_search.find_neighbor(
                anchor_box,
                direction,
                y_tolerance=y_tolerance,
                x_max_distance=x_max_distance,
                constraint_regex=regex_pattern
            )
            
            if neighbor:
                template_confidence = self._validate_extraction(
                    neighbor.text,
                    field_map.get('expected_type', 'text'),
                    regex_pattern
                )
                # Boost confidence from field map
                template_confidence += field_map.get('confidence_boost', 0.0)
                template_result = (neighbor.text, neighbor, min(0.98, template_confidence))
                metadata['methods_tried'].append('template_proximity')
                metadata['template_used'] = True
        
        # Step 3: Try heuristic scan
        heuristic_value, heuristic_conf = self.voting.run_heuristic_scan(field_name)
        heuristic_result = (heuristic_value, heuristic_conf) if heuristic_value else None
        
        if heuristic_result:
            metadata['methods_tried'].append('heuristic')
            metadata['heuristic_used'] = True
        
        # Step 4: Vote between results
        value, confidence, source = self.voting.vote(field_name, template_result, heuristic_result)
        
        # Get the bbox for the winning result
        bbox = None
        if source in ['template', 'both_agree', 'template_wins'] and template_result:
            bbox = template_result[1]
        elif source == 'heuristic_wins' and heuristic_result:
            # Find bbox containing heuristic value
            bbox = self._find_bbox_containing(heuristic_value)
        
        metadata['winning_source'] = source
        
        return value, confidence, bbox, metadata
    
    def _find_anchor_box(self, anchor_patterns: List[str], y_tolerance: int) -> Optional[BoundingBox]:
        """Find anchor label box using fuzzy matching"""
        from app.services.template_registry import FuzzyMatcher
        
        fuzzy = FuzzyMatcher()
        
        for box in self.proximity_search.boxes:
            is_match, confidence = fuzzy.is_anchor_match(
                box.text, 
                anchor_patterns, 
                max_typos=1
            )
            if is_match:
                return box
        
        return None
    
    def _find_bbox_containing(self, text: str) -> Optional[BoundingBox]:
        """Find bbox containing specific text"""
        for box in self.proximity_search.boxes:
            if text in box.text or box.text in text:
                return box
        return None
    
    def _validate_extraction(self, value: str, expected_type: str, regex: Optional[str]) -> float:
        """Validate extracted value and return confidence"""
        confidence = 0.7  # Base confidence
        
        # Check regex pattern
        if regex:
            if re.search(regex, value):
                confidence += 0.15
            else:
                confidence -= 0.2
        
        # Type-specific validation
        if expected_type == 'currency':
            # Check for currency format
            if re.match(r'^\$?[\d,]+\.\d{2}$', value):
                confidence += 0.1
            elif re.match(r'^\$?[\d,]+$', value):
                confidence += 0.05
        
        elif expected_type == 'date':
            # Check for date format
            date_patterns = [
                r'^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$',
                r'^\d{4}[/-]\d{1,2}[/-]\d{1,2}$'
            ]
            if any(re.match(p, value) for p in date_patterns):
                confidence += 0.1
        
        elif expected_type == 'number':
            # Check for numeric format
            if re.match(r'^\d+$', value):
                confidence += 0.1
            elif re.match(r'^\d+\.\d+$', value):
                confidence += 0.05
        
        return max(0.0, min(1.0, confidence))
    
    def extract_all_fields(
        self,
        field_map: Dict[str, Any]
    ) -> Tuple[Dict[str, Any], Dict[str, float], Dict[str, Any]]:
        """
        Extract all fields defined in the field map
        
        Returns:
            (extracted_data, confidence_scores, extraction_metadata)
        """
        extracted_data = {}
        confidence_scores = {}
        extraction_metadata = {}
        
        for field_name, field_config in field_map.items():
            value, confidence, bbox, metadata = self.extract_field(field_name, field_config)
            
            if value:
                extracted_data[field_name] = value
                confidence_scores[field_name] = confidence
                
                if bbox:
                    metadata['bbox'] = bbox.to_dict()
            else:
                confidence_scores[field_name] = 0.0
            
            extraction_metadata[field_name] = metadata
        
        return extracted_data, confidence_scores, extraction_metadata


# Helper function for quick extraction
def extract_with_spatial_intelligence(
    ocr_boxes: List[Dict[str, Any]],
    field_map: Dict[str, Any]
) -> Dict[str, Any]:
    """Convenience function for spatial extraction"""
    engine = SpatialIntelligenceEngine(ocr_boxes)
    extracted, confidences, metadata = engine.extract_all_fields(field_map)
    
    return {
        'extracted_data': extracted,
        'confidence_scores': confidences,
        'metadata': metadata,
        'overall_confidence': sum(confidences.values()) / len(confidences) if confidences else 0.0
    }
