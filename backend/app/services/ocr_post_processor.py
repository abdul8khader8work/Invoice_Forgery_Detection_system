"""
Post-Extraction Logic for OCR Imperfections
Handles the 5% that fails with regex correction and fuzzy matching
"""

import re
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass
import logging
from thefuzz import fuzz, process

logger = logging.getLogger(__name__)


@dataclass
class VendorDatabase:
    """Simple vendor database for fuzzy matching"""
    vendors: List[str]
    
    def __post_init__(self):
        # Normalize vendor names for better matching
        self.normalized_vendors = [self._normalize_name(v) for v in self.vendors]
    
    def _normalize_name(self, name: str) -> str:
        """Normalize vendor name for matching"""
        return re.sub(r'[^a-zA-Z0-9]', '', name.lower())
    
    def find_match(self, extracted_name: str, threshold: int = 80) -> Optional[Tuple[str, int]]:
        """
        Find best match for extracted vendor name using fuzzy matching.
        
        Args:
            extracted_name: OCR-extracted vendor name
            threshold: Minimum similarity score (0-100)
            
        Returns:
            Tuple of (matched_vendor, score) or None if no good match
        """
        if not extracted_name:
            return None
        
        # Normalize extracted name
        normalized_extracted = self._normalize_name(extracted_name)
        
        # Use fuzzy matching
        best_match = process.extractOne(
            normalized_extracted,
            self.normalized_vendors,
            scorer=fuzz.ratio
        )
        
        if best_match and best_match[1] >= threshold:
            # Get original vendor name (not normalized)
            index = self.normalized_vendors.index(best_match[0])
            return self.vendors[index], best_match[1]
        
        return None


