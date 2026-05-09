"""
Dynamic Field Discovery Engine
Detects what's actually in the invoice - no hardcoded field assumptions
"""

import re
import logging
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime

logger = logging.getLogger(__name__)


class FieldDiscoverer:
    """
    Discovers fields dynamically from OCR output
    Finds whatever is present: dates, amounts, invoice numbers, etc.
    """
    
    def __init__(self):
        # Pattern library - covers common invoice formats
        self.patterns = {
            'invoice_number': [
                r'(?:INV|Invoice|Bill|Order)[\s#:-]*(\d{4,})',
                r'#(\d{6,})',
                r'INV[A-Z0-9]{4,}',
                r'No[\s:]+(\d{4,})',
                r'Number[\s:]+(\d{4,})',
            ],
            'date': [
                r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
                r'(\d{4}[/-]\d{1,2}[/-]\d{1,2})',
                r'(\d{1,2}\s+[A-Za-z]{3,}\s+\d{2,4})',
                r'(\d{1,2}\s+[A-Za-z]{3,}\s+\d{4})',
            ],
            'amount': [
                r'[\$₹€£]?\s*([\d,]+\.?\d*)',
                r'([\d,]+\.?\d*)\s*[\$₹€£]?',
            ],
            'email': [
                r'[\w\.-]+@[\w\.-]+\.\w+',
            ],
            'phone': [
                r'[\+]?[\d\s-]{10,}',
            ],
            'gstin': [
                r'[A-Z]{5}\d{4}[A-Z]{1}[A-Z\d]{1}[Z]{1}[A-Z\d]{1}',
            ],
            'website': [
                r'https?://[\w\.-]+',
                r'www\.[\w\.-]+',
            ],
        }
    
    def discover_all_fields(self, ocr_boxes: List[Dict]) -> Dict[str, Any]:
        """
        Discover all fields present in the OCR output
        
        Returns:
            Dict with all discovered fields and their metadata
        """
        full_text = ' '.join([box.get('text', '') for box in ocr_boxes])
        
        discovered = {
            'invoice_numbers': self._extract_invoice_numbers(full_text),
            'dates': self._extract_dates(full_text),
            'amounts': self._extract_amounts(full_text, ocr_boxes),
            'emails': self._extract_emails(full_text),
            'phones': self._extract_phones(full_text),
            'gstins': self._extract_gstin(full_text),
            'websites': self._extract_websites(full_text),
            'vendor_names': self._extract_vendor_names(ocr_boxes),
            'line_items': self._extract_line_items(ocr_boxes),
            'raw_text_blocks': [box.get('text', '') for box in ocr_boxes],
        }
        
        # Determine what's actually present
        present_fields = {
            field: len(values) > 0 
            for field, values in discovered.items()
            if isinstance(values, list)
        }
        
        # Calculate confidence based on field coverage
        total_fields = len(present_fields)
        found_fields = sum(present_fields.values())
        confidence = found_fields / total_fields if total_fields > 0 else 0
        
        return {
            'discovered_fields': discovered,
            'present_fields': present_fields,
            'field_coverage': {
                'total_fields': total_fields,
                'found_fields': found_fields,
                'coverage_percent': round(confidence * 100, 1)
            },
            'confidence': round(confidence, 2)
        }
    
    def _extract_invoice_numbers(self, text: str) -> List[Dict]:
        """Extract all invoice numbers with context"""
        results = []
        for pattern in self.patterns['invoice_number']:
            matches = re.finditer(pattern, text, re.IGNORECASE)
            for match in matches:
                results.append({
                    'value': match.group(0),
                    'number': match.group(1) if match.groups() else match.group(0),
                    'start': match.start(),
                    'end': match.end()
                })
        return results
    
    def _extract_dates(self, text: str) -> List[Dict]:
        """Extract all dates with context"""
        results = []
        for pattern in self.patterns['date']:
            matches = re.finditer(pattern, text)
            for match in matches:
                date_str = match.group(1)
                # Try to parse and standardize
                try:
                    parsed = self._parse_date(date_str)
                    results.append({
                        'value': date_str,
                        'parsed': parsed,
                        'start': match.start(),
                        'end': match.end()
                    })
                except:
                    results.append({
                        'value': date_str,
                        'parsed': None,
                        'start': match.start(),
                        'end': match.end()
                    })
        return results
    
    def _parse_date(self, date_str: str) -> Optional[str]:
        """Try to parse date to ISO format"""
        formats = [
            '%d/%m/%Y', '%d-%m-%Y', '%d.%m.%Y',
            '%m/%d/%Y', '%m-%d-%Y', '%m.%d.%Y',
            '%Y/%m/%d', '%Y-%m-%d',
            '%d %B %Y', '%d %b %Y',
            '%B %d %Y', '%b %d %Y',
        ]
        for fmt in formats:
            try:
                dt = datetime.strptime(date_str, fmt)
                return dt.strftime('%Y-%m-%d')
            except:
                continue
        return None
    
    def _extract_amounts(self, text: str, ocr_boxes: List[Dict]) -> List[Dict]:
        """Extract all amounts with context and labels"""
        results = []
        
        # Find all amounts with their context (what label they're near)
        for i, box in enumerate(ocr_boxes):
            box_text = box.get('text', '')
            
            for pattern in self.patterns['amount']:
                matches = re.finditer(pattern, box_text)
                for match in matches:
                    amount_str = match.group(1).replace(',', '')
                    try:
                        amount = float(amount_str)
                        
                        # Get context from nearby text
                        context = self._get_context(ocr_boxes, i, window=3)
                        
                        results.append({
                            'value': match.group(0),
                            'amount': amount,
                            'position': {
                                'x': box.get('x', 0),
                                'y': box.get('y', 0)
                            },
                            'context': context,
                            'likely_label': self._guess_amount_label(context, amount)
                        })
                    except ValueError:
                        pass
        
        # Sort by amount (usually total is largest)
        results.sort(key=lambda x: x['amount'], reverse=True)
        return results
    
    def _get_context(self, ocr_boxes: List[Dict], index: int, window: int = 3) -> str:
        """Get text context around a box"""
        start = max(0, index - window)
        end = min(len(ocr_boxes), index + window + 1)
        context_boxes = ocr_boxes[start:end]
        return ' '.join([b.get('text', '') for b in context_boxes])
    
    def _guess_amount_label(self, context: str, amount: float) -> str:
        """Guess what type of amount this is based on context"""
        context_lower = context.lower()
        
        labels = {
            'total': ['total', 'grand', 'amount due', 'balance', 'payable'],
            'subtotal': ['subtotal', 'sub total', 'sub-total', 'net'],
            'tax': ['tax', 'gst', 'vat', 'tax amount', 'taxes'],
            'discount': ['discount', 'deduction'],
            'shipping': ['shipping', 'delivery', 'freight'],
            'unit_price': ['price', 'rate', 'unit'],
        }
        
        for label, keywords in labels.items():
            for keyword in keywords:
                if keyword in context_lower:
                    return label
        
        # If it's the largest amount, likely the total
        return 'likely_total' if amount > 100 else 'unknown'
    
    def _extract_emails(self, text: str) -> List[str]:
        """Extract all email addresses"""
        emails = []
        for pattern in self.patterns['email']:
            matches = re.findall(pattern, text)
            emails.extend(matches)
        return list(set(emails))  # Remove duplicates
    
    def _extract_phones(self, text: str) -> List[str]:
        """Extract all phone numbers"""
        phones = []
        for pattern in self.patterns['phone']:
            matches = re.findall(pattern, text)
            phones.extend(matches)
        return list(set(phones))
    
    def _extract_gstin(self, text: str) -> List[str]:
        """Extract GSTIN numbers"""
        gstins = []
        for pattern in self.patterns['gstin']:
            matches = re.findall(pattern, text)
            gstins.extend(matches)
        return list(set(gstins))
    
    def _extract_websites(self, text: str) -> List[str]:
        """Extract all websites"""
        websites = []
        for pattern in self.patterns['website']:
            matches = re.findall(pattern, text)
            websites.extend(matches)
        return list(set(websites))
    
    def _extract_vendor_names(self, ocr_boxes: List[Dict]) -> List[str]:
        """
        Extract potential vendor names
        Heuristic: First few lines, typically uppercase, company name
        """
        candidates = []
        
        # Look at first 10 boxes
        for box in ocr_boxes[:10]:
            text = box.get('text', '').strip()
            # Skip if too short or looks like a label
            if len(text) < 3 or text.lower() in ['invoice', 'bill', 'date', 'total']:
                continue
            # Skip if contains digits (likely not a name)
            if any(c.isdigit() for c in text):
                continue
            # Skip common small words
            if text.lower() in ['the', 'and', 'for', 'from', 'to', 'of']:
                continue
            
            candidates.append(text)
        
        return candidates[:5]  # Return top 5 candidates
    
    def _extract_line_items(self, ocr_boxes: List[Dict]) -> List[Dict]:
        """
        Extract line items from table-like structures
        Heuristic: Look for rows with multiple text elements
        """
        line_items = []
        
        # Group boxes by Y position (rows)
        rows = {}
        for box in ocr_boxes:
            y = box.get('y', 0)
            # Round Y to group nearby boxes
            y_rounded = round(y / 20) * 20  # 20px tolerance
            if y_rounded not in rows:
                rows[y_rounded] = []
            rows[y_rounded].append(box)
        
        # Filter for rows with multiple elements (likely table rows)
        for y, row_boxes in sorted(rows.items()):
            if len(row_boxes) >= 3:  # At least 3 columns
                # Sort by X position
                row_boxes.sort(key=lambda b: b.get('x', 0))
                
                # Extract text from each column
                texts = [b.get('text', '') for b in row_boxes]
                
                # Skip if looks like header
                if any(t.lower() in ['item', 'description', 'qty', 'amount', 'total'] for t in texts):
                    continue
                
                # Try to find amount in the row
                amount = None
                for text in texts:
                    match = re.search(r'([\d,]+\.?\d*)', text)
                    if match:
                        try:
                            amount = float(match.group(1).replace(',', ''))
                            break
                        except:
                            pass
                
                if amount:
                    line_items.append({
                        'description': ' '.join(texts[:-1]) if len(texts) > 1 else texts[0],
                        'amount': amount,
                        'row_y': y
                    })
        
        return line_items[:20]  # Limit to 20 items


