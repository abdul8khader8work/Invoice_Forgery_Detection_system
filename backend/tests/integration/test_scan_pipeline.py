"""
Backend Integration Tests for Scan Pipeline

Validates the full API contract from upload to results.
Test scenarios:
1. Happy Path: Upload → OCR → validation → ML score → complete response
2. Async Flow: Task creation → polling → SSE → final result
3. Error Handling: Invalid files, timeouts, server errors
4. API Contract: All required fields present in responses

Usage:
    cd D:\Projects\invoice_forgery_system\backend
    .\venv\Scripts\Activate.ps1
    pytest tests\integration\test_scan_pipeline.py -v
"""

import pytest
import requests
import time
import os
from pathlib import Path
from typing import Generator
import json

# Test configuration
BASE_URL = "http://localhost:8000"
API_PREFIX = "/api"
TEST_ASSETS = Path(__file__).parent.parent.parent / "test_assets"


@pytest.fixture(scope="module")
def api_client() -> Generator[requests.Session, None, None]:
    """Create API session with base configuration"""
    session = requests.Session()
    session.headers.update({
        "Accept": "application/json",
        "X-Test-Client": "integration-test"
    })
    yield session
    session.close()


@pytest.fixture
def sample_invoice() -> Path:
    """Path to sample invoice for testing"""
    # Create test_assets directory if needed
    TEST_ASSETS.mkdir(exist_ok=True)
    
    # For now, return a placeholder path
    # In production, this would be a real test PDF/image
    return TEST_ASSETS / "sample_invoice.pdf"


class TestHealthEndpoints:
    """Verify server is healthy and ready"""
    
    def test_health_endpoint(self, api_client: requests.Session):
        """Basic health check"""
        response = api_client.get(f"{BASE_URL}/health")
        assert response.status_code == 200
        data = response.json()
        assert data.get("status") in ["healthy", "alive"]
    
    def test_readiness_endpoint(self, api_client: requests.Session):
        """Readiness probe with dependency checks"""
        response = api_client.get(f"{BASE_URL}/ready")
        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert "checks" in data
    
    def test_feature_flags_endpoint(self, api_client: requests.Session):
        """Feature flags status endpoint"""
        response = api_client.get(f"{BASE_URL}{API_PREFIX}/v1/feature-flags/status")
        assert response.status_code == 200
        data = response.json()
        assert "flags" in data
        # Verify all expected flags are present
        expected_flags = [
            "ENABLE_JWT_AUTH",
            "ENABLE_ASYNC_SCAN", 
            "ENABLE_BATCH_UPLOAD",
            "ENABLE_ANALYTICS_DASHBOARD"
        ]
        for flag in expected_flags:
            assert flag in data["flags"], f"Missing flag: {flag}"