class OCRPostProcessor:
    """
    Post-extraction logic to handle OCR imperfections.
    The difference between a BTech project and a real app.
    """
    
    def __init__(self, vendor_db: Optional[VendorDatabase] = None):
        """
        Initialize post-processor.
        
        Args:
            vendor_db: Database of known vendors for fuzzy matching
        """
        self.vendor_db = vendor_db or VendorDatabase([
            "Microsoft Corporation",
            "Amazon Web Services",
            "Google LLC",
            "Apple Inc.",
            "Adobe Systems",
            "Oracle Corporation",
            "IBM Corporation",
            "Cisco Systems",
            "Intel Corporation",
            "Dell Technologies",
            "HP Inc.",
            "Lenovo Group",
            "Samsung Electronics",
            "Sony Corporation"
        ])
        
        # Common OCR corrections
        self.corrections = {
            # Number/character confusions
            't0tal': 'total',
            'tot4l': 'total',
            'tota1': 'total',
            'inv0ice': 'invoice',
            'invo1ce': 'invoice',
            'amt': 'amount',
            'am0unt': 'amount',
            
            # Common OCR errors
            'rn': 'm',  # OCR often reads 'm' as 'rn'
            'cl': 'd',  # OCR sometimes reads 'd' as 'cl'
            'vv': 'w',  # Double v seen as w
            
            # Financial terms
            'sub tota1': 'subtotal',
            'sub t0tal': 'subtotal',
            'tax amt': 'tax amount',
            'tax am0unt': 'tax amount',
            'grand t0tal': 'grand total',
            'grand tot4l': 'grand total',
            
            # Currency symbols
            's': '$',  # Sometimes OCR reads $ as s
            'usd': '$',
            'eur': '€',
            'gbp': '£',
        }
        
        # Field-specific patterns
        self.field_patterns = {
            'invoice_number': [
                r'inv[o0]ice\s*#?\s*([a-zA-Z0-9-]+)',
                r'inv\s*#?\s*([a-zA-Z0-9-]+)',
                r'bill\s*#?\s*([a-zA-Z0-9-]+)',
                r'receipt\s*#?\s*([a-zA-Z0-9-]+)',
            ],
            'total_amount': [
                r't[o0]ta[l1]\s*[:\$]?\s*([\d,]+\.\d{2})',
                r'grand\s*t[o0]ta[l1]\s*[:\$]?\s*([\d,]+\.\d{2})',
                r'amount\s*due\s*[:\$]?\s*([\d,]+\.\d{2})',
                r'balance\s*due\s*[:\$]?\s*([\d,]+\.\d{2})',
                r'\$\s*([\d,]+\.\d{2})\s*t[o0]ta[l1]',
            ],
            'tax_amount': [
                r'tax\s*[:\$]?\s*([\d,]+\.\d{2})',
                r'vat\s*[:\$]?\s*([\d,]+\.\d{2})',
                r'gst\s*[:\$]?\s*([\d,]+\.\d{2})',
                r'sales\s*tax\s*[:\$]?\s*([\d,]+\.\d{2})',
            ],
            'invoice_date': [
                r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b',
                r'\b(\d{4}[/-]\d{1,2}[/-]\d{1,2})\b',
                r'\b(\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{4})\b',
            ],
            'vendor_name': [
                r'^(.+?)\s+inv[o0]ice',  # Vendor name before "invoice"
                r'from\s+(.+?)\s+bill',   # Vendor name after "from"
                r'billed\s+by\s+(.+)',    # Vendor name after "billed by"
            ]
        }
        
        logger.info("OCRPostProcessor initialized")
    
    def correct_text(self, text: str) -> str:
        """
        Apply common OCR corrections to text.
        Handles character confusions and common errors.
        """
        if not text:
            return text
        
        corrected = text.lower()
        
        # Apply corrections
        for wrong, right in self.corrections.items():
            corrected = corrected.replace(wrong, right)
        
        # Fix number/character confusions more globally
        corrected = re.sub(r'(\d)0(\d)', r'\1\2', corrected)  # Remove spurious zeros
        corrected = re.sub(r'(\d)[oO](\d)', r'\g<1>0\g<2>', corrected)  # o -> 0 in numbers
        corrected = re.sub(r'(\d)[lLiI](\d)', r'\g<1>1\g<2>', corrected)  # l/I -> 1 in numbers
        
        return corrected.strip()
    
    def extract_field(self, field_name: str, texts: List[str]) -> Optional[str]:
        """
        Extract a specific field using corrected text and patterns.
        """
        # Correct all texts first
        corrected_texts = [self.correct_text(text) for text in texts]
        
        # Try each pattern for the field
        for pattern in self.field_patterns.get(field_name, []):
            for text in corrected_texts:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    value = match.group(1)
                    
                    # Post-process the extracted value
                    if field_name in ['total_amount', 'tax_amount']:
                        # Clean up currency amounts
                        value = re.sub(r'[^\d.]', '', value)
                        # Ensure proper decimal format
                        if '.' not in value and len(value) > 2:
                            value = value[:-2] + '.' + value[-2:]
                    
                    return value
        
        return None
    
    def match_vendor(self, extracted_name: str) -> Dict[str, Any]:
        """
        Match extracted vendor name against database using fuzzy matching.
        """
        if not extracted_name:
            return {'matched_vendor': None, 'confidence': 0, 'original': extracted_name}
        
        # Correct the extracted name first
        corrected_name = self.correct_text(extracted_name)
        
        # Try fuzzy matching
        match = self.vendor_db.find_match(corrected_name, threshold=75)
        
        if match:
            return {
                'matched_vendor': match[0],
                'confidence': match[1],
                'original': extracted_name,
                'corrected': corrected_name
            }
        
        return {
            'matched_vendor': corrected_name,  # Use corrected if no match found
            'confidence': 0,
            'original': extracted_name,
            'corrected': corrected_name
        }
    
    def process_invoice_data(self, ocr_texts: List[str]) -> Dict[str, Any]:
        """
        Process OCR texts to extract clean invoice data.
        This is where the 5% error handling happens.
        """
        if not ocr_texts:
            return {}
        
        # Extract fields with corrections
        data = {}
        
        # Invoice number
        invoice_num = self.extract_field('invoice_number', ocr_texts)
        if invoice_num:
            data['invoice_number'] = invoice_num
        
        # Total amount
        total = self.extract_field('total_amount', ocr_texts)
        if total:
            data['total_amount'] = total
        
        # Tax amount
        tax = self.extract_field('tax_amount', ocr_texts)
        if tax:
            data['tax_amount'] = tax
        
        # Invoice date
        date = self.extract_field('invoice_date', ocr_texts)
        if date:
            data['invoice_date'] = date
        
        # Vendor name with fuzzy matching
        vendor_match = self.match_vendor(' '.join(ocr_texts[:3]))  # Check first few lines
        if vendor_match['matched_vendor']:
            data['vendor_name'] = vendor_match['matched_vendor']
            data['vendor_match_confidence'] = vendor_match['confidence']
            if vendor_match['confidence'] < 90:
                data['vendor_note'] = "Low confidence match - please verify"
        
        # Add processing metadata
        data['post_processing_applied'] = True
        data['corrections_made'] = len([t for t in ocr_texts if self.correct_text(t) != t.lower()])
        
        return data


# Convenience function
def post_process_ocr_results(ocr_texts: List[str], 
                             vendor_list: Optional[List[str]] = None) -> Dict[str, Any]:
    """
    Quick post-processing of OCR results.
    """
    vendor_db = VendorDatabase(vendor_list) if vendor_list else None
    processor = OCRPostProcessor(vendor_db)
    return processor.process_invoice_data(ocr_texts)
