"""
Coordinate Registry - Anchor-based Field Extraction
Stores field positions as (Δx, Δy) offsets from anchor text
"""

from typing import Dict, List, Optional, Tuple, Any, Union
from dataclasses import dataclass
from pathlib import Path
import re
import logging

logger = logging.getLogger(__name__)


@dataclass
class FieldCoordinate:
    """Field position relative to anchor"""
    field_name: str
    anchor_text: str  # e.g., "Invoice Number", "Total:"
    delta_x: float    # pixels from anchor x
    delta_y: float    # pixels from anchor y
    width: float      # expected field width
    height: float     # expected field height
    regex_pattern: Optional[str] = None  # e.g., r"INV-\d+"


@dataclass
class ValidationRule:
    """Business rule for field validation"""
    rule_type: str  # 'checksum', 'range', 'required', 'regex'
    fields: List[str]
    expression: str  # e.g., "subtotal + tax == total"
    tolerance: float = 0.01  # for floating point comparison
    message: str = ""


class CoordinateRegistry:
    """
    Registry for vendor-specific coordinate templates
    Uses anchor text + relative positioning for field extraction
    """
    
    # Common anchor texts for invoices
    COMMON_ANCHORS = {
        'invoice_number': ['Invoice #', 'Invoice No', 'Invoice Number', 'Inv #'],
        'invoice_date': ['Date', 'Invoice Date', 'Date of Issue'],
        'due_date': ['Due Date', 'Payment Due', 'Due'],
        'vendor_name': ['From', 'Vendor', 'Seller', 'Billed By'],
        'buyer_name': ['To', 'Buyer', 'Customer', 'Billed To'],
        'subtotal': ['Subtotal', 'Sub Total', 'Sub-Total'],
        'tax': ['Tax', 'GST', 'VAT', 'Tax Amount'],
        'total': ['Total', 'Grand Total', 'Total Amount', 'Amount Due'],
        'line_items': ['Item', 'Description', 'Product']
    }
    
    def __init__(self, db_session=None):
        self.db = db_session
        self._templates: Dict[str, Dict[str, FieldCoordinate]] = {}
        self._validation_rules: List[ValidationRule] = []
        self._load_default_rules()
    
    def _load_default_rules(self):
        """Load hardcoded validation rules"""
        self._validation_rules = [
            ValidationRule(
                rule_type='checksum',
                fields=['subtotal', 'tax', 'total'],
                expression='subtotal + tax',
                message='Mathematical Inconsistency: subtotal + tax != total'
            ),
            ValidationRule(
                rule_type='checksum',
                fields=['line_items', 'total'],
                expression='sum(line_items)',
                message='Mathematical Inconsistency: sum of line items != total'
            ),
            ValidationRule(
                rule_type='required',
                fields=['invoice_number', 'invoice_date', 'total', 'vendor_name'],
                expression='all_present',
                message='Missing required fields'
            ),
            ValidationRule(
                rule_type='range',
                fields=['total'],
                expression='> 0',
                message='Total amount must be positive'
            )
        ]
    
    def create_template(self, style_tag: str, vendor_name: str) -> Dict[str, FieldCoordinate]:
        """Create new coordinate template for vendor"""
        template = {}
        self._templates[style_tag] = template
        return template
    
    def add_field_coordinate(self, 
                            style_tag: str,
                            field_name: str,
                            anchor_text: str,
                            delta_x: float,
                            delta_y: float,
                            width: float,
                            height: float,
                            regex_pattern: Optional[str] = None):
        """Add field coordinate to template"""
        if style_tag not in self._templates:
            self._templates[style_tag] = {}
        
        self._templates[style_tag][field_name] = FieldCoordinate(
            field_name=field_name,
            anchor_text=anchor_text,
            delta_x=delta_x,
            delta_y=delta_y,
            width=width,
            height=height,
            regex_pattern=regex_pattern
        )
        
        logger.info(f"Added {field_name} to template {style_tag}")
    
    def get_field_coordinate(self, style_tag: str, field_name: str) -> Optional[FieldCoordinate]:
        """Get coordinate for specific field"""
        template = self._templates.get(style_tag, {})
        return template.get(field_name)
    
    def find_anchor_in_ocr(self, ocr_boxes: List[Dict], anchor_texts: List[str]) -> Optional[Dict]:
        """
        Find anchor text in OCR output with fuzzy matching
        Returns: box dict with x, y, text
        """
        for box in ocr_boxes:
            ocr_text = box.get('text', '').lower().strip()
            
            for anchor in anchor_texts:
                anchor_lower = anchor.lower().strip()
                # Exact match or contains
                if anchor_lower in ocr_text or ocr_text in anchor_lower:
                    return box
                
                # Fuzzy match using Levenshtein
                if self._fuzzy_match(ocr_text, anchor_lower, threshold=0.8):
                    return box
        
        return None
    
    def _fuzzy_match(self, text1: str, text2: str, threshold: float = 0.8) -> bool:
        """Simple fuzzy string matching"""
        try:
            from Levenshtein import ratio
            return ratio(text1, text2) >= threshold
        except ImportError:
            # Fallback: simple substring match
            return text1 in text2 or text2 in text1
    
    def extract_field_at_coordinate(self,
                                    ocr_boxes: List[Dict],
                                    anchor_box: Dict,
                                    field_coord: FieldCoordinate) -> Optional[Dict]:
        """
        Extract field value at relative position from anchor
        
        Args:
            ocr_boxes: All OCR detected text boxes
            anchor_box: The anchor text box
            field_coord: Field coordinate definition
        
        Returns:
            Dict with text, confidence, and bbox
        """
        # Calculate expected field position
        expected_x = anchor_box['x'] + field_coord.delta_x
        expected_y = anchor_box['y'] + field_coord.delta_y
        
        # Find closest text box to expected position
        best_match = None
        best_distance = float('inf')
        
        for box in ocr_boxes:
            box_x = box.get('x', 0)
            box_y = box.get('y', 0)
            
            # Calculate Euclidean distance
            distance = ((box_x - expected_x) ** 2 + (box_y - expected_y) ** 2) ** 0.5
            
            # Check if within expected bounds
            if (abs(box_x - expected_x) <= field_coord.width and
                abs(box_y - expected_y) <= field_coord.height):
                
                if distance < best_distance:
                    best_distance = distance
                    best_match = box
        
        return best_match
    
    def extract_all_fields(self, 
                          style_tag: str,
                          ocr_boxes: List[Dict]) -> Dict[str, Any]:
        """
        Extract all fields for given template
        
        Returns:
            Dict with extracted fields and their confidence scores
        """
        template = self._templates.get(style_tag, {})
        if not template:
            logger.warning(f"No template found for style_tag: {style_tag}")
            return {}
        
        extracted = {}
        
        for field_name, field_coord in template.items():
            # Find anchor
            anchor_texts = self.COMMON_ANCHORS.get(field_name, [field_coord.anchor_text])
            anchor_box = self.find_anchor_in_ocr(ocr_boxes, anchor_texts)
            
            if not anchor_box:
                logger.warning(f"Anchor not found for field: {field_name}")
                extracted[field_name] = {
                    'value': None,
                    'confidence': 0.0,
                    'method': 'anchor_not_found'
                }
                continue
            
            # Extract field at relative position
            field_box = self.extract_field_at_coordinate(
                ocr_boxes, anchor_box, field_coord
            )
            
            if field_box:
                # Apply regex validation if specified
                text = field_box.get('text', '')
                if field_coord.regex_pattern:
                    match = re.search(field_coord.regex_pattern, text)
                    if match:
                        text = match.group(0)
                
                extracted[field_name] = {
                    'value': text,
                    'confidence': field_box.get('confidence', 0.9),
                    'bbox': {
                        'x': field_box['x'],
                        'y': field_box['y'],
                        'width': field_box.get('width', 0),
                        'height': field_box.get('height', 0)
                    },
                    'method': 'coordinate_relative'
                }
            else:
                extracted[field_name] = {
                    'value': None,
                    'confidence': 0.0,
                    'method': 'field_not_found'
                }
        
        return extracted
    
    def validate_checksum(self, extracted_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Run validation rules on extracted data
        
        Returns:
            List of validation warnings
        """
        warnings = []
        
        # Convert to flat dict for easier access
        flat_data = {}
        for key, value in extracted_data.items():
            if isinstance(value, dict):
                flat_data[key] = value.get('value')
            else:
                flat_data[key] = value
        
        # Check subtotal + tax == total
        subtotal = self._parse_amount(flat_data.get('subtotal', 0))
        tax = self._parse_amount(flat_data.get('tax', 0))
        total = self._parse_amount(flat_data.get('total', 0))
        
        if subtotal and tax and total:
            calculated = subtotal + tax
            if abs(calculated - total) > 0.01:
                warnings.append({
                    'type': 'mathematical_inconsistency',
                    'severity': 'high',
                    'message': f'subtotal (${subtotal:.2f}) + tax (${tax:.2f}) = ${calculated:.2f} ≠ total (${total:.2f})',
                    'field': 'total',
                    'expected': calculated,
                    'found': total
                })
        
        # Check sum of line items == total
        line_items = flat_data.get('line_items', [])
        if line_items and isinstance(line_items, list) and total:
            line_sum = sum(self._parse_amount(item.get('amount', 0)) for item in line_items)
            if abs(line_sum - total) > 0.01:
                warnings.append({
                    'type': 'mathematical_inconsistency',
                    'severity': 'high',
                    'message': f'Sum of line items (${line_sum:.2f}) ≠ total (${total:.2f})',
                    'field': 'total',
                    'expected': line_sum,
                    'found': total
                })
        
        # Check for negative amounts
        if total and total < 0:
            warnings.append({
                'type': 'invalid_value',
                'severity': 'critical',
                'message': 'Total amount is negative',
                'field': 'total',
                'expected': '> 0',
                'found': total
            })
        
        # Check required fields
        required = ['invoice_number', 'invoice_date', 'total', 'vendor_name']
        for field in required:
            if not flat_data.get(field):
                warnings.append({
                    'type': 'missing_required_field',
                    'severity': 'medium',
                    'message': f'Missing required field: {field}',
                    'field': field
                })
        
        return warnings
    
    def _parse_amount(self, value: Any) -> float:
        """Parse amount from various formats"""
        if value is None:
            return 0.0
        
        if isinstance(value, (int, float)):
            return float(value)
        
        # Clean string: remove $, commas, spaces
        if isinstance(value, str):
            cleaned = value.replace('$', '').replace(',', '').replace(' ', '').strip()
            try:
                return float(cleaned)
            except ValueError:
                return 0.0
        
        return 0.0
    
    def update_from_correction(self,
                               style_tag: str,
                               field_name: str,
                               anchor_text: str,
                               correction_data: Dict[str, Any],
                               ocr_boxes: List[Dict]):
        """
        Update coordinate registry based on user correction
        
        Args:
            correction_data: Dict with 'correct_value', 'correct_bbox'
        """
        anchor_box = self.find_anchor_in_ocr(ocr_boxes, [anchor_text])
        if not anchor_box:
            logger.error(f"Cannot update: anchor '{anchor_text}' not found")
            return
        
        correct_bbox = correction_data.get('correct_bbox', {})
        
        # Calculate new delta from anchor
        new_delta_x = correct_bbox.get('x', 0) - anchor_box['x']
        new_delta_y = correct_bbox.get('y', 0) - anchor_box['y']
        new_width = correct_bbox.get('width', 100)
        new_height = correct_bbox.get('height', 30)
        
        # Update or create field coordinate
        self.add_field_coordinate(
            style_tag=style_tag,
            field_name=field_name,
            anchor_text=anchor_text,
            delta_x=new_delta_x,
            delta_y=new_delta_y,
            width=new_width,
            height=new_height
        )
        
        logger.info(f"Updated {field_name} coordinates for {style_tag}")


# Global registry instance
_registry_instance = None

def get_coordinate_registry(db_session=None):
    """Get or create singleton registry instance"""
    global _registry_instance
    if _registry_instance is None:
        _registry_instance = CoordinateRegistry(db_session)
    return _registry_instance