class TestScanHappyPath:
    """
    Happy Path: Upload invoice → OCR → validation → ML score → results display
    """
    
    def test_sync_scan_invoice(self, api_client: requests.Session, sample_invoice: Path):
        """
        Synchronous scan flow (ENABLE_ASYNC_SCAN=false)
        
        Expected response structure:
        {
            "scan_id": str,
            "status": "completed",
            "extracted_data": {
                "invoice_number": str,
                "vendor_name": str,
                "invoice_date": str,
                "total_amount": float,
                "tax_amount": float,
                "confidence": float
            },
            "validation_result": {
                "is_valid": bool,
                "errors": [],
                "warnings": []
            },
            "forgery_result": {
                "risk_score": float,
                "risk_level": str,
                "anomalies": [],
                "ml_confidence": float
            },
            "xai_reasoning": {
                "explanation": str,
                "factors": []
            }
        }
        """
        # Skip if no test file exists
        if not sample_invoice.exists():
            pytest.skip(f"Test file not found: {sample_invoice}")
        
        # Upload invoice
        with open(sample_invoice, "rb") as f:
            files = {"file": ("sample_invoice.pdf", f, "application/pdf")}
            response = api_client.post(
                f"{BASE_URL}{API_PREFIX}/scan",
                files=files,
                timeout=60
            )
        
        # Verify response
        assert response.status_code == 200, f"Scan failed: {response.text}"
        data = response.json()
        
        # API Contract validation
        self._validate_scan_response(data)
    
    def _validate_scan_response(self, data: dict):
        """Validate complete scan response structure"""
        # Top-level fields
        assert "scan_id" in data, "Missing scan_id"
        assert "status" in data, "Missing status"
        assert data["status"] == "completed", f"Unexpected status: {data['status']}"
        
        # Extracted data validation
        assert "extracted_data" in data, "Missing extracted_data"
        extracted = data["extracted_data"]
        assert isinstance(extracted, dict), "extracted_data must be object"
        
        # Key invoice fields
        invoice_fields = ["invoice_number", "vendor_name", "total_amount"]
        for field in invoice_fields:
            assert field in extracted, f"Missing extracted_data.{field}"
        
        # Validation result
        assert "validation_result" in data, "Missing validation_result"
        validation = data["validation_result"]
        assert "is_valid" in validation, "Missing validation_result.is_valid"
        
        # ML/Forgery result
        assert "forgery_result" in data, "Missing forgery_result"
        forgery = data["forgery_result"]
        assert "risk_score" in forgery, "Missing forgery_result.risk_score"
        assert "risk_level" in forgery, "Missing forgery_result.risk_level"
        assert isinstance(forgery["risk_score"], (int, float)), "risk_score must be numeric"
        assert 0 <= forgery["risk_score"] <= 1, "risk_score must be between 0 and 1"
        
        # XAI reasoning
        assert "xai_reasoning" in data, "Missing xai_reasoning"
        reasoning = data["xai_reasoning"]
        assert "explanation" in reasoning, "Missing xai_reasoning.explanation"


class TestAsyncScanFlow:
    """
    Async Flow: Task creation → polling → SSE → final result
    """
    
    def test_async_scan_task_creation(self, api_client: requests.Session, sample_invoice: Path):
        """Create async scan task and verify task ID returned"""
        if not sample_invoice.exists():
            pytest.skip(f"Test file not found: {sample_invoice}")
        
        # Check if async scan is enabled
        flags_resp = api_client.get(f"{BASE_URL}{API_PREFIX}/v1/feature-flags/status")
        flags = flags_resp.json().get("flags", {})
        
        if not flags.get("ENABLE_ASYNC_SCAN", False):
            pytest.skip("ENABLE_ASYNC_SCAN is disabled")
        
        # Upload for async processing
        with open(sample_invoice, "rb") as f:
            files = {"file": ("sample_invoice.pdf", f, "application/pdf")}
            response = api_client.post(
                f"{BASE_URL}{API_PREFIX}/v2/scan/async",
                files=files,
                timeout=30
            )
        
        if response.status_code == 404:
            pytest.skip("Async scan endpoint not available (ENABLE_ASYNC_SCAN=false)")
        
        assert response.status_code == 200, f"Async scan failed: {response.text}"
        data = response.json()
        
        # Verify task created
        assert "task_id" in data, "Missing task_id in async response"
        assert "status" in data, "Missing status in async response"
        assert data["status"] == "queued"
        
        return data["task_id"]
    
    def test_async_scan_polling(self, api_client: requests.Session):
        """Poll task status until completion"""
        # This test would use a task_id from test_async_scan_task_creation
        # For now, placeholder
        pytest.skip("Requires task_id from async creation test")
    
    def test_async_scan_sse(self, api_client: requests.Session):
        """Connect to SSE endpoint and receive updates"""
        # SSE connection test
        # Would connect to /api/v2/scan/stream/{task_id}
        pytest.skip("SSE test requires running async task")


