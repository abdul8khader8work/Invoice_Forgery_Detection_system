import pytest
from app.services.extraction_service import ExtractionService
from app.services.validation_service import ValidationService
from app.utils.date_parser import parse_invoice_date, validate_date_range
from app.schemas.invoice import LineItem
from datetime import datetime

class TestEnhancedExtraction:
    """Test enhanced extraction functionality"""
    
    def setup_method(self):
        """Setup test fixtures"""
        self.extraction_service = ExtractionService()
        self.validation_service = ValidationService()
    
    def test_line_item_extraction(self):
        """Test line item extraction from sample invoice"""
        ocr_text = """
        1. Kashmiri Walnut 0.1 Kgs 1600.00 160
        2. Open Item 1 Pcs 100.00 100.00
        3. Asli Ghee 500g 1 Pkt 280.00 280.00
        4. Special Product 2.5 Kgs 50.00 125.00
        """
        
        result = self.extraction_service._extract_line_items(ocr_text, [])
        
        assert len(result['values']) == 4
        assert result['confidence'] == 0.8
        
        # Check first line item
        item1 = result['values'][0]
        assert item1['item_number'] == '1'
        assert item1['description'] == 'Kashmiri Walnut'
        assert item1['quantity'] == 0.1
        assert item1['unit'] == 'Kgs'
        assert item1['unit_price'] == 1600.00
        assert item1['amount'] == 160
    
    def test_line_item_extraction_table_format(self):
        """Test line item extraction from table-like structure"""
        ocr_text = """
        Kashmiri Walnut 0.1 Kgs 1600.00 160
        Open Item 1 Pcs 100.00 100.00
        Asli Ghee 500g 1 Pkt 280.00 280.00
        """
        
        result = self.extraction_service._extract_line_items(ocr_text, [])
        
        assert len(result['values']) == 3
        assert result['confidence'] == 0.8
        
        # Check first line item
        item1 = result['values'][0]
        assert item1['description'] == 'Kashmiri Walnut'
        assert item1['quantity'] == 0.1
        assert item1['amount'] == 160
    
    def test_payment_method_extraction(self):
        """Test payment method extraction"""
        test_cases = [
            ("Payment By UPI", "UPI"),
            ("Paid By Cash", "CASH"),
            ("Payment Mode: Card", "CARD"),
            ("Mode of Payment: NEFT", "NEFT"),
        ]
        
        for text, expected in test_cases:
            result = self.extraction_service._extract_payment_method(text)
            assert result['value'] == expected
            assert result['confidence'] == 0.9
    
    def test_vendor_contact_extraction(self):
        """Test vendor address and phone extraction"""
        text = """
        H.NO 123, MAIN ROAD, BANGALORE PIN:560001
        TEL: +91-80-12345678
        """
        
        result = self.extraction_service._extract_vendor_contact(text)
        
        assert result['address'] is not None
        assert 'H.NO 123' in result['address']
        assert '560001' in result['address']
        assert result['phone'] == '+91-80-12345678'
        assert result['address_confidence'] == 0.8
        assert result['phone_confidence'] == 0.8

class TestDateParser:
    """Test multi-format date parsing"""
    
    def test_date_parsing_formats(self):
        """Test various date formats"""
        test_cases = [
            ("05-Mar-2026", datetime(2026, 3, 5)),
            ("05-Mar-2026 09:20:06 PM", datetime(2026, 3, 5, 21, 20, 6)),
            ("05/03/2026", datetime(2026, 3, 5)),
            ("2026-03-05", datetime(2026, 3, 5)),
            ("05-03-2026", datetime(2026, 3, 5)),
            ("Mar 05, 2026", datetime(2026, 3, 5)),
            ("05 Mar 2026", datetime(2026, 3, 5)),
        ]
        
        for date_str, expected in test_cases:
            result = parse_invoice_date(date_str)
            assert result == expected
    
    def test_date_validation(self):
        """Test date range validation"""
        from datetime import datetime, timedelta
        
        # Test valid past date
        past_date = datetime.now() - timedelta(days=30)
        result = validate_date_range(past_date)
        assert result['valid'] is True
        assert result['warning'] is None
        assert result['days_in_past'] == 30
        
        # Test future date
        future_date = datetime.now() + timedelta(days=5)
        result = validate_date_range(future_date)
        assert result['valid'] is True
        assert '5 days in the future' in result['warning']
        assert result['days_in_future'] == 5

