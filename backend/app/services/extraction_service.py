import re
from typing import Dict, Any, List, Optional
import numpy as np
from datetime import datetime
from app.utils.date_parser import parse_invoice_date, validate_date_range

class ExtractionService:
    """
    Anchor Extraction Service - Uses regex and keyword proximity to identify invoice fields
    """
    
    def __init__(self):
        # Define anchor keywords for each field
        self.anchors = {
            'vendor_name': [
                r'(?i)(?:bill\s*to|sold\s*to|vendor|company|name|from)[:\s]*([A-Za-z0-9\s&.,\-]+)',
                r'(?i)(?:invoice\s*from|supplier|provider)[:\s]*([A-Za-z0-9\s&.,\-]+)',
            ],
            'invoice_number': [
                r'(?i)(?:invoice\s*#|invoice\s*no|invoice\s*number|bill\s*#)[:\s]*([A-Za-z0-9\-]+)',
                r'(?i)(?:receipt\s*#|order\s*#|reference)[:\s]*([A-Za-z0-9\-]+)',
            ],
            'invoice_date': [
                r'(?i)(?:invoice\s*date|date|dated)[:\s]*([0-9]{1,2}[\/\-\.][0-9]{1,2}[\/\-\.][0-9]{2,4})',
                r'(?i)(?:date\s*:|date)[:\s]*([0-9]{1,2}[\/\-\.][0-9]{1,2}[\/\-\.][0-9]{2,4})',
            ],
            'subtotal': [
                r'(?i)(?:subtotal|sub\s*total|net\s*amount|amount)[:\s]*\$?([0-9,]+\.?[0-9]*)',
                r'(?i)(?:before\s*tax|excl\.?\s*tax)[:\s]*\$?([0-9,]+\.?[0-9]*)',
            ],
            'tax': [
                r'(?i)(?:tax|vat|gst|sales\s*tax)[:\s]*\$?([0-9,]+\.?[0-9]*)',
                r'(?i)(?:tax\s*amount|taxable)[:\s]*\$?([0-9,]+\.?[0-9]*)',
            ],
            'total': [
                r'(?i)(?:total|grand\s*total|amount\s*due|balance\s*due)[:\s]*\$?([0-9,]+\.?[0-9]*)',
                r'(?i)(?:total\s*amount|final\s*amount)[:\s]*\$?([0-9,]+\.?[0-9]*)',
            ]
        }
        
        # Currency patterns
        self.currency_pattern = r'[$€£¥]\s*([0-9,]+\.?[0-9]*)'
        self.amount_pattern = r'([0-9,]+\.?[0-9]*)'
    
    def extract_invoice_data(self, ocr_result: Dict[str, Any]) -> Dict[str, Any]:
        """
        Extract structured invoice data using anchor extraction
        """
        text = ocr_result.get('text', '')
        confidence_scores = {}
        
        extracted_data = {
            'vendor_name': None,
            'invoice_number': None,
            'invoice_date': None,
            'subtotal': None,
            'tax': None,
            'total': None,
            'confidence_scores': {}
        }
        
        # 1. Extract Vendor Name
        vendor_result = self._extract_vendor_name(text)
        extracted_data['vendor_name'] = vendor_result['value']
        confidence_scores['vendor_name'] = vendor_result['confidence']
        
        # 2. Extract Invoice Number
        invoice_result = self._extract_invoice_number(text)
        extracted_data['invoice_number'] = invoice_result['value']
        confidence_scores['invoice_number'] = invoice_result['confidence']
        
        # 3. Extract Date
        date_result = self._extract_date(text)
        extracted_data['invoice_date'] = date_result['value']
        confidence_scores['invoice_date'] = date_result['confidence']
        
        # 4. Extract Amounts
        amounts_result = self._extract_amounts(text)
        extracted_data.update(amounts_result['values'])
        confidence_scores.update(amounts_result['confidence_scores'])
        
        # 5. Extract Line Items
        line_items_result = self._extract_line_items(text, ocr_result.get('boxes', []))
        extracted_data['line_items'] = line_items_result['values']
        confidence_scores['line_items'] = line_items_result['confidence']
        
        # 6. Extract Payment Method
        payment_result = self._extract_payment_method(text)
        extracted_data['payment_method'] = payment_result['value']
        confidence_scores['payment_method'] = payment_result['confidence']
        
        # 7. Extract Vendor Contact
        contact_result = self._extract_vendor_contact(text)
        extracted_data['vendor_address'] = contact_result['address']
        extracted_data['vendor_phone'] = contact_result['phone']
        confidence_scores['vendor_address'] = contact_result['address_confidence']
        confidence_scores['vendor_phone'] = contact_result['phone_confidence']
        
        extracted_data['confidence_scores'] = confidence_scores
        
        return extracted_data
    
    def _extract_field(self, text: str, patterns: List[str], field_name: str, bounding_boxes: List[Dict]) -> Dict[str, Any]:
        """
        Extract a specific field using multiple patterns
        """
        best_match = None
        best_confidence = 0.0
        
        for pattern in patterns:
            matches = re.finditer(pattern, text)
            
            for match in matches:
                if match.groups():
                    value = match.group(1).strip()
                    confidence = self._calculate_confidence(value, field_name, match, bounding_boxes)
                    
                    if confidence > best_confidence:
                        best_confidence = confidence
                        best_match = {
                            'value': self._clean_value(value, field_name),
                            'pattern': pattern,
                            'position': match.span(),
                            'confidence': confidence
                        }
        
        if best_match:
            return best_match
        else:
            return {'value': None, 'confidence': 0.0}
    
    def _calculate_confidence(self, value: str, field_name: str, match, bounding_boxes: List[Dict]) -> float:
        """
        Calculate confidence score for extracted value
        """
        confidence = 0.5  # Base confidence
        
        # Length and format validation
        if field_name == 'invoice_number':
            if re.match(r'^[A-Za-z0-9\-]+$', value) and len(value) >= 3:
                confidence += 0.3
        elif field_name in ['subtotal', 'tax', 'total']:
            if re.match(r'^[0-9,]+\.?[0-9]*$', value):
                confidence += 0.3
        elif field_name == 'vendor_name':
            if len(value) >= 2 and any(c.isalpha() for c in value):
                confidence += 0.3
        elif field_name == 'invoice_date':
            try:
                parse_invoice_date(value)
                confidence += 0.4
            except:
                pass
        
        # Context validation - check if near relevant keywords
        context_words = self._get_context_words(field_name)
        text_segment = self._get_text_segment(match, bounding_boxes)
        
        if any(word.lower() in text_segment.lower() for word in context_words):
            confidence += 0.2
        
        return min(confidence, 1.0)
    
    def _get_context_words(self, field_name: str) -> List[str]:
        """Get context words for field validation"""
        context_map = {
            'vendor_name': ['invoice', 'bill', 'company', 'vendor'],
            'invoice_number': ['invoice', 'number', 'receipt', 'order'],
            'invoice_date': ['date', 'invoice', 'due'],
            'subtotal': ['subtotal', 'total', 'amount', 'tax'],
            'tax': ['tax', 'vat', 'gst', 'amount'],
            'total': ['total', 'amount', 'due', 'balance']
        }
        return context_map.get(field_name, [])
    
    def _get_text_segment(self, match, bounding_boxes: List[Dict]) -> str:
        """Get text segment around the match"""
        # Simplified version - in production, would use actual bounding box positions
        return ""
    
    def _clean_value(self, value: str, field_name: str) -> Any:
        """Clean and type-convert extracted value"""
        if field_name in ['subtotal', 'tax', 'total']:
            # Remove currency symbols and commas, convert to float
            clean_amount = re.sub(r'[$,]', '', value)
            try:
                return float(clean_amount)
            except ValueError:
                return None
        elif field_name == 'invoice_date':
            try:
                parsed = parse_invoice_date(value)
                return parsed.isoformat() if parsed else value
            except:
                return value
        else:
            return value
    
    def _post_process_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Post-process extracted data for consistency and validation
        """
        # Calculate missing tax if subtotal and total are present
        if data.get('subtotal') and data.get('total') and not data.get('tax'):
            calculated_tax = data['total'] - data['subtotal']
            if calculated_tax > 0:
                data['tax'] = calculated_tax
                data['confidence_scores']['tax'] = 0.6  # Lower confidence for calculated values
        
        # Validate date
        if data.get('invoice_date'):
            try:
                parsed_date = parse_invoice_date(data['invoice_date'])
                data['invoice_date'] = parsed_date.isoformat() if parsed_date else None
                if not parsed_date:
                    data['confidence_scores']['invoice_date'] = 0.0
            except:
                data['invoice_date'] = None
                data['confidence_scores']['invoice_date'] = 0.0
        
        # Validate amounts are positive
        for field in ['subtotal', 'tax', 'total']:
            if data.get(field) is not None and data[field] < 0:
                data[field] = abs(data[field])
        
        return data
    
    def _extract_vendor_name(self, text: str) -> Dict[str, Any]:
        """Extract vendor name using anchor patterns"""
        patterns = self.anchors['vendor_name']
        return self._extract_field(text, patterns, 'vendor_name', [])
    
    def _extract_invoice_number(self, text: str) -> Dict[str, Any]:
        """Extract invoice number using anchor patterns"""
        patterns = self.anchors['invoice_number']
        return self._extract_field(text, patterns, 'invoice_number', [])
    
    def _extract_date(self, text: str) -> Dict[str, Any]:
        """Extract invoice date using anchor patterns and new parser"""
        patterns = self.anchors['invoice_date']
        result = self._extract_field(text, patterns, 'invoice_date', [])
        
        # Parse the extracted date using the new parser
        if result['value']:
            parsed_date = parse_invoice_date(result['value'])
            if parsed_date:
                # Validate the date range
                validation = validate_date_range(parsed_date)
                result['value'] = parsed_date.isoformat()
                result['date_validation'] = validation
                result['confidence'] = result['confidence'] * (0.8 if validation['valid'] else 0.5)
            else:
                # If parsing failed, try to extract date directly from text
                lines = text.split('\n')
                for line in lines:
                    date_match = re.search(r'(\d{1,2}[-/]\d{1,2}[-/]\d{4}|\d{4}[-/]\d{1,2}[-/]\d{1,2})', line)
                    if date_match:
                        parsed_date = parse_invoice_date(date_match.group(1))
                        if parsed_date:
                            validation = validate_date_range(parsed_date)
                            result['value'] = parsed_date.isoformat()
                            result['date_validation'] = validation
                            result['confidence'] = 0.7
                            break
        
        return result
    
    def _extract_line_items(self, text: str, bounding_boxes: List[Dict]) -> Dict[str, Any]:
        """
        Extract line items from invoice using table detection.
        Looks for patterns: # DESCRIPTION QTY PRICE AMOUNT
        """
        line_items = []
        
        # Pattern 1: Numbered list items (1. Item Name 2. Item Name)
        item_pattern = r'(\d+)\.\s+([A-Za-z0-9\s]+)\s+(\d+\.?\d*)\s*(Kgs|Pcs|Pkt|g|kg)?\s+(\d+\.?\d*)\s+(\d+\.?\d*)'
        
        # Pattern 2: Table rows (detect by consistent spacing)
        # Implement row detection based on y-coordinate clustering
        
        for match in re.finditer(item_pattern, text):
            try:
                line_items.append({
                    'item_number': match.group(1),
                    'description': match.group(2).strip(),
                    'quantity': float(match.group(3)),
                    'unit': match.group(4) or 'Pcs',
                    'unit_price': float(match.group(5)),
                    'amount': float(match.group(6)),
                })
            except (ValueError, IndexError):
                continue
        
        # Fallback: Try to extract from table-like structure
        if not line_items:
            # Look for lines with multiple numbers (indicating table rows)
            lines = text.split('\n')
            for i, line in enumerate(lines):
                # Pattern for table rows: description qty unit price amount
                table_pattern = r'([A-Za-z0-9\s]+)\s+(\d+\.?\d*)\s*(Kgs|Pcs|Pkt|g|kg)?\s+(\d+\.?\d*)\s+(\d+\.?\d*)'
                match = re.search(table_pattern, line)
                if match:
                    try:
                        line_items.append({
                            'item_number': str(len(line_items) + 1),
                            'description': match.group(1).strip(),
                            'quantity': float(match.group(2)),
                            'unit': match.group(3) or 'Pcs',
                            'unit_price': float(match.group(4)),
                            'amount': float(match.group(5)),
                        })
                    except (ValueError, IndexError):
                        continue
        
        confidence = 0.8 if line_items else 0.0
        return {
            'values': line_items,
            'confidence': confidence
        }
    
    def _extract_payment_method(self, text: str) -> Dict[str, Any]:
        """Extract payment method (UPI, Cash, Card, etc.)"""
        payment_patterns = [
            r'Payment\s+By\s+(\w+)',
            r'Paid\s+By\s+(\w+)',
            r'Payment\s+Mode[:\s]+(\w+)',
            r'Mode\s+of\s+Payment[:\s]+(\w+)',
            r'Payment\s*[:\s]+([A-Za-z\s]+)',
            r'Paid\s+([A-Za-z\s]+)',
            r'Advance\s*\([^)]+\)\s*[:\s]+([\d\.]+)',  # Detect advance payment
        ]
        
        for pattern in payment_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                value = match.group(1).strip()
                # Handle advance payment case
                if 'advance' in pattern.lower() and value.replace('.', '').isdigit():
                    return {
                        'value': 'Paid Online',
                        'confidence': 0.9
                    }
                return {
                    'value': value.title(),
                    'confidence': 0.9
                }
        
        return {
            'value': None,
            'confidence': 0.0
        }
    
    def _extract_vendor_contact(self, text: str) -> Dict[str, Any]:
        """Extract vendor address and phone"""
        # Look for address patterns (H.NO, Road, City, PIN)
        address_patterns = [
            r'(?:ADDRESS|ADDR)[:\s]+([^\n]+(?:\n[^\n]+)*?)(?:PIN|PHONE|TEL|GSTIN|Office)',
            r'(\d+-\d+/[^\n]+,[^\n]+,[^\n]+(?:\n[^\n]+)*?PIN[:\s]?\d{6})',
            r'([A-Z0-9\s/-]+,?\s+[A-Z\s]+,?\s+[A-Z\s]+,?\s+[A-Z\s]+-\d{6})',
        ]
        
        phone_patterns = [
            r'(?:TEL|PHONE|PH|MOBILE|CONTACT)[:\s]+([\d,\s\-+]+)',
            r'(\d{4}[-\s]?\d{6,8})',
            r'(\+91[-\s]?\d{10})',
            r'(\d{10})',
        ]
        
        address = None
        for pattern in address_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                address = match.group(1).strip()
                address = ' '.join(address.split())
                if len(address) > 20:
                    break
        
        phones = []
        for pattern in phone_patterns:
            matches = re.findall(pattern, text)
            for match in matches:
                phone = match.strip()
                if len(phone) >= 10 and len(phone) <= 15:
                    phones.append(phone)
        
        phone = None
        if phones:
            unique_phones = list(dict.fromkeys(phones))[:3]
            phone = ', '.join(unique_phones)
        
        return {
            'address': address,
            'phone': phone,
            'address_confidence': 0.8 if address else 0.0,
            'phone_confidence': 0.8 if phone else 0.0
        }
    
    def _extract_amounts(self, text: str) -> Dict[str, Any]:
        """Extract all monetary amounts from text"""
        values = {
            'subtotal': None,
            'tax': None,
            'total': None
        }
        confidence_scores = {}
        
        # Extract each amount field
        for field in ['subtotal', 'tax', 'total']:
            patterns = self.anchors[field]
            result = self._extract_field(text, patterns, field, [])
            values[field] = result['value']
            confidence_scores[field] = result['confidence']
        
        return {
            'values': values,
            'confidence_scores': confidence_scores
        }
