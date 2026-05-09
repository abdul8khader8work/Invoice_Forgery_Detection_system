"""
Advanced Invoice Information Extraction System
Provides robust field extraction with multiple pattern matching strategies
"""

import re
import json
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class ExtractedField:
    """Represents an extracted field with confidence and context"""
    value: Any
    raw_text: str
    confidence: float
    method: str
    position: Optional[Tuple[int, int]] = None


class FieldPatternMatcher:
    """Advanced pattern matching for invoice fields with multiple strategies"""
    
    # Comprehensive label variations for each field type
    FIELD_LABELS = {
        'vendor_name': [
            r'(?:from|vendor|seller|supplier|billed by|bill from|invoice from|company|business|merchant)\s*:?\s*',
            r'(?:sold by|shipped by|dealer|provider|contractor|consultant)\s*:?\s*',
        ],
        'invoice_number': [
            r'(?:invoice\s*(?:#|no|number|num|#?)|inv\.?\s*|bill\s*(?:#|no|number)?)\s*:?\s*',
            r'(?:receipt\s*(?:#|no|number)?|order\s*(?:#|ref|reference)?|transaction\s*id)\s*:?\s*',
            r'(?:document\s*(?:#|no)|booking\s*(?:#|ref)|confirmation\s*#?)\s*:?\s*',
        ],
        'invoice_date': [
            r'(?:invoice\s*date|date\s*(?:of\s*)?invoice|bill\s*date|issue\s*date|created\s*date)\s*:?\s*',
            r'(?:date|invoice\s*dated|dated|issued?|generated|created)\s*:?\s*',
        ],
        'due_date': [
            r'(?:due\s*date|payment\s*due|date\s*due|pay\s*by|must\s*pay\s*by)\s*:?\s*',
            r'(?:due|payment\s*date|settlement\s*date|deadline)\s*:?\s*',
        ],
        'subtotal': [
            r'(?:sub\s*total|subtotal|net\s*amount|amount\s*before\s*tax|gross\s*amount)\s*:?\s*[$€£]?\s*',
            r'(?:total\s*before\s*tax|pre[-\s]?tax\s*total|net\s*total)\s*:?\s*[$€£]?\s*',
        ],
        'tax': [
            r'(?:tax|vat|gst|sales\s*tax|vat\s*amount|tax\s*amount|gst\s*amount)\s*:?\s*[$€£]?\s*',
            r'(?:taxes|vat\s*total|gst\s*total|vat\s*@\s*\d+%?)\s*:?\s*[$€£]?\s*',
        ],
        'tax_rate': [
            r'(?:tax\s*rate|vat\s*rate|gst\s*rate|rate\s*of\s*tax)\s*:?\s*',
            r'(?:vat\s*@|tax\s*@|gst\s*@)\s*',
        ],
        'total': [
            r'(?:total|grand\s*total|amount\s*due|balance\s*due|total\s*amount|final\s*total)\s*:?\s*[$€£]?\s*',
            r'(?:total\s*payable|amount\s*payable|total\s*due|sum\s*total|invoice\s*total)\s*:?\s*[$€£]?\s*',
            r'(?:to\s*pay|payable|balance|final\s*amount)\s*:?\s*[$€£]?\s*',
        ],
        'discount': [
            r'(?:discount|less\s*discount|discount\s*amount|promo\s*discount)\s*:?\s*[$€£-]?\s*',
            r'(?:savings|coupon\s*discount|promotional\s*discount)\s*:?\s*[$€£-]?\s*',
        ],
        'shipping': [
            r'(?:shipping|delivery|freight|transport|carriage|postage|handling)\s*(?:fee|cost|charge)?\s*:?\s*[$€£]?\s*',
            r'(?:ship\s*charge|delivery\s*fee|transport\s*cost)\s*:?\s*[$€£]?\s*',
        ],
        'po_number': [
            r'(?:p\.?o\.?\s*(?:#|no|number)?|purchase\s*order|customer\s*po|your\s*po)\s*:?\s*',
            r'(?:order\s*#|reference\s*#|cust\s*ref)\s*:?\s*',
        ],
        'account_number': [
            r'(?:account\s*(?:#|no|number)|acct\s*(?:#|no)?|customer\s*#|client\s*#)\s*:?\s*',
            r'(?:account\s*id|member\s*#|cust\s*id)\s*:?\s*',
        ],
        'payment_terms': [
            r'(?:payment\s*terms|terms|net|due\s*in|pay\s*within)\s*:?\s*',
            r'(?:net\s*\d+|net\s*days|days\s*to\s*pay)\s*:?\s*',
        ],
    }
    
    # Value extraction patterns
    VALUE_PATTERNS = {
        'vendor_name': [
            r'^([A-Z][A-Za-z0-9\s&.,]+(?:Inc|LLC|Ltd|Limited|Corp|Corporation|Company|Co|GmbH|BV|LLP|PLC)?)',
            r'([A-Z][A-Za-z0-9\s&.,]{3,50})',
        ],
        'invoice_number': [
            r'([A-Z]{0,4}\d{3,12}(?:[-_]\d{2,6})?)',
            r'([A-Z]\d{7,10})',
            r'(\d{6,12})',
            r'(INV[-]?\d{3,8})',
        ],
        'date': [
            # MM/DD/YYYY or MM-DD-YYYY
            r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
            # DD/MM/YYYY or DD-MM-YYYY
            r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
            # YYYY-MM-DD (ISO format)
            r'(\d{4}[/-]\d{1,2}[/-]\d{1,2})',
            # Month DD, YYYY or DD Month YYYY
            r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4})',
            r'(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{2,4})',
            # DD Mon YYYY
            r'(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{2,4})',
        ],
        'amount': [
            # Currency with commas and decimals
            r'([$€£]\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?)',
            r'(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)',
            r'(\d+(?:\.\d{2})?)',
            # With currency code after
            r'(\d{1,3}(?:,\d{3})*(?:\.\d{2})?\s*(?:USD|EUR|GBP|CAD|AUD|INR))',
        ],
        'percentage': [
            r'(\d{1,2}(?:\.\d{1,2})?\s*%)',
            r'(\d{1,2}(?:\.\d{1,2})?\s*percent)',
            r'@?\s*(\d{1,2}(?:\.\d{1,2})?)%?',
        ],
    }
    
    def __init__(self):
        self.compiled_patterns = self._compile_patterns()
    
    def _compile_patterns(self) -> Dict[str, List[re.Pattern]]:
        """Compile all regex patterns for efficiency"""
        compiled = {}
        for field, patterns in self.FIELD_LABELS.items():
            compiled[field] = [re.compile(p, re.IGNORECASE) for p in patterns]
        for field, patterns in self.VALUE_PATTERNS.items():
            compiled[field] = [re.compile(p, re.IGNORECASE) for p in patterns]
        return compiled
    
    def find_field_context(self, text: str, field_type: str) -> List[Tuple[str, int, float]]:
        """
        Find all potential contexts for a field in text.
        Returns list of (matched_text, position, confidence)
        """
        contexts = []
        patterns = self.FIELD_LABELS.get(field_type, [])
        
        for pattern in patterns:
            compiled = re.compile(pattern, re.IGNORECASE)
            for match in compiled.finditer(text):
                # Get surrounding context (200 chars after label)
                start = match.end()
                end = min(start + 200, len(text))
                context = text[start:end]
                
                # Calculate confidence based on label specificity
                confidence = 0.5 + (0.1 * len(pattern.split('|')))
                confidence = min(confidence, 0.9)
                
                contexts.append((context, start, confidence))
        
        return contexts
    
    def extract_value(self, context: str, value_type: str) -> Optional[ExtractedField]:
        """Extract a value from context using appropriate patterns"""
        patterns = self.VALUE_PATTERNS.get(value_type, [])
        
        for i, pattern in enumerate(patterns):
            compiled = re.compile(pattern, re.IGNORECASE)
            match = compiled.search(context)
            if match:
                raw_value = match.group(1) if match.groups() else match.group(0)
                confidence = 0.7 + (0.05 * (len(patterns) - i - 1))  # Earlier patterns = higher confidence
                
                return ExtractedField(
                    value=self._clean_value(raw_value, value_type),
                    raw_text=raw_value,
                    confidence=min(confidence, 0.95),
                    method=f"pattern_{i}",
                    position=(match.start(), match.end())
                )
        
        return None
    
    def _clean_value(self, value: str, value_type: str) -> Any:
        """Clean and convert extracted values"""
        if not value:
            return None
        
        value = value.strip()
        
        if value_type == 'amount':
            # Remove currency symbols and commas
            cleaned = re.sub(r'[$€£,\s]', '', value)
            try:
                return float(cleaned)
            except ValueError:
                return value
        
        elif value_type == 'percentage':
            cleaned = re.sub(r'[%\s]', '', value)
            try:
                return float(cleaned)
            except ValueError:
                return value
        
        elif value_type == 'date':
            # Try to parse date
            return self._parse_date(value)
        
        elif value_type == 'vendor_name':
            # Clean up vendor name
            value = re.sub(r'\s+', ' ', value)  # Normalize whitespace
            value = re.sub(r'^[\s:,-]+|[\s:,-]+$', '', value)  # Trim separators
            return value
        
        return value
    
    def _parse_date(self, date_str: str) -> Optional[str]:
        """Parse various date formats"""
        date_formats = [
            '%m/%d/%Y', '%m-%d-%Y',
            '%d/%m/%Y', '%d-%m-%Y',
            '%Y/%m/%d', '%Y-%m-%d',
            '%m/%d/%y', '%m-%d-%y',
            '%d/%m/%y', '%d-%m-%y',
            '%B %d, %Y', '%b %d, %Y',
            '%d %B %Y', '%d %b %Y',
            '%B %d %Y', '%b %d %Y',
        ]
        
        # Try each format
        for fmt in date_formats:
            try:
                parsed = datetime.strptime(date_str.strip(), fmt)
                return parsed.strftime('%Y-%m-%d')
            except ValueError:
                continue
        
        # If standard parsing fails, return original
        return date_str