class SmartExtractionEngine:
    """
    Smart extraction that works with what's present
    No hardcoded assumptions - discovers fields dynamically
    """
    
    def __init__(self):
        self.discoverer = FieldDiscoverer()
    
    def extract_invoice(self, ocr_boxes: List[Dict]) -> Dict[str, Any]:
        """
        Extract invoice data using field discovery
        
        Returns:
            Dict with all discovered fields, organized by type
        """
        discovery = self.discoverer.discover_all_fields(ocr_boxes)
        
        # Build structured output
        extracted = {
            'metadata': {
                'total_boxes': len(ocr_boxes),
                'discovery_confidence': discovery['confidence'],
                'field_coverage': discovery['field_coverage']
            },
            'invoice_number': self._pick_best(discovery['discovered_fields']['invoice_numbers']),
            'date': self._pick_best_date(discovery['discovered_fields']['dates']),
            'total_amount': self._find_total(discovery['discovered_fields']['amounts']),
            'subtotal': self._find_subtotal(discovery['discovered_fields']['amounts']),
            'tax': self._find_tax(discovery['discovered_fields']['amounts']),
            'vendor_name': discovery['discovered_fields']['vendor_names'][0] if discovery['discovered_fields']['vendor_names'] else None,
            'email': discovery['discovered_fields']['emails'][0] if discovery['discovered_fields']['emails'] else None,
            'phone': discovery['discovered_fields']['phones'][0] if discovery['discovered_fields']['phones'] else None,
            'gstin': discovery['discovered_fields']['gstins'][0] if discovery['discovered_fields']['gstins'] else None,
            'website': discovery['discovered_fields']['websites'][0] if discovery['discovered_fields']['websites'] else None,
            'line_items': discovery['discovered_fields']['line_items'],
            'all_amounts': discovery['discovered_fields']['amounts'],
            'present_fields': discovery['present_fields'],
        }
        
        # Run validation on what we found
        extracted['validation'] = self._validate_extraction(extracted)
        
        return extracted
    
    def _pick_best(self, items: List[Dict]) -> Optional[str]:
        """Pick the best item from a list"""
        if not items:
            return None
        # Return the first one (usually the most prominent)
        return items[0].get('value') if isinstance(items[0], dict) else items[0]
    
    def _pick_best_date(self, dates: List[Dict]) -> Optional[str]:
        """Pick the best date (prefer parsed over raw)"""
        if not dates:
            return None
        # Prefer dates that were successfully parsed
        parsed_dates = [d for d in dates if d.get('parsed')]
        if parsed_dates:
            return parsed_dates[0].get('parsed')
        return dates[0].get('value')
    
    def _find_total(self, amounts: List[Dict]) -> Optional[Dict]:
        """Find the total amount (usually largest, labeled 'total')"""
        if not amounts:
            return None
        
        # First try to find explicitly labeled 'total'
        for amount in amounts:
            if amount.get('likely_label') == 'total':
                return amount
        
        # Fall back to largest amount
        return amounts[0] if amounts else None
    
    def _find_subtotal(self, amounts: List[Dict]) -> Optional[Dict]:
        """Find subtotal amount"""
        if not amounts:
            return None
        for amount in amounts:
            if amount.get('likely_label') == 'subtotal':
                return amount
        # Try second largest amount
        return amounts[1] if len(amounts) > 1 else None
    
    def _find_tax(self, amounts: List[Dict]) -> Optional[Dict]:
        """Find tax amount"""
        if not amounts:
            return None
        for amount in amounts:
            if amount.get('likely_label') == 'tax':
                return amount
        return None
    
    def _validate_extraction(self, extracted: Dict) -> List[Dict]:
        """Validate what we extracted"""
        warnings = []
        
        amounts = extracted.get('all_amounts', [])
        if not amounts:
            warnings.append({
                'type': 'no_amounts_found',
                'severity': 'critical',
                'message': 'No monetary amounts detected in the invoice'
            })
        
        total = extracted.get('total_amount')
        if total:
            total_amt = total.get('amount', 0)
            
            # Check if total > sum of line items
            line_items = extracted.get('line_items', [])
            if line_items:
                line_sum = sum(item.get('amount', 0) for item in line_items)
                if abs(line_sum - total_amt) > 0.01:
                    warnings.append({
                        'type': 'mathematical_inconsistency',
                        'severity': 'high',
                        'message': f'Sum of line items (${line_sum:.2f}) ≠ total (${total_amt:.2f})',
                        'expected': line_sum,
                        'found': total_amt
                    })
            
            # Check if total matches subtotal + tax
            subtotal = extracted.get('subtotal')
            tax = extracted.get('tax')
            if subtotal and tax:
                calc_total = subtotal.get('amount', 0) + tax.get('amount', 0)
                if abs(calc_total - total_amt) > 0.01:
                    warnings.append({
                        'type': 'mathematical_inconsistency',
                        'severity': 'high',
                        'message': f'subtotal + tax (${calc_total:.2f}) ≠ total (${total_amt:.2f})',
                        'expected': calc_total,
                        'found': total_amt
                    })
        
        return warnings


def extract_smart(ocr_boxes: List[Dict]) -> Dict[str, Any]:
    """Quick smart extraction function"""
    engine = SmartExtractionEngine()
    return engine.extract_invoice(ocr_boxes)
