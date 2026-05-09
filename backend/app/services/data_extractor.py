"""
Invoice OCR Pipeline - Data Extraction Module
Phase 3: Spatial Heuristics & Data Extraction (The "Brain")
"""

import re
import numpy as np
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, field
from .paddle_ocr_extractor import OCRResult, OCROutput
import logging

logger = logging.getLogger(__name__)


@dataclass
class ExtractedField:
    """Extracted field with metadata"""
    field_name: str
    value: str
    confidence: float
    source_text: str
    bbox: List[List[int]]
    spatial_score: float = 0.0


@dataclass
class InvoiceData:
    """Complete extracted invoice data"""
    vendor_name: Optional[str] = None
    invoice_date: Optional[str] = None
    total_amount: Optional[str] = None
    tax_amount: Optional[str] = None
    invoice_number: Optional[str] = None
    
    # Additional fields
    subtotal: Optional[str] = None
    due_date: Optional[str] = None
    currency: Optional[str] = None
    
    # Metadata
    fields: List[ExtractedField] = field(default_factory=list)
    extraction_confidence: float = 0.0
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'vendor_name': self.vendor_name,
            'invoice_date': self.invoice_date,
            'total_amount': self.total_amount,
            'tax_amount': self.tax_amount,
            'invoice_number': self.invoice_number,
            'subtotal': self.subtotal,
            'due_date': self.due_date,
            'currency': self.currency,
            'extraction_confidence': self.extraction_confidence,
            'fields_found': len([f for f in [self.vendor_name, self.invoice_date, 
                                              self.total_amount, self.tax_amount, 
                                              self.invoice_number] if f])
        }


