import requests
import json
import io
import time
from pathlib import Path

def test_api_001_health_check():
    """API-001: Health Check"""
    print("🧪 Testing API-001: Health Check")
    try:
        response = requests.get('http://127.0.0.1:8000/health')
        print(f"Status: {response.status_code}")
        data = response.json()
        
        assert response.status_code == 200
        assert data['status'] == 'healthy'
        assert 'timestamp' in data
        assert 'services' in data
        assert 'version' in data
        
        print("✅ API-001 PASSED")
        return True
    except Exception as e:
        print(f"❌ API-001 FAILED: {e}")
        return False

def test_api_002_valid_pdf():
    """API-002: File Upload - Valid PDF"""
    print("\n🧪 Testing API-002: File Upload - Valid PDF")
    try:
        # Create a simple PDF-like file
        pdf_content = b"%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n/Pages 2 0 R\n>>\nendobj\n"
        
        files = {'file': ('test.pdf', io.BytesIO(pdf_content), 'application/pdf')}
        response = requests.post('http://127.0.0.1:8000/scan', files=files)
        
        print(f"Status: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            assert 'file_id' in data
            assert 'extracted_data' in data
            assert 'risk_score' in data
            assert 'risk_level' in data
            print("✅ API-002 PASSED")
            return True
        else:
            print(f"Expected 200, got {response.status_code}")
            print(f"Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ API-002 FAILED: {e}")
        return False

def test_api_003_invalid_format():
    """API-003: File Upload - Invalid Format"""
    print("\n🧪 Testing API-003: File Upload - Invalid Format")
    try:
        txt_content = b"This is a text file, not a PDF"
        
        files = {'file': ('test.txt', io.BytesIO(txt_content), 'text/plain')}
        response = requests.post('http://127.0.0.1:8000/scan', files=files)
        
        print(f"Status: {response.status_code}")
        
        assert response.status_code == 400
        data = response.json()
        assert 'File must be PDF, JPG, JPEG, or PNG' in data['detail']
        
        print("✅ API-003 PASSED")
        return True
    except Exception as e:
        print(f"❌ API-003 FAILED: {e}")
        return False

def test_api_004_empty_file():
    """API-004: File Upload - Empty File"""
    print("\n🧪 Testing API-004: File Upload - Empty File")
    try:
        empty_content = b""
        
        files = {'file': ('empty.pdf', io.BytesIO(empty_content), 'application/pdf')}
        response = requests.post('http://127.0.0.1:8000/scan', files=files)
        
        print(f"Status: {response.status_code}")
        
        assert response.status_code == 400
        data = response.json()
        assert 'File is empty' in data['detail']
        
        print("✅ API-004 PASSED")
        return True
    except Exception as e:
        print(f"❌ API-004 FAILED: {e}")
        return False

def test_api_005_large_file():
    """API-005: File Upload - Large File"""
    print("\n🧪 Testing API-005: File Upload - Large File")
    try:
        # Create a file larger than 10MB (max_file_size)
        large_content = b"X" * (11 * 1024 * 1024)  # 11MB
        
        files = {'file': ('large.pdf', io.BytesIO(large_content), 'application/pdf')}
        response = requests.post('http://127.0.0.1:8000/scan', files=files)
        
        print(f"Status: {response.status_code}")
        
        assert response.status_code == 400
        data = response.json()
        assert 'exceeds maximum allowed size' in data['detail']
        
        print("✅ API-005 PASSED")
        return True
    except Exception as e:
        print(f"❌ API-005 FAILED: {e}")
        return False

def test_api_006_verify_valid():
    """API-006: Verify Invoice - Valid Data"""
    print("\n🧪 Testing API-006: Verify Invoice - Valid Data")
    try:
        verify_data = {
            "vendor_name": "Test Corp",
            "invoice_number": "INV-001",
            "total": 100.0
        }
        
        response = requests.post(
            'http://127.0.0.1:8000/verify/test-file-id-12345',
            json=verify_data
        )
        
        print(f"Status: {response.status_code}")
        
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'verified'
        assert data['file_id'] == 'test-file-id-12345'
        
        print("✅ API-006 PASSED")
        return True
    except Exception as e:
        print(f"❌ API-006 FAILED: {e}")
        return False

def test_api_007_verify_invalid():
    """API-007: Verify Invoice - Invalid ID"""
    print("\n🧪 Testing API-007: Verify Invoice - Invalid ID")
    try:
        verify_data = {"vendor_name": "Test Corp"}
        
        response = requests.post(
            'http://127.0.0.1:8000/verify/invalid',
            json=verify_data
        )
        
        print(f"Status: {response.status_code}")
        
        assert response.status_code == 404
        data = response.json()
        assert 'not found' in data['detail']
        
        print("✅ API-007 PASSED")
        return True
    except Exception as e:
        print(f"❌ API-007 FAILED: {e}")
        return False

def test_api_008_get_invoices():
    """API-008: Get Invoices - No Filter"""
    print("\n🧪 Testing API-008: Get Invoices - No Filter")
    try:
        response = requests.get('http://127.0.0.1:8000/invoices')
        
        print(f"Status: {response.status_code}")
        
        assert response.status_code == 200
        data = response.json()
        assert 'invoices' in data
        assert 'total' in data
        assert isinstance(data['invoices'], list)
        
        print("✅ API-008 PASSED")
        return True
    except Exception as e:
        print(f"❌ API-008 FAILED: {e}")
        return False

def test_api_009_get_invoices_filtered():
    """API-009: Get Invoices - With Filter"""
    print("\n🧪 Testing API-009: Get Invoices - With Filter")
    try:
        response = requests.get('http://127.0.0.1:8000/invoices?risk_level=high')
        
        print(f"Status: {response.status_code}")
        
        assert response.status_code == 200
        data = response.json()
        assert 'invoices' in data
        assert data['risk_level'] == 'high'
        
        # All returned invoices should have high risk level
        for invoice in data['invoices']:
            assert invoice['risk_level'] == 'high'
        
        print("✅ API-009 PASSED")
        return True
    except Exception as e:
        print(f"❌ API-009 FAILED: {e}")
        return False

def run_all_tests():
    """Run all API tests"""
    print("🚀 Starting Backend API Test Suite")
    print("=" * 50)
    
    tests = [
        test_api_001_health_check,
        test_api_002_valid_pdf,
        test_api_003_invalid_format,
        test_api_004_empty_file,
        test_api_005_large_file,
        test_api_006_verify_valid,
        test_api_007_verify_invalid,
        test_api_008_get_invoices,
        test_api_009_get_invoices_filtered,
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        if test():
            passed += 1
        time.sleep(0.5)  # Small delay between tests
    
    print("\n" + "=" * 50)
    print(f"📊 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All API tests PASSED!")
    else:
        print(f"⚠️ {total - passed} tests failed")
    
    return passed == total

if __name__ == "__main__":
    run_all_tests()
    input("\nPress Enter to continue...")