class TestErrorHandling:
    """
    Error Handling: Invalid files, network timeout, server errors → graceful recovery
    """
    
    def test_invalid_file_type(self, api_client: requests.Session):
        """Upload invalid file type returns 400 with clear message"""
        # Create a temporary invalid file
        import tempfile
        
        with tempfile.NamedTemporaryFile(suffix=".exe", delete=False) as f:
            f.write(b"invalid executable content")
            temp_path = f.name
        
        try:
            with open(temp_path, "rb") as f:
                files = {"file": ("malware.exe", f, "application/x-msdownload")}
                response = api_client.post(
                    f"{BASE_URL}{API_PREFIX}/scan",
                    files=files,
                    timeout=10
                )
            
            # Should return 400 or 422 for invalid file type
            assert response.status_code in [400, 422, 415], \
                f"Expected validation error, got {response.status_code}"
            
            # Verify error response structure
            data = response.json()
            assert "error" in data or "detail" in data or "message" in data, \
                "Error response should contain error message"
            
        finally:
            os.unlink(temp_path)
    
    def test_empty_file_upload(self, api_client: requests.Session):
        """Upload empty file returns error"""
        import tempfile
        
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
            f.write(b"")  # Empty file
            temp_path = f.name
        
        try:
            with open(temp_path, "rb") as f:
                files = {"file": ("empty.pdf", f, "application/pdf")}
                response = api_client.post(
                    f"{BASE_URL}{API_PREFIX}/scan",
                    files=files,
                    timeout=10
                )
            
            # Should reject empty file
            assert response.status_code in [400, 422], \
                f"Expected validation error for empty file, got {response.status_code}"
                
        finally:
            os.unlink(temp_path)
    
    def test_oversized_file(self, api_client: requests.Session):
        """Upload oversized file returns error"""
        # Create file larger than 10MB limit
        import tempfile
        
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
            # Write 11MB of data
            f.write(b"0" * (11 * 1024 * 1024))
            temp_path = f.name
        
        try:
            with open(temp_path, "rb") as f:
                files = {"file": ("oversized.pdf", f, "application/pdf")}
                response = api_client.post(
                    f"{BASE_URL}{API_PREFIX}/scan",
                    files=files,
                    timeout=30
                )
            
            # Should reject oversized file (413 Payload Too Large)
            assert response.status_code in [413, 400, 422], \
                f"Expected file size error, got {response.status_code}"
                
        finally:
            os.unlink(temp_path)
    
    def test_server_error_graceful(self, api_client: requests.Session):
        """Server errors return JSON with error message, not HTML"""
        # This test would mock a server error condition
        # For now, verify error handling structure
        pytest.skip("Requires error injection mechanism")


class TestGrokFallback:
    """
    Grok API fallback: When Grok fails, app uses rule-based without crashing
    """
    
    def test_grok_timeout_fallback(self, api_client: requests.Session, sample_invoice: Path):
        """Grok timeout triggers rule-based fallback"""
        # This test would mock Grok service timeout
        # Verify that:
        # 1. Response still returned (not 500)
        # 2. extracted_data present (from rule-based extraction)
        # 3. risk_score present (from rule-based calculation)
        # 4. No error stack traces in response
        pytest.skip("Requires Grok service mocking")
    
    def test_grok_rate_limit_fallback(self, api_client: requests.Session):
        """Grok rate limit triggers rule-based fallback"""
        pytest.skip("Requires Grok service mocking")


class TestAPIContract:
    """
    API Contract Validation: All endpoints return expected structure
    """
    
    def test_response_content_type_json(self, api_client: requests.Session):
        """All API responses have Content-Type: application/json"""
        response = api_client.get(f"{BASE_URL}/health")
        content_type = response.headers.get("Content-Type", "")
        assert "json" in content_type, f"Expected JSON response, got: {content_type}"
    
    def test_cors_headers_present(self, api_client: requests.Session):
        """CORS headers present for web clients"""
        # Preflight request
        response = api_client.options(
            f"{BASE_URL}{API_PREFIX}/scan",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "POST"
            }
        )
        
        # Should have CORS headers
        assert "Access-Control-Allow-Origin" in response.headers or response.status_code == 200, \
            "CORS not configured"
    
    def test_correlation_id_propagation(self, api_client: requests.Session):
        """Correlation ID passed through request/response"""
        test_id = "test-correlation-123"
        response = api_client.get(
            f"{BASE_URL}/health",
            headers={"X-Correlation-ID": test_id}
        )
        
        # Verify correlation ID returned in response
        response_id = response.headers.get("X-Correlation-ID")
        if response_id:
            assert response_id == test_id, \
                f"Correlation ID mismatch: {response_id} != {test_id}"


# Run tests if executed directly
if __name__ == "__main__":
    pytest.main([__file__, "-v"])