class DataExtractor:
    """
    Extract structured invoice data using regex patterns and spatial heuristics.
    """
    
    def __init__(self):
        # Regex patterns for different field types
        self.patterns = {
            'date': [
                r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b',  # 01/01/2024 or 01-01-24
                r'\b(\d{4}[/-]\d{1,2}[/-]\d{1,2})\b',    # 2024/01/01
                r'\b(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4})\b',
                r'\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{4})\b',
            ],
            'amount': [
                r'[$€£¥]?\s*([\d,]+\.\d{2})\b',           # $1,234.56
                r'[$€£¥]?\s*([\d,]+)\b',                  # $1,234
                r'\b(Total|Amount|Due)[:\s]*[$€£¥]?\s*([\d,]+\.?\d{0,2})\b',
            ],
            'tax_id': [
                r'\b(TIN|VAT|GST|EIN)[\s:#]*(\d[-\w]+)\b',
                r'\bTax\s*ID[:\s#]*(\d[-\w]+)\b',
            ],
            'invoice_number': [
                r'\b(?:Invoice|Inv)[\s#:]*(\d{3,}[-\w]*)\b',
                r'\b(?:Invoice|Inv)\s*(?:No|Number|#)[:\s#]*(\d{3,}[-\w]*)\b',
                r'\b(?:INV|IN)[-\s]*(\d{3,}[-\w]*)\b',
            ],
            'currency': [
                r'[$€£¥]',
                r'\b(USD|EUR|GBP|JPY|CAD|AUD)\b',
            ]
        }
        
        # Anchor keywords for spatial search
        self.anchor_keywords = {
            'total': ['total', 'amount due', 'grand total', 'final total', 'payment due'],
            'tax': ['tax', 'vat', 'gst', 'sales tax'],
            'invoice': ['invoice', 'invoice number', 'inv #', 'bill'],
            'date': ['date', 'invoice date', 'issue date'],
            'vendor': ['from', 'seller', 'vendor', 'billed by'],
        }
        
        logger.info("DataExtractor initialized")
    
    def extract(self, ocr_output: OCROutput) -> InvoiceData:
        """
        Extract structured data from OCR output.
        
        Args:
            ocr_output: OCR results from PaddleOCRExtractor
            
        Returns:
            InvoiceData with extracted fields
        """
        results = ocr_output.results
        invoice_data = InvoiceData()
        extracted_fields = []
        
        # Extract invoice number
        invoice_num = self._extract_invoice_number(results)
        if invoice_num:
            invoice_data.invoice_number = invoice_num.value
            extracted_fields.append(invoice_num)
        
        # Extract dates
        dates = self._extract_dates(results)
        if dates:
            invoice_data.invoice_date = dates[0].value
            extracted_fields.extend(dates)
        
        # Extract amounts using spatial logic
        total = self._extract_amount_by_anchor(results, 'total')
        if total:
            invoice_data.total_amount = total.value
            extracted_fields.append(total)
        
        tax = self._extract_amount_by_anchor(results, 'tax')
        if tax:
            invoice_data.tax_amount = tax.value
            extracted_fields.append(tax)
        
        # Extract vendor name
        vendor = self._extract_vendor(results)
        if vendor:
            invoice_data.vendor_name = vendor.value
            extracted_fields.append(vendor)
        
        # Calculate overall confidence
        if extracted_fields:
            avg_confidence = np.mean([f.confidence for f in extracted_fields])
            invoice_data.extraction_confidence = round(avg_confidence, 2)
        
        invoice_data.fields = extracted_fields
        
        logger.info(f"Extraction complete: {len(extracted_fields)} fields, "
                   f"confidence: {invoice_data.extraction_confidence}")
        
        return invoice_data
    
    def _extract_invoice_number(self, results: List[OCRResult]) -> Optional[ExtractedField]:
        """Extract invoice number using regex patterns"""
        for result in results:
            text = result.text.strip()
            for pattern in self.patterns['invoice_number']:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    return ExtractedField(
                        field_name='invoice_number',
                        value=match.group(1),
                        confidence=result.confidence,
                        source_text=text,
                        bbox=result.bbox
                    )
        return None
    
    def _extract_dates(self, results: List[OCRResult]) -> List[ExtractedField]:
        """Extract dates using regex patterns"""
        dates = []
        for result in results:
            text = result.text.strip()
            for pattern in self.patterns['date']:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    dates.append(ExtractedField(
                        field_name='date',
                        value=match.group(1),
                        confidence=result.confidence,
                        source_text=text,
                        bbox=result.bbox
                    ))
                    break  # Only take first match per result
        return dates
    
    def _extract_amount_by_anchor(self, results: List[OCRResult], 
                                   anchor_type: str) -> Optional[ExtractedField]:
        """
        Find amount using spatial relationship with anchor keywords.
        Searches to the immediate right and below the anchor word.
        """
        anchors = self.anchor_keywords.get(anchor_type, [anchor_type])
        
        for i, result in enumerate(results):
            text_lower = result.text.lower().strip()
            
            # Check if this result contains an anchor keyword
            if any(anchor in text_lower for anchor in anchors):
                anchor_bbox = result.bbox
                anchor_center = self._get_center(anchor_bbox)
                
                # Search for amount to the right and below
                best_match = None
                best_score = float('inf')
                
                for j, candidate in enumerate(results):
                    if i == j:
                        continue
                    
                    candidate_bbox = candidate.bbox
                    candidate_center = self._get_center(candidate_bbox)
                    
                    # Check spatial relationship
                    direction_score = self._calculate_direction_score(
                        anchor_center, candidate_center, anchor_type
                    )
                    
                    if direction_score < best_score:
                        # Check if candidate contains an amount
                        amount_match = re.search(
                            r'[$€£¥]?\s*([\d,]+\.?\d{0,2})', 
                            candidate.text
                        )
                        if amount_match:
                            best_match = candidate
                            best_score = direction_score
                
                if best_match:
                    # Extract amount value
                    amount_match = re.search(
                        r'[$€£¥]?\s*([\d,]+\.?\d{0,2})', 
                        best_match.text
                    )
                    if amount_match:
                        return ExtractedField(
                            field_name=f'{anchor_type}_amount',
                            value=amount_match.group(1).replace(',', ''),
                            confidence=best_match.confidence * (1 - best_score),
                            source_text=best_match.text,
                            bbox=best_match.bbox,
                            spatial_score=1 - best_score
                        )
        
        return None
    
    def _extract_vendor(self, results: List[OCRResult]) -> Optional[ExtractedField]:
        """
        Extract vendor name using spatial heuristics.
        Looks for company names near 'From:' or at top of invoice.
        """
        # Strategy 1: Look for text after "From:" or similar
        for i, result in enumerate(results):
            text_lower = result.text.lower()
            if any(keyword in text_lower for keyword in ['from:', 'seller:', 'vendor:']):
                # Look for company name in next few results
                for j in range(i + 1, min(i + 4, len(results))):
                    candidate = results[j]
                    # Check if it looks like a company name
                    if self._is_company_name(candidate.text):
                        return ExtractedField(
                            field_name='vendor_name',
                            value=candidate.text.strip(),
                            confidence=candidate.confidence,
                            source_text=candidate.text,
                            bbox=candidate.bbox
                        )
        
        # Strategy 2: Look for company name patterns
        for result in results:
            if self._is_company_name(result.text):
                return ExtractedField(
                    field_name='vendor_name',
                    value=result.text.strip(),
                    confidence=result.confidence,
                    source_text=result.text,
                    bbox=result.bbox
                )
        
        return None
    
    def _get_center(self, bbox: List[List[int]]) -> Tuple[float, float]:
        """Calculate center point of bounding box"""
        xs = [p[0] for p in bbox]
        ys = [p[1] for p in bbox]
        return (sum(xs) / len(xs), sum(ys) / len(ys))
    
    def _calculate_direction_score(self, 
                                    anchor: Tuple[float, float],
                                    candidate: Tuple[float, float],
                                    field_type: str) -> float:
        """
        Calculate how well positioned the candidate is relative to anchor.
        Lower score = better match.
        """
        dx = candidate[0] - anchor[0]
        dy = candidate[1] - anchor[1]
        
        # For amounts, we expect them to be to the right or slightly below
        if field_type in ['total', 'tax']:
            # Ideal: to the right (positive dx) and slightly below or aligned
            right_score = max(0, -dx) / 100  # Penalize if left of anchor
            vertical_score = abs(dy) / 50    # Penalize vertical distance
            return right_score + vertical_score
        
        # General: prefer close proximity
        return np.sqrt(dx**2 + dy**2) / 100
    
    def _is_company_name(self, text: str) -> bool:
        """Check if text looks like a company name"""
        text = text.strip()
        
        # Skip if too short or too long
        if len(text) < 3 or len(text) > 100:
            return False
        
        # Skip if it contains amounts or dates
        if re.search(r'\d+\.\d{2}', text):  # Dollar amounts
            return False
        if re.search(r'\d{1,2}[/-]\d', text):  # Dates
            return False
        
        # Skip if it contains invoice keywords
        skip_keywords = ['invoice', 'bill', 'receipt', 'date', 'total', 'tax']
        if any(kw in text.lower() for kw in skip_keywords):
            return False
        
        # Must contain letters
        if not re.search(r'[A-Za-z]{2,}', text):
            return False
        
        # Check for company indicators
        company_indicators = [
            r'\b(?:Inc|LLC|Ltd|Corp|Corporation|Company|Co\.)\b',
            r'\b(?:GmbH|S\.A\.|B\.V\.|Pty|Limited)\b',
        ]
        if any(re.search(pattern, text) for pattern in company_indicators):
            return True
        
        # Accept if it looks like a proper name
        words = text.split()
        if len(words) >= 1 and words[0][0].isupper():
            return True
        
        return False


# Convenience function
def extract_invoice_data(ocr_output: OCROutput) -> InvoiceData:
    """Quick data extraction"""
    extractor = DataExtractor()
    return extractor.extract(ocr_output)
