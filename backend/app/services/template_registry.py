"""
Active Learning Template Registry
Manages vendor fingerprints and learned spatial field mappings
"""

import hashlib
import json
import re
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, asdict
from difflib import SequenceMatcher
import numpy as np
from sqlalchemy.orm import Session
from sqlalchemy import desc

from app.models.database import SessionLocal
from app.models.active_learning_models import TemplateRegistry, VendorIdentifier


@dataclass
class FieldMap:
    """Spatial field mapping with anchor relationships"""
    anchor_label: str
    anchor_patterns: List[str]
    direction: str  # 'right', 'left', 'above', 'below'
    y_tolerance: int = 5
    x_max_distance: int = 200
    expected_type: str = "text"  # 'currency', 'date', 'number', 'text'
    regex_pattern: Optional[str] = None
    confidence_boost: float = 0.0
    
    def to_dict(self) -> Dict:
        return asdict(self)


@dataclass
class VendorFingerprint:
    """Extracted vendor identifiers for template matching"""
    gstin: Optional[str] = None
    vat: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    tax_id: Optional[str] = None
    support_email: Optional[str] = None
    
    def compute_hash(self) -> str:
        """Generate SHA256 fingerprint from identifiers"""
        # Sort for consistent hashing
        identifiers = {
            'gstin': self.gstin or '',
            'vat': self.vat or '',
            'email': self.email or '',
            'tax_id': self.tax_id or ''
        }
        
        # Only hash non-empty identifiers
        hash_input = ''.join(sorted(v for v in identifiers.values() if v))
        
        if not hash_input:
            # Fallback to support email or phone if no tax IDs
            hash_input = (self.support_email or '') + (self.phone or '')
        
        return hashlib.sha256(hash_input.encode()).hexdigest()[:64]


class FuzzyMatcher:
    """Fuzzy string matching for OCR typo tolerance"""
    
    @staticmethod
    def levenshtein_distance(s1: str, s2: str) -> int:
        """Calculate edit distance between two strings"""
        if len(s1) < len(s2):
            return FuzzyMatcher.levenshtein_distance(s2, s1)
        
        if len(s2) == 0:
            return len(s1)
        
        previous_row = range(len(s2) + 1)
        for i, c1 in enumerate(s1):
            current_row = [i + 1]
            for j, c2 in enumerate(s2):
                insertions = previous_row[j + 1] + 1
                deletions = current_row[j] + 1
                substitutions = previous_row[j] + (c1 != c2)
                current_row.append(min(insertions, deletions, substitutions))
            previous_row = current_row
        
        return previous_row[-1]
    
    @staticmethod
    def similarity_ratio(s1: str, s2: str) -> float:
        """Return similarity ratio (0.0 to 1.0)"""
        return SequenceMatcher(None, s1.lower(), s2.lower()).ratio()
    
    @staticmethod
    def find_best_match(target: str, candidates: List[str], threshold: float = 0.8) -> Optional[Tuple[str, float]]:
        """Find best matching candidate above threshold"""
        best_match = None
        best_score = 0.0
        
        for candidate in candidates:
            score = FuzzyMatcher.similarity_ratio(target, candidate)
            if score > best_score and score >= threshold:
                best_score = score
                best_match = candidate
        
        return (best_match, best_score) if best_match else None
    
    @staticmethod
    def is_anchor_match(ocr_text: str, anchor_patterns: List[str], max_typos: int = 1) -> Tuple[bool, float]:
        """
        Check if OCR text matches any anchor pattern with typo tolerance
        Returns: (is_match, confidence_score)
        """
        ocr_clean = ocr_text.lower().strip()
        
        for pattern in anchor_patterns:
            pattern_clean = pattern.lower().strip()
            
            # Exact match
            if ocr_clean == pattern_clean:
                return True, 1.0
            
            # Fuzzy match using Levenshtein
            distance = FuzzyMatcher.levenshtein_distance(ocr_clean, pattern_clean)
            max_len = max(len(ocr_clean), len(pattern_clean))
            
            if max_len == 0:
                continue
                
            typo_ratio = distance / max_len
            
            # Allow up to max_typos character differences
            if distance <= max_typos:
                confidence = 1.0 - (distance * 0.2)  # Penalize typos
                return True, max(confidence, 0.6)
            
            # Also check similarity ratio as backup
            similarity = FuzzyMatcher.similarity_ratio(ocr_clean, pattern_clean)
            if similarity >= 0.85:
                return True, similarity
        
        return False, 0.0