class SmartInvoiceExtractor:
    """
    Intelligent invoice information extractor using multiple strategies:
    1. Pattern-based extraction with fuzzy matching
    2. Context-aware field extraction
    3. Cross-validation between fields
    4. Line-item extraction
    """
    
    def __init__(self):
        self.matcher = FieldPatternMatcher()
    
    def extract_all(self, raw_text: str) -> Dict[str, Any]:
        """
        Extract all invoice fields from raw text.
        Returns structured data with confidence scores.
        """
        # Normalize text
        text = self._normalize_text(raw_text)
        
        extracted = {
            'vendor_name': self._extract_vendor_name(text),
            'invoice_number': self._extract_invoice_number(text),
            'invoice_date': self._extract_date_field(text, 'invoice_date'),
            'due_date': self._extract_date_field(text, 'due_date'),
            'subtotal': self._extract_amount_field(text, 'subtotal'),
            'tax': self._extract_amount_field(text, 'tax'),
            'tax_rate': self._extract_percentage_field(text, 'tax_rate'),
            'total': self._extract_amount_field(text, 'total'),
            'discount': self._extract_amount_field(text, 'discount'),
            'shipping': self._extract_amount_field(text, 'shipping'),
            'po_number': self._extract_field_with_patterns(text, 'po_number', 'invoice_number'),
            'account_number': self._extract_field_with_patterns(text, 'account_number', 'invoice_number'),
            'payment_terms': self._extract_payment_terms(text),
            'line_items': self._extract_line_items(text),
        }
        
        # Add confidence scores
        confidence_scores = {}
        for field, value in extracted.items():
            if isinstance(value, ExtractedField):
                confidence_scores[field] = value.confidence
                extracted[field] = value.value
            elif isinstance(value, list) and value and isinstance(value[0], ExtractedField):
                confidence_scores[field] = sum(item.confidence for item in value) / len(value)
                extracted[field] = [item.value for item in value]
            else:
                confidence_scores[field] = 0.0 if value is None else 0.5
        
        return {
            'extracted_data': extracted,
            'confidence_scores': confidence_scores,
            'raw_text': raw_text[:2000],  # Store first 2000 chars for reference
        }
    
    def _normalize_text(self, text: str) -> str:
        """Normalize text for better extraction"""
        # Remove excessive whitespace
        text = re.sub(r'\n\s*\n', '\n', text)
        text = re.sub(r'[ \t]+', ' ', text)
        
        # Normalize common OCR errors
        replacements = [
            (r'[|]', 'I'),  # Pipe to I
            (r'0', 'O'),    # Zero to O (context-dependent)
            (r'S', '5'),    # S to 5 (context-dependent)
        ]
        
        return text.strip()
    
    def _extract_vendor_name(self, text: str) -> Optional[ExtractedField]:
        """Extract vendor name with multiple strategies"""
        strategies = [
            self._vendor_from_header,
            self._vendor_from_label,
            self._vendor_from_lines,
        ]
        
        for strategy in strategies:
            result = strategy(text)
            if result and result.confidence > 0.6:
                return result
        
        return None
    
    def _vendor_from_header(self, text: str) -> Optional[ExtractedField]:
        """Look for vendor name in document header"""
        lines = text.split('\n')[:15]  # First 15 lines
        
        for i, line in enumerate(lines):
            line = line.strip()
            # Look for company indicators
            if re.search(r'(?:Inc|LLC|Ltd|Limited|Corp|Corporation|Company|Co\.?|GmbH|BV)$', line, re.IGNORECASE):
                if len(line) > 3 and len(line) < 100:
                    return ExtractedField(
                        value=line,
                        raw_text=line,
                        confidence=0.85,
                        method='header_company_suffix'
                    )
            
            # Look for lines that look like company names (Title Case, no numbers)
            if re.match(r'^[A-Z][a-zA-Z\s&.,]{3,50}$', line):
                if not any(word in line.lower() for word in ['invoice', 'bill', 'date', 'total', 'amount']):
                    return ExtractedField(
                        value=line,
                        raw_text=line,
                        confidence=0.7,
                        method='header_title_case'
                    )
        
        return None
    
    def _vendor_from_label(self, text: str) -> Optional[ExtractedField]:
        """Extract vendor from "From:" or similar labels"""
        contexts = self.matcher.find_field_context(text, 'vendor_name')
        
        for context, position, label_conf in contexts:
            # Look for company name in context
            company_match = re.search(
                r'([A-Z][A-Za-z0-9\s&.,]+(?:Inc|LLC|Ltd|Limited|Corp|Corporation|Company|Co|GmbH|BV)?)',
                context[:100]
            )
            
            if company_match:
                name = company_match.group(1).strip()
                if len(name) > 3:
                    return ExtractedField(
                        value=name,
                        raw_text=name,
                        confidence=label_conf * 0.9,
                        method='label_company'
                    )
        
        return None
    
    def _vendor_from_lines(self, text: str) -> Optional[ExtractedField]:
        """Extract vendor from analyzing line patterns"""
        lines = text.split('\n')
        
        for line in lines[:20]:
            line = line.strip()
            # Skip lines with numbers/dates
            if re.search(r'\d{2,}', line):
                continue
            
            # Skip common non-vendor words
            skip_words = ['invoice', 'date', 'page', 'tel', 'fax', 'email', 'www', 'http']
            if any(word in line.lower() for word in skip_words):
                continue
            
            # Look for substantial text that could be a company name
            if len(line) > 10 and len(line) < 60:
                words = line.split()
                if len(words) >= 2:
                    return ExtractedField(
                        value=line,
                        raw_text=line,
                        confidence=0.5,
                        method='line_heuristic'
                    )
        
        return None
    
    def _extract_invoice_number(self, text: str) -> Optional[ExtractedField]:
        """Extract invoice number with multiple strategies"""
        contexts = self.matcher.find_field_context(text, 'invoice_number')
        
        best_result = None
        best_confidence = 0.0
        
        for context, position, label_conf in contexts:
            # Try each pattern
            for pattern_name in ['invoice_number', 'invoice_number', 'invoice_number']:
                result = self.matcher.extract_value(context, 'invoice_number')
                if result:
                    combined_conf = (label_conf + result.confidence) / 2
                    if combined_conf > best_confidence:
                        best_confidence = combined_conf
                        best_result = result
        
        # Also search entire text for invoice-like patterns
        if not best_result or best_confidence < 0.6:
            invoice_patterns = [
                r'(?:INV|IN|BILL|DOC)[-]?\s*(\d{3,10})',
                r'(?:Invoice|Bill)\s*#?\s*(\d{3,12})',
                r'#\s*(\d{6,12})',
            ]
            
            for pattern in invoice_patterns:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    value = match.group(1)
                    return ExtractedField(
                        value=value,
                        raw_text=match.group(0),
                        confidence=0.75,
                        method='pattern_search'
                    )
        
        return best_result
    
    def _extract_date_field(self, text: str, field_type: str) -> Optional[ExtractedField]:
        """Extract date field with context awareness"""
        contexts = self.matcher.find_field_context(text, field_type)
        
        for context, position, label_conf in contexts:
            result = self.matcher.extract_value(context, 'date')
            if result:
                result.confidence = (label_conf + result.confidence) / 2
                return result
        
        # Fallback: search for any date-like pattern
        if not contexts:
            date_pattern = r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})'
            matches = list(re.finditer(date_pattern, text))
            if matches:
                # For invoice_date, take first; for due_date, take second or later
                if field_type == 'invoice_date':
                    match = matches[0]
                elif len(matches) > 1:
                    match = matches[1]
                else:
                    return None
                
                parsed_date = self.matcher._parse_date(match.group(1))
                if parsed_date:
                    return ExtractedField(
                        value=parsed_date,
                        raw_text=match.group(1),
                        confidence=0.6,
                        method='date_fallback'
                    )
        
        return None
    
    def _extract_amount_field(self, text: str, field_type: str) -> Optional[ExtractedField]:
        """Extract monetary amount field"""
        contexts = self.matcher.find_field_context(text, field_type)
        
        best_result = None
        best_confidence = 0.0
        
        for context, position, label_conf in contexts:
            result = self.matcher.extract_value(context, 'amount')
            if result:
                combined_conf = (label_conf + result.confidence) / 2
                if combined_conf > best_confidence:
                    best_confidence = combined_conf
                    best_result = result
        
        # Special handling for total - look for largest amount
        if field_type == 'total' and not best_result:
            amounts = self._find_all_amounts(text)
            if amounts:
                # Usually the largest amount is the total
                largest = max(amounts, key=lambda x: x['value'])
                return ExtractedField(
                    value=largest['value'],
                    raw_text=largest['raw'],
                    confidence=0.65,
                    method='largest_amount'
                )
        
        return best_result
    
    def _extract_percentage_field(self, text: str, field_type: str) -> Optional[ExtractedField]:
        """Extract percentage/tax rate field"""
        contexts = self.matcher.find_field_context(text, field_type)
        
        for context, position, label_conf in contexts:
            result = self.matcher.extract_value(context, 'percentage')
            if result:
                result.confidence = (label_conf + result.confidence) / 2
                return result
        
        # Look for common tax rates
        tax_pattern = r'(\d{1,2}(?:\.\d{1,2})?)\s*%'
        match = re.search(tax_pattern, text)
        if match:
            value = float(match.group(1))
            if 0 < value < 50:  # Reasonable tax rate
                return ExtractedField(
                    value=value,
                    raw_text=match.group(0),
                    confidence=0.7,
                    method='tax_rate_pattern'
                )
        
        return None
    
    def _extract_field_with_patterns(self, text: str, field_type: str, value_type: str) -> Optional[ExtractedField]:
        """Generic field extraction with label patterns"""
        contexts = self.matcher.find_field_context(text, field_type)
        
        for context, position, label_conf in contexts:
            result = self.matcher.extract_value(context, value_type)
            if result:
                result.confidence = (label_conf + result.confidence) / 2
                return result
        
        return None
    
    def _extract_payment_terms(self, text: str) -> Optional[ExtractedField]:
        """Extract payment terms like Net 30"""
        patterns = [
            r'(?:Net|Due in|Payment due)\s+(\d{1,3})\s*(?:days?)?',
            r'(\d{1,3})\s*days?\s*(?:to\s*pay)?',
        ]
        
        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                days = int(match.group(1))
                return ExtractedField(
                    value=f"Net {days}",
                    raw_text=match.group(0),
                    confidence=0.8,
                    method='payment_terms_pattern'
                )
        
        return None
    
    def _extract_line_items(self, text: str) -> List[ExtractedField]:
        """Extract line items from invoice"""
        line_items = []
        
        # Look for table-like structures
        lines = text.split('\n')
        in_table = False
        
        for line in lines:
            # Detect start of item section
            if re.search(r'(?:qty|quantity|item|description|product)', line, re.IGNORECASE):
                in_table = True
                continue
            
            if not in_table:
                continue
            
            # Try to parse line item
            # Pattern: description, quantity, unit price, total
            item_pattern = r'(.*?)\s+(\d+(?:\.\d{1,2})?)\s+[$€£]?\s*(\d+[\.,]?\d{0,2})\s+[$€£]?\s*(\d+[\.,]?\d{2})'
            match = re.search(item_pattern, line)
            
            if match:
                item = {
                    'description': match.group(1).strip(),
                    'quantity': float(match.group(2)),
                    'unit_price': float(match.group(3).replace(',', '.')),
                    'line_total': float(match.group(4).replace(',', '.')),
                }
                line_items.append(ExtractedField(
                    value=item,
                    raw_text=line,
                    confidence=0.75,
                    method='line_item_pattern'
                ))
        
        return line_items
    
    def _find_all_amounts(self, text: str) -> List[Dict]:
        """Find all monetary amounts in text"""
        amounts = []
        pattern = r'[$€£]?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)'
        
        for match in re.finditer(pattern, text):
            try:
                value_str = match.group(1).replace(',', '').replace('$', '').replace('€', '').replace('£', '')
                value = float(value_str)
                amounts.append({
                    'value': value,
                    'raw': match.group(0),
                    'position': match.start()
                })
            except ValueError:
                continue
        
        return amounts


# Convenience function for external use
def extract_invoice_data(raw_text: str) -> Dict[str, Any]:
    """
    Main entry point for invoice data extraction.
    
    Args:
        raw_text: Raw OCR text from invoice
        
    Returns:
        Dictionary with extracted_data and confidence_scores
    """
    extractor = SmartInvoiceExtractor()
    return extractor.extract_all(raw_text)


if __name__ == '__main__':
    # Test with sample invoice text
    sample = """
    ABC Company Inc.
    123 Business Street
    
    INVOICE # INV-2024-001
    Date: 03/15/2024
    Due Date: 04/15/2024
    
    Bill To:
    Customer XYZ
    
    Description          Qty    Unit Price    Total
    Consulting Services   10      $150.00    $1,500.00
    Software License       1      $500.00      $500.00
    
    Subtotal:                         $2,000.00
    Tax (10%):                          $200.00
    Total Due:                        $2,200.00
    """
    
    result = extract_invoice_data(sample)
    print(json.dumps(result, indent=2, default=str))
