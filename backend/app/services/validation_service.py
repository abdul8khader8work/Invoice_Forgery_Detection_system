from typing import Dict, Any, List, Optional
from datetime import datetime, timedelta
from dateutil.parser import parse as parse_date
import re

class ValidationService:
    """
    Deterministic Engine - Math checks, date validation, duplicate detection
    """
    
    def __init__(self):
        self.processed_invoices = []  # In production, this would be a database
        self.tax_rates = {
            'standard': 0.18,  # 18% standard tax
            'reduced': 0.12,   # 12% reduced tax
            'zero': 0.0        # 0% tax
        }
    
    def _parse_amount(self, value: Any) -> Optional[float]:
        """Parse amount from string or numeric value"""
        if value is None:
            return None
        if isinstance(value, (int, float)):
            return float(value)
        try:
            # Remove currency symbols, commas, and spaces
            cleaned = re.sub(r'[$€£¥,\s]', '', str(value))
            return float(cleaned)
        except (ValueError, TypeError):
            return None
    
    def validate_deterministic(self, extracted_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Perform deterministic validation on extracted invoice data
        """
        validation_results = {
            'passed': True,
            'risk_score': 0.0,
            'checks': {},
            'reasons': []
        }
        
        # 1. Math Validation
        math_result = self._validate_math(extracted_data)
        validation_results['checks']['math_validation'] = math_result
        if not math_result['passed']:
            validation_results['passed'] = False
            validation_results['risk_score'] += 30.0
            validation_results['reasons'].append(math_result['reason'])
        
        # 2. Date Validation
        date_result = self._validate_date(extracted_data)
        validation_results['checks']['date_validation'] = date_result
        if not date_result['passed']:
            validation_results['passed'] = False
            validation_results['risk_score'] += 20.0
            validation_results['reasons'].append(date_result['reason'])
        
        # 3. Tax Rate Validation
        tax_result = self._validate_tax_rate(extracted_data)
        validation_results['checks']['tax_validation'] = tax_result
        if not tax_result['passed']:
            validation_results['passed'] = False
            validation_results['risk_score'] += 25.0
            validation_results['reasons'].append(tax_result['reason'])
        
        # 4. Amount Validation
        amount_result = self._validate_amounts(extracted_data)
        validation_results['checks']['amount_validation'] = amount_result
        if not amount_result['passed']:
            validation_results['passed'] = False
            validation_results['risk_score'] += 15.0
            validation_results['reasons'].append(amount_result['reason'])
        
        # 5. Completeness Validation
        completeness_result = self._validate_completeness(extracted_data)
        validation_results['checks']['completeness_validation'] = completeness_result
        if not completeness_result['passed']:
            validation_results['passed'] = False
            validation_results['risk_score'] += 10.0
            validation_results['reasons'].append(completeness_result['reason'])
        
        return validation_results
    
    def calculate_validation_score(self, invoice_data: dict, validation_results: dict) -> int:
        """
        Calculate overall validation score (0-100).
        Combines math validation, date validation, field completeness, and ML analysis.
        """
        score = 0
        weights = {
            'math': 40,
            'date': 20,
            'fields': 20,
            'ml': 20,
        }
        
        # Math validation (40 points)
        math_score = validation_results.get('checks', {}).get('math_validation', {}).get('score', 0)
        score += (math_score / 100) * weights['math']
        
        # Date validation (20 points)
        date_result = validation_results.get('checks', {}).get('date_validation', {})
        if date_result.get('passed', False):
            score += weights['date']  # Full points for valid date
        else:
            # Partial points for minor date issues
            score += weights['date'] * 0.3
        
        # Field completeness (20 points)
        required_fields = ['vendor_name', 'invoice_number', 'invoice_date', 'total']
        optional_fields = ['line_items', 'tax', 'payment_method', 'vendor_address']
        
        fields_present = sum(1 for f in required_fields if invoice_data.get(f))
        score += (fields_present / len(required_fields)) * weights['fields']
        
        # Bonus points for optional fields
        optional_present = sum(1 for f in optional_fields if invoice_data.get(f))
        score += (optional_present / len(optional_fields)) * 5  # Up to 5 bonus points
        
        # ML anomaly score (20 points) - lower anomaly = higher score
        # This will be populated by the ML service
        ml_score = validation_results.get('ml_analysis', {}).get('anomaly_score', 0)
        if ml_score > 0:
            score += (1 - ml_score / 100) * weights['ml']
        else:
            score += weights['ml'] * 0.8  # Default 80% if no ML analysis
        
        return int(min(100, max(0, score)))
    
    def _validate_math(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate mathematical consistency of invoice amounts including line items
        """
        findings = []
        score = 100
        tolerance = 1.0  # Allow ±1.0 for rounding differences
        
        # Parse amounts to handle string values like "$1,234.56"
        subtotal = self._parse_amount(data.get('subtotal'))
        tax = self._parse_amount(data.get('tax')) or 0.0
        total = self._parse_amount(data.get('total'))
        line_items = data.get('line_items', [])
        
        # Check 1: Line item calculations (Qty × Unit Price = Amount)
        if line_items:
            for item in line_items:
                try:
                    quantity = float(item.get('quantity', 0))
                    unit_price = float(item.get('unit_price', 0))
                    amount = float(item.get('amount', 0))
                    expected_amount = quantity * unit_price
                    
                    if abs(expected_amount - amount) > tolerance:
                        findings.append({
                            'type': 'line_item_mismatch',
                            'item': item.get('description', 'Unknown'),
                            'expected': expected_amount,
                            'actual': amount,
                            'difference': abs(expected_amount - amount)
                        })
                        score -= 10
                except (ValueError, TypeError):
                    findings.append({
                        'type': 'line_item_invalid_data',
                        'item': item.get('description', 'Unknown'),
                        'error': 'Invalid numeric values'
                    })
                    score -= 5
        
        # Check 2: Sum of line items = Subtotal
        if line_items and subtotal is not None:
            calculated_subtotal = 0.0
            for item in line_items:
                try:
                    calculated_subtotal += float(item.get('amount', 0))
                except (ValueError, TypeError):
                    continue
            
            if abs(calculated_subtotal - subtotal) > tolerance:
                findings.append({
                    'type': 'subtotal_mismatch',
                    'calculated': calculated_subtotal,
                    'stated': subtotal,
                    'difference': abs(calculated_subtotal - subtotal)
                })
                score -= 15
        
        # Check 3: Subtotal + Tax = Total
        if subtotal is not None and total is not None:
            expected_total = subtotal + tax
            if abs(expected_total - total) > tolerance:
                findings.append({
                    'type': 'total_mismatch',
                    'expected': expected_total,
                    'actual': total,
                    'difference': abs(expected_total - total)
                })
                score -= 15
        
        # Check 4: Tax calculation validation (if tax rate can be inferred)
        if subtotal is not None and tax > 0:
            tax_rate = tax / subtotal
            # Check if tax rate matches common rates (5%, 12%, 18%, 28%)
            common_rates = [0.05, 0.12, 0.18, 0.28]
            closest_rate = min(common_rates, key=lambda x: abs(x - tax_rate))
            
            if abs(tax_rate - closest_rate) > 0.02:  # 2% tolerance
                findings.append({
                    'type': 'tax_rate_unusual',
                    'calculated_rate': tax_rate * 100,
                    'closest_standard_rate': closest_rate * 100,
                    'difference': abs(tax_rate - closest_rate) * 100
                })
                score -= 5
        
        # Determine if validation passed
        passed = score >= 80 and len(findings) == 0
        
        return {
            'passed': passed,
            'reason': 'Math validation passed' if passed else f'Math validation failed: {len(findings)} issues found',
            'confidence': 0.9 if passed else 0.7,
            'score': max(0, score),
            'findings': findings,
            'details': {
                'subtotal': subtotal,
                'tax': tax,
                'total': total,
                'line_items_count': len(line_items),
                'issues_found': len(findings)
            }
        }
    
    def _validate_date(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate invoice date (no future dates, reasonable date range)
        """
        invoice_date_str = data.get('invoice_date')
        
        if not invoice_date_str:
            return {
                'passed': False,
                'reason': 'Invoice date not found',
                'confidence': 0.0
            }
        
        try:
            invoice_date = parse_date(invoice_date_str)
            current_date = datetime.now()
            
            # Check if date is in future
            if invoice_date > current_date + timedelta(days=7):
                days_future = (invoice_date - current_date).days
                return {
                    'passed': False,
                    'reason': f'Invoice date is {days_future} days in the future',
                    'confidence': 0.9,
                    'details': {
                        'invoice_date': invoice_date_str,
                        'current_date': current_date.isoformat(),
                        'days_future': days_future
                    }
                }
            
            # Check if date is too old (more than 5 years)
            if invoice_date < current_date - timedelta(days=5*365):
                years_old = (current_date - invoice_date).days / 365
                return {
                    'passed': False,
                    'reason': f'Invoice date is {years_old:.1f} years old',
                    'confidence': 0.7,
                    'details': {
                        'invoice_date': invoice_date_str,
                        'current_date': current_date.isoformat(),
                        'years_old': years_old
                    }
                }
            
            return {
                'passed': True,
                'reason': 'Date validation passed',
                'confidence': 0.8,
                'details': {
                    'invoice_date': invoice_date_str,
                    'days_old': (current_date - invoice_date).days
                }
            }
            
        except Exception as e:
            return {
                'passed': False,
                'reason': f'Invalid date format: {str(e)}',
                'confidence': 0.0
            }
    
    def _check_duplicates(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Check for duplicate invoices
        """
        invoice_number = data.get('invoice_number')
        vendor_name = data.get('vendor_name')
        total = data.get('total')
        
        if not invoice_number:
            return {
                'passed': True,  # Can't check without invoice number
                'reason': 'Cannot check duplicates without invoice number',
                'confidence': 0.5
            }
        
        # Check against processed invoices (simplified - in production use database)
        for invoice in self.processed_invoices:
            if (invoice.get('invoice_number') == invoice_number or
                (invoice.get('vendor_name') == vendor_name and 
                 invoice.get('total') == total)):
                return {
                    'passed': False,
                    'reason': f'Duplicate invoice detected: {invoice_number}',
                    'confidence': 0.95,
                    'details': {
                        'duplicate_invoice': invoice,
                        'match_type': 'invoice_number' if invoice.get('invoice_number') == invoice_number else 'vendor_amount'
                    }
                }
        
        # Add to processed invoices
        self.processed_invoices.append(data)
        
        return {
            'passed': True,
            'reason': 'No duplicate found',
            'confidence': 0.8
        }
    
    def _validate_formats(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate data formats
        """
        issues = []
        
        # Validate invoice number format
        invoice_number = data.get('invoice_number')
        if invoice_number and not re.match(r'^[A-Za-z0-9\-]+$', invoice_number):
            issues.append('Invoice number contains invalid characters')
        
        # Validate amounts are positive numbers
        for field in ['subtotal', 'tax', 'total']:
            amount = data.get(field)
            if amount is not None:
                if not isinstance(amount, (int, float)) or amount < 0:
                    issues.append(f'{field} is not a valid positive amount')
        
        # Validate vendor name
        vendor_name = data.get('vendor_name')
        if vendor_name and (len(vendor_name) < 2 or not re.search(r'[A-Za-z]', vendor_name)):
            issues.append('Vendor name appears invalid')
        
        if issues:
            return {
                'passed': False,
                'reason': f'Format validation issues: {", ".join(issues)}',
                'confidence': 0.7,
                'details': {'issues': issues}
            }
        else:
            return {
                'passed': True,
                'reason': 'All formats are valid',
                'confidence': 0.8
            }
    
    def _validate_logical_rules(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate logical business rules
        """
        issues = []
        
        subtotal = data.get('subtotal')
        tax = data.get('tax')
        total = data.get('total')
        
        # Rule 1: Total should be greater than or equal to subtotal
        if subtotal is not None and total is not None:
            if total < subtotal:
                issues.append('Total amount is less than subtotal')
        
        # Rule 2: Tax should be reasonable percentage of subtotal
        if subtotal is not None and tax is not None and subtotal > 0:
            tax_percentage = (tax / subtotal) * 100
            if tax_percentage > 30:  # Unusually high tax rate
                issues.append(f'Tax rate is unusually high: {tax_percentage:.1f}%')
            elif tax_percentage < 0:  # Negative tax
                issues.append('Tax amount is negative')
        
        # Rule 3: Subtotal should be positive
        if subtotal is not None and subtotal <= 0:
            issues.append('Subtotal should be positive')
        
        # Rule 4: Invoice number should be present
        if not data.get('invoice_number'):
            issues.append('Invoice number is missing')
        
        # Rule 5: Vendor name should be present
        if not data.get('vendor_name'):
            issues.append('Vendor name is missing')
        
        if issues:
            return {
                'passed': False,
                'reason': f'Logical validation issues: {", ".join(issues)}',
                'confidence': 0.8,
                'details': {'issues': issues}
            }
        else:
            return {
                'passed': True,
                'reason': 'All logical rules passed',
                'confidence': 0.9
            }
    
    def _validate_tax_rate(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate tax rate based on product category.
        """
        # Parse amounts to handle string values like "$1,234.56"
        subtotal = self._parse_amount(data.get('subtotal'))
        tax = self._parse_amount(data.get('tax'))
        total = self._parse_amount(data.get('total'))
        tax_rate = data.get('tax_rate')
        
        if subtotal is None or tax is None:
            return {
                'passed': True,  # Can't validate without data
                'reason': 'Cannot validate tax rate - missing subtotal or tax',
                'confidence': 0.5
            }
        
        if subtotal <= 0:
            return {
                'passed': False,
                'reason': 'Cannot calculate tax rate with zero or negative subtotal',
                'confidence': 0.3
            }
        
        # Calculate actual tax rate
        actual_tax_rate = tax / subtotal
        tax_percentage = actual_tax_rate * 100
        
        # Detect category from line items
        line_items = data.get('line_items', [])
        descriptions = ' '.join(item.get('description', '').lower() for item in line_items)
        
        # Expected rates by category
        if 'gas' in descriptions or 'cylinder' in descriptions or 'lpg' in descriptions:
            expected_rate = 5.0  # LPG gas
            category = 'LPG Gas'
        elif 'food' in descriptions:
            expected_rate = 5.0  # Basic food
            category = 'Food'
        elif 'medicine' in descriptions or 'pharma' in descriptions:
            expected_rate = 12.0  # Medicines
            category = 'Pharmaceuticals'
        else:
            expected_rate = 18.0  # General
            category = 'General'
        
        # Allow ±1% tolerance
        tolerance = 1.0
        is_valid = abs(actual_tax_rate - expected_rate) <= tolerance
        
        if tax_percentage == 0:
            return {
                'passed': True,
                'reason': 'No tax applied',
                'confidence': 0.7,
                'details': {
                    'tax_rate': actual_tax_rate,
                    'tax_percentage': tax_percentage,
                    'category': category
                }
            }
        
        if is_valid:
            return {
                'passed': True,
                'reason': f'{tax_percentage:.2f}% tax rate is correct for {category}',
                'confidence': 0.9,
                'details': {
                    'tax_rate': actual_tax_rate,
                    'tax_percentage': tax_percentage,
                    'expected_rate': expected_rate,
                    'category': category
                }
            }
        else:
            return {
                'passed': True,  # Non-standard but not necessarily wrong
                'reason': f'{tax_percentage:.2f}% tax rate is unusual for {category} (expected ~{expected_rate}%)',
                'confidence': 0.6,
                'details': {
                    'tax_rate': actual_tax_rate,
                    'tax_percentage': tax_percentage,
                    'expected_rate': expected_rate,
                    'category': category,
                    'difference': abs(actual_tax_rate - expected_rate)
                }
            }
    
    def _validate_amounts(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate amount fields for suspicious values
        """
        # Parse amounts to handle string values like "$1,234.56"
        subtotal = self._parse_amount(data.get('subtotal'))
        tax = self._parse_amount(data.get('tax'))
        total = self._parse_amount(data.get('total'))
        
        result = {
            'passed': True,
            'reason': 'Amount validation passed',
            'confidence': 1.0
        }
        
        # Check for zero amounts
        if total == 0:
            result['passed'] = False
            result['reason'] = 'Total amount is zero - suspicious'
            result['confidence'] = 0.3
            return result
        
        # Check for negative amounts
        if subtotal is not None and subtotal < 0:
            result['passed'] = False
            result['reason'] = 'Subtotal is negative - invalid'
            result['confidence'] = 0.2
            return result
        
        if tax is not None and tax < 0:
            result['passed'] = False
            result['reason'] = 'Tax amount is negative - invalid'
            result['confidence'] = 0.2
            return result
        
        if total is not None and total < 0:
            result['passed'] = False
            result['reason'] = 'Total amount is negative - invalid'
            result['confidence'] = 0.2
            return result
        
        # Check for unusually large amounts
        if total and total > 1000000:  # $1 million
            result['passed'] = False
            result['reason'] = f'Total amount ${total:,.2f} is unusually large'
            result['confidence'] = 0.4
        
        return result
    
    def _validate_completeness(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate that critical fields are present
        """
        critical_fields = ['vendor_name', 'total']
        missing_fields = []
        
        for field in critical_fields:
            if not data.get(field):
                missing_fields.append(field)
        
        result = {
            'passed': len(missing_fields) == 0,
            'reason': '',
            'confidence': 1.0
        }
        
        if missing_fields:
            field_names = ', '.join(missing_fields)
            result['reason'] = f'Missing critical fields: {field_names}'
            result['confidence'] = 0.5
        else:
            result['reason'] = 'All critical fields present'
        
        return result