class TestMathValidation:
    """Test enhanced math validation"""
    
    def setup_method(self):
        """Setup test fixtures"""
        self.validation_service = ValidationService()
    
    def test_line_item_math_validation(self):
        """Test line item calculation validation"""
        invoice = {
            'line_items': [
                {'quantity': 2, 'unit_price': 100, 'amount': 200},
                {'quantity': 1, 'unit_price': 50, 'amount': 50},
                {'quantity': 0.5, 'unit_price': 40, 'amount': 20},
            ],
            'subtotal': 270,
            'tax': 0,
            'total': 270,
        }
        
        result = self.validation_service._validate_math(invoice)
        
        assert result['passed'] is True
        assert result['score'] == 100
        assert len(result['findings']) == 0
    
    def test_line_item_mismatch_detection(self):
        """Test detection of line item calculation mismatches"""
        invoice = {
            'line_items': [
                {'quantity': 2, 'unit_price': 100, 'amount': 190},  # Wrong: should be 200
                {'quantity': 1, 'unit_price': 50, 'amount': 50},
            ],
            'subtotal': 240,  # Wrong: should be 250
            'tax': 0,
            'total': 240,
        }
        
        result = self.validation_service._validate_math(invoice)
        
        assert result['passed'] is False
        assert result['score'] < 100
        
        # Check for specific findings
        finding_types = [f['type'] for f in result['findings']]
        assert 'line_item_mismatch' in finding_types
        assert 'subtotal_mismatch' in finding_types
    
    def test_tax_rate_validation(self):
        """Test tax rate validation"""
        invoice = {
            'line_items': [],
            'subtotal': 100,
            'tax': 18,  # 18% tax
            'total': 118,
        }
        
        result = self.validation_service._validate_math(invoice)
        
        assert result['passed'] is True
        
        # Test unusual tax rate
        invoice['tax'] = 25  # 25% tax (unusual)
        result = self.validation_service._validate_math(invoice)
        
        # Should still pass but with finding about unusual tax rate
        finding_types = [f['type'] for f in result['findings']]
        assert 'tax_rate_unusual' in finding_types

class TestValidationScore:
    """Test comprehensive validation score calculation"""
    
    def setup_method(self):
        """Setup test fixtures"""
        self.validation_service = ValidationService()
    
    def test_perfect_validation_score(self):
        """Test perfect validation score calculation"""
        invoice_data = {
            'vendor_name': 'Test Vendor',
            'invoice_number': 'INV-001',
            'invoice_date': '2026-03-05',
            'total': 100.0,
            'line_items': [{'description': 'Test', 'quantity': 1, 'unit_price': 100, 'amount': 100}],
            'tax': 0,
            'payment_method': 'UPI',
            'vendor_address': 'Test Address',
        }
        
        validation_results = {
            'checks': {
                'math_validation': {'score': 100, 'passed': True},
                'date_validation': {'passed': True},
            },
            'ml_analysis': {'anomaly_score': 10.0},  # Low anomaly
        }
        
        score = self.validation_service.calculate_validation_score(invoice_data, validation_results)
        
        assert score >= 90  # Should be very high
    
    def test_low_validation_score(self):
        """Test low validation score calculation"""
        invoice_data = {
            'vendor_name': 'Test Vendor',
            # Missing other required fields
            'total': 100.0,
        }
        
        validation_results = {
            'checks': {
                'math_validation': {'score': 50, 'passed': False},
                'date_validation': {'passed': False},
            },
            'ml_analysis': {'anomaly_score': 80.0},  # High anomaly
        }
        
        score = self.validation_service.calculate_validation_score(invoice_data, validation_results)
        
        assert score < 50  # Should be low

class TestLineItemSchema:
    """Test LineItem schema validation"""
    
    def test_line_item_creation(self):
        """Test LineItem model creation"""
        line_item = LineItem(
            item_number='1',
            description='Test Product',
            quantity=2.5,
            unit='Kgs',
            unit_price=100.0,
            amount=250.0
        )
        
        assert line_item.item_number == '1'
        assert line_item.description == 'Test Product'
        assert line_item.quantity == 2.5
        assert line_item.unit == 'Kgs'
        assert line_item.unit_price == 100.0
        assert line_item.amount == 250.0
    
    def test_line_item_serialization(self):
        """Test LineItem JSON serialization"""
        line_item = LineItem(
            item_number='1',
            description='Test Product',
            quantity=2.5,
            unit='Kgs',
            unit_price=100.0,
            amount=250.0
        )
        
        data = line_item.dict()
        assert data['item_number'] == '1'
        assert data['description'] == 'Test Product'
        assert data['quantity'] == 2.5

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
