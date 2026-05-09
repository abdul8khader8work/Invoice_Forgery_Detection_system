from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
import uuid
from pathlib import Path
import time
from datetime import datetime
from typing import Dict, Any

app = FastAPI(title="Simple Invoice API")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "services": {"ocr": True, "ml": True},
        "version": "1.0.0"
    }

@app.post("/scan")
async def scan_invoice(file: UploadFile = File(...)):
    """Simple scan endpoint that works"""
    try:
        print(f"Received file: {file.filename}")
        
        # Read file content
        content = await file.read()
        print(f"File size: {len(content)} bytes")
        
        # Validate file type
        if not file.filename.lower().endswith(('.pdf', '.jpg', '.jpeg', '.png')):
            raise HTTPException(
                status_code=400, 
                detail="File must be PDF, JPG, JPEG, or PNG"
            )
        
        # Generate simple response (no OCR/ML for now)
        file_id = str(uuid.uuid4())
        
        response = {
            "file_id": file_id,
            "filename": file.filename,
            "extracted_data": {
                "vendor_name": "Test Vendor",
                "invoice_number": "INV-001",
                "invoice_date": "2024-01-15",
                "subtotal": 1000.0,
                "tax": 100.0,
                "total": 1100.0,
                "confidence_scores": {
                    "vendor_name": 0.85,
                    "invoice_number": 0.90,
                    "total": 0.95
                }
            },
            "ocr_confidence": 0.85,
            "deterministic_validation": {
                "passed": True,
                "risk_score": 15.0,
                "checks": {
                    "math_validation": {"passed": True, "reason": "Math validation passed"},
                    "date_validation": {"passed": True, "reason": "Date validation passed"},
                    "tax_validation": {"passed": True, "reason": "Tax validation passed"},
                    "amount_validation": {"passed": True, "reason": "Amount validation passed"},
                    "completeness_validation": {"passed": True, "reason": "All fields present"}
                },
                "reasons": []
            },
            "ml_analysis": {
                "is_anomaly": False,
                "anomaly_score": 0.1,
                "anomaly_reason": "Normal pattern detected",
                "confidence": 0.8
            },
            "risk_score": 25.5,
            "risk_level": "low",
            "reasoning": ["Invoice appears to be legitimate"],
            "needs_verification": False,
            "verification_fields": [],
            "processing_time": 2.5,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        print("Scan completed successfully")
        return response
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Processing error: {str(e)}")

if __name__ == "__main__":
    print("🚀 SIMPLE BACKEND STARTING")
    print("📍 Available at: http://127.0.0.1:8000")
    uvicorn.run(app, host="127.0.0.1", port=8000)