class TemplateRegistryManager:
    """
    Manages the active learning template registry
    Learns from user corrections and improves extraction over time
    """
    
    # Default field maps for common invoice fields
    DEFAULT_FIELD_MAPS = {
        'total': FieldMap(
            anchor_label='Total',
            anchor_patterns=['Grand Total', 'Total Amount', 'Gross Total', 'Total', 'Amount Due', 'Balance Due'],
            direction='right',
            y_tolerance=5,
            x_max_distance=250,
            expected_type='currency',
            regex_pattern=r'^\$?[\d,]+\.\d{2}$',
            confidence_boost=0.15
        ),
        'subtotal': FieldMap(
            anchor_label='Subtotal',
            anchor_patterns=['Subtotal', 'Sub-Total', 'Net Amount', 'Amount'],
            direction='right',
            y_tolerance=5,
            x_max_distance=250,
            expected_type='currency',
            regex_pattern=r'^\$?[\d,]+\.\d{2}$'
        ),
        'tax': FieldMap(
            anchor_label='Tax',
            anchor_patterns=['Tax', 'VAT', 'GST', 'Sales Tax', 'Tax Amount'],
            direction='right',
            y_tolerance=5,
            x_max_distance=200,
            expected_type='currency',
            regex_pattern=r'^\$?[\d,]+\.\d{2}$'
        ),
        'date': FieldMap(
            anchor_label='Date',
            anchor_patterns=['Invoice Date', 'Date', 'Issued Date', 'Bill Date', 'Date of Issue'],
            direction='right',
            y_tolerance=3,
            x_max_distance=200,
            expected_type='date',
            regex_pattern=r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2}'
        ),
        'invoice_number': FieldMap(
            anchor_label='Invoice #',
            anchor_patterns=['Invoice Number', 'Invoice #', 'Invoice No', 'Bill Number', 'Reference'],
            direction='right',
            y_tolerance=3,
            x_max_distance=200,
            expected_type='text',
            regex_pattern=r'[A-Z0-9\-]+'
        ),
        'vendor_name': FieldMap(
            anchor_label='From',
            anchor_patterns=['From', 'Billed By', 'Seller', 'Vendor', 'Company', 'Bill From'],
            direction='below',
            y_tolerance=20,
            x_max_distance=300,
            expected_type='text'
        ),
        'due_date': FieldMap(
            anchor_label='Due Date',
            anchor_patterns=['Due Date', 'Payment Due', 'Due By'],
            direction='right',
            y_tolerance=3,
            x_max_distance=200,
            expected_type='date'
        )
    }
    
    def __init__(self, db: Optional[Session] = None):
        self.db = db or SessionLocal()
        self.fuzzy = FuzzyMatcher()
    
    def get_or_create_template(
        self, 
        fingerprint: VendorFingerprint,
        style_tag: Optional[str] = None
    ) -> Tuple[TemplateRegistry, bool]:
        """
        Get existing template or create new one
        Returns: (template, is_new)
        """
        fp_hash = fingerprint.compute_hash()
        
        template = self.db.query(TemplateRegistry).filter(
            TemplateRegistry.vendor_fingerprint == fp_hash,
            TemplateRegistry.is_active == True
        ).first()
        
        if template:
            # Update last used
            template.last_used_at = datetime.utcnow()
            self.db.commit()
            return template, False
        
        # Create new template with default field maps
        field_map_json = {
            k: v.to_dict() for k, v in self.DEFAULT_FIELD_MAPS.items()
        }
        
        template = TemplateRegistry(
            vendor_fingerprint=fp_hash,
            style_tag=style_tag or f"Vendor_{fp_hash[:8]}",
            identifiers=fingerprint.__dict__,
            field_map=field_map_json,
            confidence_score=0.5
        )
        
        self.db.add(template)
        self.db.commit()
        self.db.refresh(template)
        
        # Store individual identifiers for lookup
        self._store_identifiers(template.id, fingerprint)
        
        return template, True
    
    def _store_identifiers(self, template_id: int, fingerprint: VendorFingerprint):
        """Store individual identifiers for reverse lookup"""
        id_map = {
            'gstin': fingerprint.gstin,
            'vat': fingerprint.vat,
            'email': fingerprint.email,
            'phone': fingerprint.phone,
            'tax_id': fingerprint.tax_id,
            'support_email': fingerprint.support_email
        }
        
        for id_type, value in id_map.items():
            if value:
                vi = VendorIdentifier(
                    template_id=template_id,
                    identifier_type=id_type,
                    identifier_value=value
                )
                self.db.add(vi)
        
        self.db.commit()
    
    def find_template_by_identifier(
        self, 
        id_type: str, 
        id_value: str
    ) -> Optional[TemplateRegistry]:
        """Find template by a specific identifier (e.g., GSTIN)"""
        vi = self.db.query(VendorIdentifier).filter(
            VendorIdentifier.identifier_type == id_type,
            VendorIdentifier.identifier_value == id_value
        ).first()
        
        if vi:
            return self.db.query(TemplateRegistry).get(vi.template_id)
        return None
    
    def update_field_map(
        self,
        template_id: int,
        field_name: str,
        corrected_bbox: Dict[str, Any],
        anchor_bbox: Dict[str, Any],
        confidence_delta: float = 0.05
    ) -> bool:
        """
        Update template field map based on user correction
        This is the core learning mechanism
        """
        template = self.db.query(TemplateRegistry).get(template_id)
        if not template:
            return False
        
        field_map = template.field_map or {}
        
        # Calculate new spatial relationship
        delta_x = corrected_bbox['x'] - anchor_bbox['x']
        delta_y = corrected_bbox['y'] - anchor_bbox['y']
        
        # Update field map with learned offset
        if field_name in field_map:
            field_map[field_name]['learned_offset_x'] = delta_x
            field_map[field_name]['learned_offset_y'] = delta_y
            field_map[field_name]['extraction_count'] = field_map[field_name].get('extraction_count', 0) + 1
        else:
            # New field learned
            field_map[field_name] = {
                'anchor_label': 'Unknown',
                'anchor_patterns': [],
                'direction': 'right' if abs(delta_x) > abs(delta_y) else 'below',
                'learned_offset_x': delta_x,
                'learned_offset_y': delta_y,
                'y_tolerance': 10,
                'extraction_count': 1
            }
        
        # Boost template confidence
        template.field_map = field_map
        template.confidence_score = min(1.0, template.confidence_score + confidence_delta)
        template.correction_count += 1
        template.last_corrected_at = datetime.utcnow()
        
        self.db.commit()
        return True
    
    def get_template_confidence(self, template_id: int) -> float:
        """Get confidence score for a template"""
        template = self.db.query(TemplateRegistry).get(template_id)
        return template.confidence_score if template else 0.0
    
    def list_templates(
        self,
        min_confidence: float = 0.0,
        limit: int = 100
    ) -> List[TemplateRegistry]:
        """List templates by confidence"""
        return self.db.query(TemplateRegistry).filter(
            TemplateRegistry.confidence_score >= min_confidence,
            TemplateRegistry.is_active == True
        ).order_by(desc(TemplateRegistry.confidence_score)).limit(limit).all()
    
    def extract_vendor_fingerprint(
        self,
        ocr_boxes: List[Dict[str, Any]]
    ) -> VendorFingerprint:
        """
        Extract vendor identifiers from OCR text
        Uses regex patterns to find GSTIN, VAT, Email, etc.
        """
        fp = VendorFingerprint()
        
        # Patterns for common identifiers
        patterns = {
            'gstin': r'\b[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[0-9A-Z]{3}\b',
            'vat': r'\b[A-Z]{2}[0-9]{11,12}\b',
            'email': r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
            'phone': r'\b[\+]?[0-9]{1,4}[-.\s]?[0-9]{1,4}[-.\s]?[0-9]{1,4}[-.\s]?[0-9]{1,9}\b'
        }
        
        for box in ocr_boxes:
            text = box.get('text', '')
            
            for id_type, pattern in patterns.items():
                matches = re.findall(pattern, text)
                if matches:
                    if id_type == 'gstin' and not fp.gstin:
                        fp.gstin = matches[0]
                    elif id_type == 'vat' and not fp.vat:
                        fp.vat = matches[0]
                    elif id_type == 'email' and not fp.email:
                        fp.email = matches[0]
                    elif id_type == 'phone' and not fp.phone:
                        fp.phone = matches[0]
        
        return fp


# Import datetime at the end to avoid circular import issues
from datetime import datetime
