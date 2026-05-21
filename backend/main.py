# Fix: Monkey-patch for PIL/Pillow 10.0+ compatibility BEFORE importing EasyOCR
# EasyOCR uses Image.ANTIALIAS which was removed in Pillow 10.0+
try:
    from PIL import Image
    if not hasattr(Image, 'ANTIALIAS'):
        if hasattr(Image, 'Resampling'):
            Image.ANTIALIAS = Image.Resampling.LANCZOS
        else:
            Image.ANTIALIAS = Image.LANCZOS
except ImportError:
    pass

# Load environment variables from .env file
from dotenv import load_dotenv
load_dotenv()

# In-memory scan status tracking for async scans
_scan_status = {}

def extract_text_from_pdf_fitz(pdf_path: str) -> str:
    """Extract text from PDF using PyMuPDF (fitz) - handles both text and scanned PDFs"""
    try:
        import fitz  # PyMuPDF
        doc = fitz.open(pdf_path)
        
        # First try to extract text directly
        text = ""
        for page in doc:
            text += page.get_text()
        doc.close()
        
        # If no text found, it's likely a scanned PDF - render as image and OCR
        if len(text.strip()) < 50:
            print(f"Only {len(text.strip())} chars found - using OCR for better extraction...")
            doc = fitz.open(pdf_path)
            text = ""
            
            # Only OCR first page for speed (most invoices are 1 page)
            max_pages = min(len(doc), 1)
            for page_num in range(max_pages):
                page = doc[page_num]
                # Render page as image - full DPI for accuracy
                pix = page.get_pixmap(dpi=300)
                img_data = pix.tobytes("png")
                
                # Save temporary image
                temp_path = pdf_path.replace('.pdf', f'_temp_page_{page_num}.png')
                with open(temp_path, 'wb') as f:
                    f.write(img_data)
                
                # Run OCR on the image
                try:
                    import easyocr
                    reader = easyocr.Reader(['en'], gpu=False, verbose=False)
                    results = reader.readtext(temp_path)
                    page_text = ' '.join([result[1] for result in results])
                    text += page_text + "\n"
                    print(f"OCR extracted {len(page_text)} characters from page {page_num + 1}")
                except Exception as e:
                    print(f"OCR failed for page {page_num + 1}: {e}")
                
                # Clean up temp image
                try:
                    import os
                    os.remove(temp_path)
                except:
                    pass
            
            doc.close()
        
        return text.strip()
    except ImportError:
        print("PyMuPDF not installed. Installing...")
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pymupdf"])
        import fitz
        doc = fitz.open(pdf_path)
        text = ""
        for page in doc:
            text += page.get_text()
        doc.close()
        return text.strip()
    except Exception as e:
        raise Exception(f"PDF text extraction failed: {e}")

from fastapi import FastAPI, File, UploadFile, HTTPException, BackgroundTasks, Depends, Form, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn
import os
import sys
import uuid
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
import json
import time
import groq

from app.core.config import settings
from app.core.feature_flags import feature_flags, feature_flag_validator
from app.models.database import get_db, Invoice, AuditLog
from app.services.ocr_service import OCRService
from app.services.extraction_service import ExtractionService
from app.services.extraction_processor import ExtractionProcessor, get_extraction_processor
from app.services.validation_service import ValidationService
from app.services.ml_service import MLService
from app.services.detection_service import ForgeryDetectionService, get_forgery_detection_service
from app.services.xai_reasoning_engine import XAIReasoningEngine, get_xai_reasoning_engine
from app.services.groq_service import GroqService
from app.api.smart_ingestion import router as smart_ingestion_router
from app.api.active_learning_routes import router as active_learning_router
from app.api.batch_reports import router as batch_reports_router
from app.api.analytics_routes import router as analytics_router
from app.api import auth_routes
from app.schemas.invoice import InvoiceScanRequest, InvoiceResponse, ValidationResult

app = FastAPI(
    title="Invoice Forgery Detection API",
    description="Production-ready Invoice Forgery Detection System",
    version="1.0.0"
)

# Configure CORS for all origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configure host binding for all interfaces
@app.on_event("startup")
async def startup_event():
    print("Invoice Forgery Detection API Starting...")
    print(f"Server will be available at:")
    print(f"   - http://127.0.0.1:8000")
    print(f"   - http://localhost:8000")
    print(f"   - http://0.0.0.0:8000")
    print("CORS enabled for all origins")
    print("Ready to accept connections from Flutter app")
    
    # Create database tables
    try:
        from app.models.database import create_tables
        create_tables()
        print("Database tables created/verified")
        
        # Create active learning tables
        from app.models.active_learning_models import Base as ALBase
        from app.models.database import engine
        ALBase.metadata.create_all(bind=engine)
        print("Active Learning tables created/verified")
    except Exception as e:
        print(f"Database initialization warning: {e}")
        print("   Continuing anyway - tables will be created on first save")

# Initialize services
ocr_service = OCRService()
extraction_service = ExtractionService()
validation_service = ValidationService()
ml_service = MLService()

# Create directories
UPLOAD_DIR = Path(settings.upload_dir)
UPLOAD_DIR.mkdir(exist_ok=True)

# Register routers
app.include_router(smart_ingestion_router)
app.include_router(active_learning_router)
app.include_router(batch_reports_router)
app.include_router(analytics_router)
app.include_router(auth_routes.router)

@app.get("/")
async def root():
    return {
        "message": "Invoice Forgery Detection API",
        "version": "1.0.0",
        "status": "running"
    }

@app.get("/health")
async def health_check():
    """Health check endpoint with service status and feature flags"""
    try:
        return {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "services": {
                "ocr": ocr_service.is_available() if hasattr(ocr_service, 'is_available') else True,
                "ml": ml_service.is_available() if hasattr(ml_service, 'is_available') else True
            },
            "version": "1.0.0",
            "uptime": "running",
            "feature_flags": {
                "ENABLE_JWT_AUTH": getattr(settings, 'enable_jwt_auth', False),
                "ENABLE_ASYNC_SCAN": getattr(settings, 'enable_async_scan', False),
                "ENABLE_DB_V2": getattr(settings, 'enable_db_v2', False),
                "ENABLE_SECURITY_HARDENING": getattr(settings, 'enable_security_hardening', False),
                "ENABLE_CELERY": getattr(settings, 'enable_celery', False),
                "ENABLE_AUTO_RETRAIN": getattr(settings, 'enable_auto_retrain', False),
                "ENABLE_PUSH_NOTIFICATIONS": getattr(settings, 'enable_push_notifications', False),
            }
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "timestamp": datetime.utcnow().isoformat(),
            "error": str(e),
            "services": {
                "ocr": False,
                "ml": False
            },
            "feature_flags": {
                "ENABLE_JWT_AUTH": False,
                "ENABLE_ASYNC_SCAN": False,
                "ENABLE_DB_V2": False,
                "ENABLE_SECURITY_HARDENING": False,
                "ENABLE_CELERY": False,
                "ENABLE_AUTO_RETRAIN": False,
                "ENABLE_PUSH_NOTIFICATIONS": False,
            }
        }

@app.get("/invoices")
async def get_invoices(skip: int = 0, limit: int = 10, db = Depends(get_db)):
    """Get list of recent invoices from database"""
    try:
        invoices = db.query(Invoice).order_by(Invoice.created_at.desc()).offset(skip).limit(limit).all()
        return {
            "success": True,
            "invoices": [
                {
                    "file_id": inv.file_id,
                    "filename": inv.filename,
                    "vendor_name": inv.vendor_name,
                    "invoice_number": inv.invoice_number,
                    "invoice_date": inv.invoice_date,
                    "total": inv.total,
                    "risk_score": inv.risk_score,
                    "risk_level": inv.risk_level,
                    "needs_verification": inv.needs_verification,
                    "verified": inv.verified,
                    "created_at": inv.created_at.isoformat() if inv.created_at else None,
                }
                for inv in invoices
            ]
        }
    except Exception as e:
        print(f"Error in /invoices endpoint: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "database_error", "message": str(e)}
        )

@app.get("/invoices/{invoice_id}")
async def get_invoice(invoice_id: str, db = Depends(get_db)):
    """Get single invoice by ID"""
    try:
        invoice = db.query(Invoice).filter(Invoice.file_id == invoice_id).first()
        if not invoice:
            raise HTTPException(
                status_code=404,
                detail={"success": False, "error": "not_found", "message": "Invoice not found"}
            )
        
        return {
            "success": True,
            "file_id": invoice.file_id,
            "filename": invoice.filename,
            "vendor_name": invoice.vendor_name,
            "invoice_number": invoice.invoice_number,
            "invoice_date": invoice.invoice_date,
            "subtotal": invoice.subtotal,
            "tax": invoice.tax,
            "total": invoice.total,
            "risk_score": invoice.risk_score,
            "risk_level": invoice.risk_level,
            "needs_verification": invoice.needs_verification,
            "verified": invoice.verified,
            "extracted_data": invoice.extracted_data,
            "validation_results": invoice.validation_results,
            "ml_results": invoice.ml_results,
            "reasoning": invoice.reasoning,
            "verification_fields": invoice.verification_fields,
            "processing_time": invoice.processing_time,
            "created_at": invoice.created_at.isoformat() if invoice.created_at else None,
            "updated_at": invoice.updated_at.isoformat() if invoice.updated_at else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "database_error", "message": str(e)}
        )

@app.put("/invoices/{file_id}/edit")
async def edit_invoice_data(file_id: str, data: dict, db = Depends(get_db)):
    """Edit invoice data in database"""
    try:
        invoice = db.query(Invoice).filter(Invoice.file_id == file_id).first()
        if not invoice:
            raise HTTPException(
                status_code=404,
                detail={"success": False, "error": "not_found", "message": "Invoice not found"}
            )
        
        # Update fields if provided
        if 'vendor_name' in data:
            invoice.vendor_name = data['vendor_name']
        if 'invoice_number' in data:
            invoice.invoice_number = data['invoice_number']
        if 'invoice_date' in data:
            invoice.invoice_date = data['invoice_date']
        if 'subtotal' in data:
            invoice.subtotal = float(data['subtotal'])
        if 'tax' in data:
            invoice.tax = float(data['tax'])
        if 'total' in data:
            invoice.total = float(data['total'])
        if 'extracted_data' in data:
            invoice.extracted_data = data['extracted_data']
        
        invoice.updated_at = datetime.utcnow()
        invoice.edited_by = data.get('edited_by', 'system')
        
        db.commit()
        db.refresh(invoice)
        
        # Create audit log
        audit_log = AuditLog(
            file_id=file_id,
            action='edit',
            details=f"Edited invoice data: {list(data.keys())}",
            user_id=invoice.edited_by
        )
        db.add(audit_log)
        db.commit()
        
        return {
            "success": True,
            "message": "Invoice updated successfully",
            "invoice": {
                "file_id": invoice.file_id,
                "vendor_name": invoice.vendor_name,
                "invoice_number": invoice.invoice_number,
                "edited_by": invoice.edited_by,
                "updated_at": invoice.updated_at.isoformat() if invoice.updated_at else None,
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "edit_failed", "message": str(e)}
        )

@app.put("/invoices/{file_id}/approve")
async def approve_invoice(file_id: str, approved_by: str = None, db = Depends(get_db)):
    """Approve invoice as verified"""
    try:
        invoice = db.query(Invoice).filter(Invoice.file_id == file_id).first()
        if not invoice:
            raise HTTPException(
                status_code=404,
                detail={"success": False, "error": "not_found", "message": "Invoice not found"}
            )
        
        invoice.verified = True
        invoice.needs_verification = False
        invoice.approved_by = approved_by or 'system'
        invoice.approved_at = datetime.utcnow()
        invoice.updated_at = datetime.utcnow()
        
        db.commit()
        db.refresh(invoice)
        
        # Create audit log
        audit_log = AuditLog(
            file_id=file_id,
            action='approve',
            details=f"Invoice approved by {invoice.approved_by}",
            user_id=invoice.approved_by
        )
        db.add(audit_log)
        db.commit()
        
        return {
            "success": True,
            "message": "Invoice approved successfully",
            "verified": invoice.verified,
            "approved_by": invoice.approved_by,
            "approved_at": invoice.approved_at.isoformat() if invoice.approved_at else None,
            "updated_at": invoice.updated_at.isoformat() if invoice.updated_at else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "approve_failed", "message": str(e)}
        )

@app.post("/verify/{invoice_id}")
async def verify_invoice(
    invoice_id: str,
    verified: bool = Body(...),
    notes: Optional[str] = Body(None),
    verified_by: Optional[str] = Body(None),
    db = Depends(get_db)
):
    """Verify invoice with notes"""
    try:
        invoice = db.query(Invoice).filter(Invoice.file_id == invoice_id).first()
        if not invoice:
            raise HTTPException(
                status_code=404,
                detail={"success": False, "error": "not_found", "message": "Invoice not found"}
            )
        
        invoice.verified = verified
        invoice.needs_verification = not verified
        invoice.verified_by = verified_by or 'system'
        invoice.verified_at = datetime.utcnow()
        invoice.verification_notes = notes
        invoice.updated_at = datetime.utcnow()
        
        db.commit()
        db.refresh(invoice)
        
        # Create audit log
        audit_log = AuditLog(
            file_id=invoice_id,
            action='verify',
            details=f"Verified: {verified}. Notes: {notes or 'None'}",
            user_id=invoice.verified_by
        )
        db.add(audit_log)
        db.commit()
        
        return {
            "success": True,
            "message": "Invoice verification recorded",
            "verified": invoice.verified,
            "verified_by": invoice.verified_by,
            "verified_at": invoice.verified_at.isoformat() if invoice.verified_at else None,
            "verification_notes": invoice.verification_notes,
            "updated_at": invoice.updated_at.isoformat() if invoice.updated_at else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "verify_failed", "message": str(e)}
        )

@app.get("/api/invoices/{invoice_id}/audit")
async def get_invoice_audit_history(invoice_id: str, db = Depends(get_db)):
    """Get audit history for invoice"""
    try:
        audit_logs = db.query(AuditLog).filter(AuditLog.file_id == invoice_id).order_by(AuditLog.created_at.desc()).all()
        
        return {
            "success": True,
            "audit_history": [
                {
                    "id": log.id,
                    "action": log.action,
                    "details": log.details,
                    "user_id": log.user_id,
                    "created_at": log.created_at.isoformat() if log.created_at else None,
                }
                for log in audit_logs
            ]
        }
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "audit_fetch_failed", "message": str(e)}
        )

@app.get("/invoices/{file_id}/report")
async def download_invoice_report(file_id: str, db = Depends(get_db)):
    """Download invoice report (JSON format)"""
    try:
        invoice = db.query(Invoice).filter(Invoice.file_id == file_id).first()
        if not invoice:
            raise HTTPException(
                status_code=404,
                detail={"success": False, "error": "not_found", "message": "Invoice not found"}
            )
        
        report = {
            "success": True,
            "report": {
                "file_id": invoice.file_id,
                "filename": invoice.filename,
                "generated_at": datetime.utcnow().isoformat(),
                "vendor_name": invoice.vendor_name,
                "invoice_number": invoice.invoice_number,
                "invoice_date": invoice.invoice_date,
                "subtotal": invoice.subtotal,
                "tax": invoice.tax,
                "total": invoice.total,
                "risk_score": invoice.risk_score,
                "risk_level": invoice.risk_level,
                "verified": invoice.verified,
                "extracted_data": invoice.extracted_data,
                "validation_results": invoice.validation_results,
                "ml_results": invoice.ml_results,
                "reasoning": invoice.reasoning,
            }
        }
        
        return report
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "report_generation_failed", "message": str(e)}
        )

@app.delete("/invoices/{file_id}")
async def delete_invoice(file_id: str, db = Depends(get_db)):
    """Delete an invoice from database"""
    try:
        invoice = db.query(Invoice).filter(Invoice.file_id == file_id).first()
        if not invoice:
            raise HTTPException(
                status_code=404,
                detail={"success": False, "error": "not_found", "message": "Invoice not found"}
            )
        
        db.delete(invoice)
        db.commit()
        return {"success": True, "message": "Invoice deleted successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "delete_failed", "message": str(e)}
        )

@app.get("/scan/status/{scan_id}")
async def get_scan_status(scan_id: str):
    """Get status of an async scan by scan_id"""
    if scan_id not in _scan_status:
        return {
            "success": False,
            "error": "not_found",
            "message": "Scan ID not found"
        }
    
    status = _scan_status[scan_id]
    return {
        "success": True,
        "scan_id": scan_id,
        "status": status.get("status", "unknown"),
        "progress": status.get("progress", 0),
        "result": status.get("result"),
        "error": status.get("error"),
        "updated_at": status.get("updated_at"),
    }

# In-memory share link storage (for demo purposes)
_share_links = {}

@app.post("/invoices/{file_id}/share")
async def share_invoice(file_id: str, db = Depends(get_db)):
    """Generate shareable link for invoice (expires in 24 hours)"""
    try:
        invoice = db.query(Invoice).filter(Invoice.file_id == file_id).first()
        if not invoice:
            raise HTTPException(
                status_code=404,
                detail={"success": False, "error": "not_found", "message": "Invoice not found"}
            )
        
        # Generate unique share token
        import secrets
        share_token = secrets.token_urlsafe(32)
        
        # Calculate expiry (24 hours from now)
        expiry_time = datetime.utcnow() + timedelta(hours=24)
        
        # Store share link
        _share_links[share_token] = {
            "file_id": file_id,
            "expires_at": expiry_time.isoformat(),
            "created_at": datetime.utcnow().isoformat()
        }
        
        # Generate share URL (using base URL from settings)
        base_url = settings.api_base_url.rstrip('/') if hasattr(settings, 'api_base_url') else "http://localhost:8000"
        share_url = f"{base_url}/shared/{share_token}"
        
        return {
            "success": True,
            "share_url": share_url,
            "share_token": share_token,
            "expires_at": expiry_time.isoformat(),
            "expires_in_hours": 24
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "share_failed", "message": str(e)}
        )

@app.get("/shared/{share_token}")
async def get_shared_invoice(share_token: str, db = Depends(get_db)):
    """Get invoice via share token"""
    try:
        # Check if share token exists and is not expired
        if share_token not in _share_links:
            raise HTTPException(
                status_code=404,
                detail={"success": False, "error": "invalid_token", "message": "Share link not found"}
            )
        
        share_data = _share_links[share_token]
        expiry = datetime.fromisoformat(share_data["expires_at"])
        
        if datetime.utcnow() > expiry:
            # Remove expired link
            del _share_links[share_token]
            raise HTTPException(
                status_code=410,
                detail={"success": False, "error": "expired", "message": "Share link has expired"}
            )
        
        # Get invoice
        file_id = share_data["file_id"]
        invoice = db.query(Invoice).filter(Invoice.file_id == file_id).first()
        if not invoice:
            raise HTTPException(
                status_code=404,
                detail={"success": False, "error": "not_found", "message": "Invoice not found"}
            )
        
        return {
            "success": True,
            "file_id": invoice.file_id,
            "filename": invoice.filename,
            "vendor_name": invoice.vendor_name,
            "invoice_number": invoice.invoice_number,
            "invoice_date": invoice.invoice_date,
            "total": invoice.total,
            "risk_score": invoice.risk_score,
            "risk_level": invoice.risk_level,
            "verified": invoice.verified,
            "extracted_data": invoice.extracted_data,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "fetch_failed", "message": str(e)}
        )

@app.post("/scan")
async def scan_invoice(
    file: UploadFile = File(...),
    db = Depends(get_db)
):
    """
    Main endpoint for invoice scanning and forgery detection
    """
    start_time = time.time()
    scan_id = str(uuid.uuid4())
    
    # Initialize scan status
    _scan_status[scan_id] = {
        "status": "processing",
        "progress": 0,
        "result": None,
        "error": None,
        "updated_at": datetime.utcnow().isoformat()
    }
    
    try:
        print(f"Received file: {file.filename}")
        print(f"Scan ID: {scan_id}")
        
        # File size validation
        file_content = await file.read()
        file_size = len(file_content)
        print(f"File size: {file_size} bytes")
        
        if file_size == 0:
            raise HTTPException(
                status_code=400, 
                detail="File is empty"
            )
        
        if file_size > settings.max_file_size:
            raise HTTPException(
                status_code=400, 
                detail=f"File size {file_size} bytes exceeds maximum allowed size of {settings.max_file_size} bytes"
            )
        
        # Validate file type
        if not file.filename.lower().endswith(('.pdf', '.jpg', '.jpeg', '.png')):
            raise HTTPException(
                status_code=400, 
                detail="File must be PDF, JPG, JPEG, or PNG"
            )
        
        # Generate unique filename
        file_id = str(uuid.uuid4())
        file_extension = Path(file.filename).suffix
        filename = f"{file_id}{file_extension}"
        file_path = UPLOAD_DIR / filename
        
        print(f"Saving file to: {file_path}")
        
        # Save uploaded file
        try:
            with open(file_path, "wb") as buffer:
                buffer.write(file_content)
            print("File saved successfully")
            
            # Log file content info for debugging
            print(f"File extension: {file_extension}")
            print(f"First 100 bytes (hex): {file_content[:100].hex() if len(file_content) >= 100 else file_content.hex()}")
            
            # Check if it's a valid image by checking magic bytes
            if file_extension.lower() in ['.jpg', '.jpeg']:
                if file_content[:2] == b'\xff\xd8':
                    print("Valid JPEG signature detected")
                else:
                    print(f"WARNING: Invalid JPEG signature. Got: {file_content[:2].hex()}")
            elif file_extension.lower() == '.png':
                if file_content[:8] == b'\x89PNG\r\n\x1a\n':
                    print("Valid PNG signature detected")
                else:
                    print(f"WARNING: Invalid PNG signature. Got: {file_content[:8].hex()}")
        except Exception as e:
            print(f"File save error: {e}")
            raise HTTPException(status_code=500, detail=f"File save error: {str(e)}")
        
        print("Starting invoice processing...")
        
        # Process invoice - single try block for everything
        try:
            print("Step 1: LLM extraction...")
            from app.services.llm_extractor import get_groq_extractor
            llm_extractor = get_groq_extractor()
            
            # For PDFs, extract text directly using PyMuPDF (no Poppler needed)
            if file_path.suffix.lower() == '.pdf':
                print("Extracting text from PDF using PyMuPDF...")
                ocr_text = extract_text_from_pdf_fitz(str(file_path))
                print(f"PyMuPDF extracted {len(ocr_text)} characters from PDF")
                if not ocr_text or len(ocr_text) < 50:
                    raise Exception("PDF text extraction failed - no text found")
                extracted = llm_extractor.extract_from_ocr_text(ocr_text)
            else:
                # For images, use LLM extractor's built-in OCR
                try:
                    extracted = llm_extractor.extract_from_image_path(str(file_path))
                except Exception as e:
                    print(f"Image extraction failed: {e}")
                    # Try a fallback: if the file might be corrupted, check if it's actually a PDF with wrong extension
                    try:
                        print("Attempting fallback: checking if file might be a PDF...")
                        ocr_text = extract_text_from_pdf_fitz(str(file_path))
                        if ocr_text and len(ocr_text) > 50:
                            print("Fallback successful: treating as PDF")
                            extracted = llm_extractor.extract_from_ocr_text(ocr_text)
                        else:
                            raise Exception("File appears to be corrupted - cannot extract text")
                    except Exception as fallback_error:
                        print(f"Fallback also failed: {fallback_error}")
                        raise Exception(f"Image processing failed: {e}. The uploaded file may be corrupted or in an unsupported format.")
            
            # Check if extraction returned error (rate limit exhausted)
            if isinstance(extracted, dict) and extracted.get('error') == 'rate_limit_exhausted':
                print(f"API rate limit exhausted: {extracted.get('message')}")
                return JSONResponse(
                    status_code=503,
                    content={
                        "success": False,
                        "error": "rate_limit_exhausted",
                        "message": extracted.get('message', 'All API providers rate limited. Please try again later.'),
                        "retry_after": extracted.get('retry_after', 3600)
                    }
                )
            
            # Check if extraction returned None
            if extracted is None:
                print("LLM extraction returned None, using regex fallback")
                if file_path.suffix.lower() == '.pdf':
                    ocr_text = extract_text_from_pdf_fitz(str(file_path))
                    extracted = llm_extractor._extract_with_regex(ocr_text)
                else:
                    raise Exception("LLM extraction failed and no OCR text available for regex fallback")
            
            print(f"LLM extraction completed. Confidence: {extracted.get('confidence', 0)}")
            
            print("Step 2: Validating extraction...")
            from app.services.llm_extractor import LLMInvoiceExtractor
            llm_validator = LLMInvoiceExtractor(llm_extractor.api_key)
            warnings = llm_validator.validate_extraction(extracted)
            print(f"Validation completed with {len(warnings)} warnings")
            
            # Convert LLM result to old format
            extracted_data = {
                'vendor_name': extracted.get('vendor_name') or None,
                'invoice_number': extracted.get('invoice_number') or None,
                'invoice_date': extracted.get('invoice_date') or None,
                'subtotal': extracted.get('subtotal') or None,
                'tax': extracted.get('tax') or None,
                'total': extracted.get('total') or None,
                'currency': extracted.get('currency') or None,
                'line_items': extracted.get('line_items') or [],
                'buyer_name': extracted.get('buyer_name') or None,
                'payment_terms': extracted.get('payment_terms') or None,
                'notes': extracted.get('notes') or None,
                'missing_fields': extracted.get('missing_fields') or [],
                'confidence_scores': extracted.get('confidence_scores') if isinstance(extracted.get('confidence_scores'), dict) else {},
                'structured_fields': [],
                'requires_manual_check': len(warnings) > 0 or extracted.get('confidence', 0) < 0.7,
                'extraction_method': 'llm_groq',
                'validation_warnings': warnings if warnings else []
            }
            
            # Set confidence - ensure it's a double
            confidence_value = extracted.get('confidence', 0.8)
            if isinstance(confidence_value, str):
                try:
                    confidence_value = float(confidence_value)
                except:
                    confidence_value = 0.8
            extracted_data['confidence_scores']['overall'] = float(confidence_value)
            
            ocr_result = {
                'text': str(extracted),
                'confidence': extracted.get('confidence', 0.8),
                'raw_ocr': extracted
            }
            
            print("Step 3: Deterministic Validation...")
            deterministic_results = validation_service.validate_deterministic(extracted_data)
            print(f"Deterministic results: {deterministic_results}")
            
            # Step 3.5: Check for total mismatch forgery indicator
            total_mismatch_warning = None
            subtotal = extracted_data.get('subtotal')
            tax = extracted_data.get('tax')
            total = extracted_data.get('total')
            
            if subtotal is not None and tax is not None and total is not None:
                calculated_total = subtotal + tax
                difference = abs(total - calculated_total)
                percent_diff = (difference / calculated_total) * 100 if calculated_total != 0 else 0
                
                if percent_diff > 5:  # Flag if difference > 5%
                    total_mismatch_warning = {
                        'type': 'total_mismatch_forgery',
                        'severity': 'critical',
                        'message': f'Invoice total ({total}) differs from calculated total (subtotal + tax = {calculated_total:.2f}). Difference: {difference:.2f} ({percent_diff:.1f}%)',
                        'invoice_total': total,
                        'calculated_total': calculated_total,
                        'difference': difference,
                        'percent_difference': percent_diff
                    }
                    print(f"FORGERY WARNING: Total mismatch detected! Invoice shows {total}, should be {calculated_total:.2f}")
                    
                    # Add to validation warnings
                    if 'validation_warnings' not in extracted_data:
                        extracted_data['validation_warnings'] = []
                    extracted_data['validation_warnings'].append(total_mismatch_warning)
                    
                    # Increase risk score for this forgery indicator
                    if 'risk_score' in deterministic_results:
                        deterministic_results['risk_score'] = min(100, deterministic_results['risk_score'] + 30)
                    if 'passed' in deterministic_results:
                        deterministic_results['passed'] = False
                    if 'reasons' in deterministic_results:
                        deterministic_results['reasons'].append('Total amount mismatch - potential forgery')
            
            print("Step 4: ML Anomaly Detection...")
            ml_results = await ml_service.detect_anomalies(extracted_data)
            print(f"ML results: {ml_results}")
            
            # Step 4.5: Calculate comprehensive validation score
            validation_score = validation_service.calculate_validation_score(extracted_data, {
                'checks': deterministic_results.get('checks', {}),
                'ml_analysis': ml_results
            })
            print(f"Validation score: {validation_score}/100")
            
            print("Step 5: Forgery Detection...")
            detection_service = get_forgery_detection_service()
            detection_result = detection_service.analyze(extracted_data)
            print(f"Detection verdict: {detection_result.verdict}")
            
            print("Step 6: XAI Report...")
            xai_engine = get_xai_reasoning_engine()
            xai_report = xai_engine.generate_report(detection_result.to_dict())
            
            print("Step 6.5: Groq AI Analysis...")
            groq_service = GroqService()
            ai_analysis = groq_service.analyze_invoice(extracted_data)
            print(f"AI analysis success: {ai_analysis['success']}")
            
            print("Step 7: Risk calculation...")
            risk_score = calculate_risk_score(deterministic_results, ml_results)
            risk_level = determine_risk_level(risk_score)
            
            print("Step 8: Reasoning...")
            reasoning = generate_reasoning(deterministic_results, ml_results)
            
            print("Step 9: Verification check...")
            needs_verification = check_verification_needed(extracted_data, risk_score, risk_level)
            needs_verification = needs_verification or detection_result.verdict != "LIKELY GENUINE"
            
            print("Step 10: Creating response...")
            
            # Convert numpy types to Python types for JSON serialization
            def convert_numpy(obj):
                import numpy as np
                if isinstance(obj, np.bool_):
                    return bool(obj)
                elif isinstance(obj, np.integer):
                    return int(obj)
                elif isinstance(obj, np.floating):
                    return float(obj)
                elif isinstance(obj, np.ndarray):
                    return obj.tolist()
                elif isinstance(obj, dict):
                    return {k: convert_numpy(v) for k, v in obj.items()}
                elif isinstance(obj, list):
                    return [convert_numpy(v) for v in obj]
                return obj
            
            response_data = {
                "success": True,
                "scan_id": scan_id,
                "file_id": file_id,
                "filename": file.filename,
                "extracted_data": convert_numpy(extracted_data) if extracted_data else {},
                "deterministic_validation": convert_numpy(deterministic_results) if deterministic_results else {},
                "ml_analysis": convert_numpy(ml_results) if ml_results else {},
                "risk_score": float(risk_score) if risk_score is not None else 0.0,
                "risk_level": risk_level if risk_level else 'low',
                "reasoning": reasoning if reasoning else [],
                "needs_verification": bool(needs_verification) if needs_verification is not None else False,
                "verification_fields": get_verification_fields(extracted_data, deterministic_results) if extracted_data else [],
                "processing_time": float(time.time() - start_time),
                "timestamp": datetime.now().isoformat(),
                # New fields for enhanced extraction
                "line_items": convert_numpy(extracted_data.get('line_items', [])),
                "payment_method": extracted_data.get('payment_method'),
                "vendor_address": extracted_data.get('vendor_address'),
                "vendor_phone": extracted_data.get('vendor_phone'),
                "validation_score": validation_score,
                "ml_score": ml_results.get('anomaly_score', 0.0) if ml_results else 0.0,
                # AI Analysis from Groq
                "ai_reasoning": ai_analysis.get('reasoning', ''),
                "ai_risk_factors": ai_analysis.get('risk_factors', []),
                "ai_confidence": ai_analysis.get('confidence', 0)
            }
            
            print(f"Response data created with keys: {list(response_data.keys())}")
            
            # Save to database
            try:
                from app.models.database import Invoice
                invoice = Invoice(
                    file_id=file_id,
                    filename=file.filename,
                    vendor_name=extracted_data.get('vendor_name'),
                    invoice_number=extracted_data.get('invoice_number'),
                    invoice_date=extracted_data.get('invoice_date'),
                    subtotal=extracted_data.get('subtotal'),
                    tax=extracted_data.get('tax'),
                    total=extracted_data.get('total'),
                    risk_score=float(risk_score) if risk_score is not None else 0.0,
                    risk_level=risk_level,
                    reasoning=json.dumps(convert_numpy(reasoning)) if reasoning else None,
                    needs_verification=bool(needs_verification) if needs_verification is not None else False,
                    verified=False,
                    extracted_data=convert_numpy(extracted_data),
                    validation_results=convert_numpy(deterministic_results),
                    ml_results=convert_numpy(ml_results),
                    verification_fields=convert_numpy(get_verification_fields(extracted_data, deterministic_results)),
                    processing_time=float(time.time() - start_time)
                )
                db.add(invoice)
                db.commit()
                print("Invoice saved to database")
            except Exception as db_error:
                print(f"Database save error: {db_error}")
                import traceback
                traceback.print_exc()
                db.rollback()
                raise HTTPException(
                    status_code=500,
                    detail={
                        "success": False,
                        "error": "database_save_failed",
                        "message": str(db_error),
                        "file_id": file_id,
                        "processing_succeeded": True
                    }
                )
            
            print("Returning response...")
            
            # Update scan status to completed
            _scan_status[scan_id] = {
                "status": "completed",
                "progress": 100,
                "result": response_data,
                "error": None,
                "updated_at": datetime.utcnow().isoformat()
            }
            
            return response_data
            
        except Exception as e:
            print(f"ERROR during processing: {e}")
            import traceback
            traceback.print_exc()
            
            # Update scan status to failed
            _scan_status[scan_id] = {
                "status": "failed",
                "progress": 0,
                "result": None,
                "error": str(e),
                "updated_at": datetime.utcnow().isoformat()
            }
            
            raise HTTPException(
                status_code=500,
                detail={"success": False, "error": "processing_error", "message": str(e)}
            )

    except HTTPException:
        # Update scan status to failed for HTTP exceptions
        _scan_status[scan_id] = {
            "status": "failed",
            "progress": 0,
            "result": None,
            "error": "HTTP exception occurred",
            "updated_at": datetime.utcnow().isoformat()
        }
        raise
    except Exception as e:
        print(f"General error: {e}")
        import traceback
        traceback.print_exc()
        
        # Update scan status to failed
        _scan_status[scan_id] = {
            "status": "failed",
            "progress": 0,
            "result": None,
            "error": str(e),
            "updated_at": datetime.utcnow().isoformat()
        }
        
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "server_error", "message": str(e)}
        )
    
    finally:
        # Clean up file
        try:
            if 'file_path' in locals() and os.path.exists(file_path):
                os.remove(file_path)
                print("File cleaned up")
        except:
            pass

@app.post("/chat/query")
async def chat_query(
    query: str = Form(...),
    extracted_data: str = Form(...),
    conversation_history: str = Form(default="[]"),
    db = Depends(get_db)
):
    """
    Chat with the extracted invoice data using LLM
    Allows users to ask questions about what was extracted
    Supports conversation history for multi-turn chat
    """
    try:
        import os
        from dotenv import load_dotenv
        load_dotenv()
        
        api_key = os.getenv('GROQ_API_KEY')
        if not api_key:
            raise HTTPException(
                status_code=500,
                detail={"success": False, "error": "groq_api_key_missing", "message": "Groq API key not configured"}
            )
        
        # Parse multiple API keys for rotation
        api_keys = [key.strip() for key in api_key.split(',') if key.strip()]
        current_key_index = 0
        
        import httpx
        import json
        from groq import Groq
        
        # Parse extracted_data from JSON string
        try:
            data = json.loads(extracted_data)
        except:
            data = {}
        
        # Parse conversation history
        try:
            history = json.loads(conversation_history)
        except:
            history = []
        
        # Build system prompt with invoice context
        system_prompt = f"""You are an expert invoice analysis assistant. You help users understand invoice data by answering questions clearly and accurately.

Here is the extracted invoice data:
{json.dumps(data, indent=2)}

Your role:
- Answer questions about this invoice
- Explain validation findings
- Clarify any anomalies or risk factors
- Be concise but thorough
- If information is not available, say so clearly
- Maintain context of previous questions in the conversation"""

        # Build messages array with history
        messages = [{"role": "system", "content": system_prompt}]
        messages.extend(history)
        messages.append({"role": "user", "content": query})
        
        # Use Groq client with API key rotation
        max_key_attempts = len(api_keys)
        for key_attempt in range(max_key_attempts):
            try:
                current_api_key = api_keys[current_key_index]
                print(f"Chat query: Using API key {current_key_index + 1}/{len(api_keys)}")
                client = Groq(api_key=current_api_key)
                response = client.chat.completions.create(
                    model="llama-3.3-70b-versatile",
                    messages=messages,
                    temperature=0.3,
                    max_tokens=1024
                )
                break  # Success, exit the loop
            except groq.AuthenticationError as e:
                print(f"Chat query authentication error (key {current_key_index + 1}): {e}")
                if current_key_index < len(api_keys) - 1:
                    current_key_index += 1
                    print(f"Rotating to next API key")
                    continue
                return JSONResponse(
                    status_code=500,
                    content={
                        "success": False,
                        "error": "chat_query_failed",
                        "message": "Chat query failed: All API keys are invalid. Please check your GROQ_API_KEY configuration."
                    }
                )
            except groq.RateLimitError as e:
                print(f"Chat query rate limit error (key {current_key_index + 1}): {e}")
                if current_key_index < len(api_keys) - 1:
                    current_key_index += 1
                    print(f"Rotating to next API key")
                    continue
                return JSONResponse(
                    status_code=500,
                    content={
                        "success": False,
                        "error": "chat_query_failed",
                        "message": "Chat query failed: All API keys have reached rate limit. Please try again in a few minutes or upgrade your Groq account for higher limits."
                    }
                )
            except Exception as e:
                print(f"Chat query error: {e}")
                return JSONResponse(
                    status_code=500,
                    content={
                        "success": False,
                        "error": "chat_query_failed",
                        "message": f"Chat query failed: {str(e)}"
                    }
                )
        
        answer = response.choices[0].message.content
        
        # Update conversation history with this exchange
        updated_history = history + [
            {"role": "user", "content": query},
            {"role": "assistant", "content": answer}
        ]
        
        return {
            "success": True,
            "answer": answer,
            "query": query,
            "conversation_history": updated_history
        }
            
    except HTTPException:
        raise
    except Exception as e:
        print(f"Chat query error: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": "chat_query_failed", "message": f"Chat query failed: {str(e)}"}
        )

@app.post("/scan-batch")
async def scan_batch(
    files: List[UploadFile] = File(...),
    db = Depends(get_db)
):
    """
    Batch endpoint for processing multiple invoices using the same pipeline as single upload
    Maximum 5 invoices per batch
    """
    MAX_BATCH_SIZE = 5
    
    if len(files) > MAX_BATCH_SIZE:
        raise HTTPException(
            status_code=400,
            detail=f"Maximum {MAX_BATCH_SIZE} invoices allowed per batch"
        )
    
    if len(files) == 0:
        raise HTTPException(
            status_code=400,
            detail="At least one file must be provided"
        )
    
    # Initialize PaddleOCR once for all files (faster than re-initializing for each file)
    print("Initializing PaddleOCR...")
    from app.services.optimized_paddleocr import OptimizedPaddleOCRProcessor
    paddle_processor = OptimizedPaddleOCRProcessor(
        confidence_threshold=0.7,
        max_image_size=(1920, 1080),
        enable_grayscale=True
    )
    print("PaddleOCR initialized")
    
    # Initialize LLM extractor once
    from app.services.llm_extractor import get_groq_extractor
    llm_extractor = get_groq_extractor()
    
    results = []
    errors = []
    
    for file in files:
        file_start_time = time.time()
        try:
            print(f"\nProcessing file: {file.filename}")
            
            # File size validation
            file_content = await file.read()
            file_size = len(file_content)
            
            if file_size == 0:
                errors.append({
                    "filename": file.filename,
                    "error": "File is empty"
                })
                continue
            
            if file_size > settings.max_file_size:
                errors.append({
                    "filename": file.filename,
                    "error": f"File size exceeds maximum allowed size"
                })
                continue
            
            # Validate file type
            if not file.filename.lower().endswith(('.pdf', '.jpg', '.jpeg', '.png')):
                errors.append({
                    "filename": file.filename,
                    "error": "File must be PDF, JPG, JPEG, or PNG"
                })
                continue
            
            # Generate unique filename
            file_id = str(uuid.uuid4())
            file_extension = Path(file.filename).suffix
            filename = f"{file_id}{file_extension}"
            file_path = UPLOAD_DIR / filename
            
            # Save uploaded file
            with open(file_path, "wb") as buffer:
                buffer.write(file_content)
            
            # Process invoice using optimized pipeline
            print("Step 1: LLM extraction with OCR...")
            
            # For PDFs, extract text directly using PyMuPDF (faster than OCR)
            if file_path.suffix.lower() == '.pdf':
                print("Extracting text from PDF using PyMuPDF...")
                ocr_text = extract_text_from_pdf_fitz(str(file_path))
                print(f"PyMuPDF extracted {len(ocr_text)} characters from PDF")
                if not ocr_text or len(ocr_text) < 50:
                    raise Exception("PDF text extraction failed - no text found")
                extracted = llm_extractor.extract_from_ocr_text(ocr_text)
            else:
                # For images, use PaddleOCR for faster OCR (instead of EasyOCR)
                import cv2
                image = cv2.imread(str(file_path))
                if image is not None:
                    print("Running PaddleOCR on image...")
                    paddle_result = paddle_processor.process_single_invoice(image, file.filename)
                    ocr_text_paddle = ' '.join([r.text for r in paddle_result.ocr_results])
                    print(f"PaddleOCR extracted {len(ocr_text_paddle)} characters")
                    extracted = llm_extractor.extract_from_ocr_text(ocr_text_paddle)
                else:
                    # Fallback to LLM extractor's built-in OCR
                    extracted = llm_extractor.extract_from_image_path(str(file_path))
            
            print(f"Extraction completed. Confidence: {extracted.get('confidence', 0)}")
            
            extracted_data = {
                'vendor_name': extracted.get('vendor_name'),
                'invoice_number': extracted.get('invoice_number'),
                'invoice_date': extracted.get('invoice_date'),
                'subtotal': extracted.get('subtotal'),
                'tax': extracted.get('tax'),
                'total': extracted.get('total'),
                'line_items': extracted.get('line_items', []),
            }
            
            print("Step 2: Deterministic Validation...")
            validation_service = ValidationService()
            deterministic_results = validation_service.validate_deterministic(extracted_data)
            
            print("Step 3: ML Anomaly Detection...")
            ml_service = MLService()
            ml_results = await ml_service.detect_anomalies(extracted_data)
            
            print("Step 4: Forgery Detection...")
            detection_service = get_forgery_detection_service()
            detection_result = detection_service.analyze(extracted_data)
            
            print("Step 5: XAI Report...")
            xai_engine = get_xai_reasoning_engine()
            xai_report = xai_engine.generate_report(detection_result.to_dict())
            
            print("Step 6: Risk calculation...")
            risk_score = calculate_risk_score(deterministic_results, ml_results)
            risk_level = determine_risk_level(risk_score)
            
            print("Step 7: Reasoning...")
            reasoning = generate_reasoning(deterministic_results, ml_results)
            
            print("Step 8: Verification check...")
            needs_verification = check_verification_needed(extracted_data, risk_score, risk_level)
            needs_verification = needs_verification or detection_result.verdict != "LIKELY GENUINE"
            
            # Convert numpy types to Python types
            def convert_numpy(obj):
                import numpy as np
                if isinstance(obj, np.bool_):
                    return bool(obj)
                elif isinstance(obj, np.integer):
                    return int(obj)
                elif isinstance(obj, np.floating):
                    return float(obj)
                elif isinstance(obj, np.ndarray):
                    return obj.tolist()
                elif isinstance(obj, dict):
                    return {k: convert_numpy(v) for k, v in obj.items()}
                elif isinstance(obj, list):
                    return [convert_numpy(v) for v in obj]
                return obj
            
            response_data = {
                "file_id": file_id,
                "filename": file.filename,
                "extracted_data": convert_numpy(extracted_data) if extracted_data else {},
                "deterministic_validation": convert_numpy(deterministic_results) if deterministic_results else {},
                "ml_analysis": convert_numpy(ml_results) if ml_results else {},
                "risk_score": float(risk_score) if risk_score is not None else 0.0,
                "risk_level": risk_level if risk_level else 'low',
                "reasoning": reasoning if reasoning else [],
                "needs_verification": bool(needs_verification) if needs_verification is not None else False,
                "verification_fields": get_verification_fields(extracted_data, deterministic_results) if extracted_data else [],
                "processing_time": float(time.time() - file_start_time),
                "timestamp": datetime.now().isoformat(),
                "xai_report": xai_report
            }
            
            # Save to database
            try:
                invoice = Invoice(
                    file_id=file_id,
                    filename=file.filename,
                    vendor_name=extracted_data.get('vendor_name'),
                    invoice_number=extracted_data.get('invoice_number'),
                    invoice_date=extracted_data.get('invoice_date'),
                    subtotal=extracted_data.get('subtotal'),
                    tax=extracted_data.get('tax'),
                    total=extracted_data.get('total'),
                    risk_score=float(risk_score) if risk_score is not None else 0.0,
                    risk_level=risk_level,
                    reasoning=json.dumps(reasoning) if reasoning else None,
                    needs_verification=bool(needs_verification) if needs_verification is not None else False,
                    verified=False,
                    extracted_data=convert_numpy(extracted_data) if extracted_data else {},
                    validation_results=convert_numpy(deterministic_results) if deterministic_results else {},
                    ml_results=convert_numpy(ml_results) if ml_results else {},
                    verification_fields=convert_numpy(get_verification_fields(extracted_data, deterministic_results)) if extracted_data else [],
                    processing_time=float(time.time() - file_start_time)
                )
                db.add(invoice)
                db.commit()
                print("Invoice saved to database")
            except Exception as db_error:
                print(f"Database save error: {db_error}")
                db.rollback()
            
            results.append(response_data)
            
        except Exception as e:
            print(f"ERROR processing {file.filename}: {e}")
            import traceback
            traceback.print_exc()
            errors.append({
                "filename": file.filename,
                "error": str(e)
            })
        finally:
            # Clean up file
            try:
                if 'file_path' in locals() and os.path.exists(file_path):
                    os.remove(file_path)
            except:
                pass
    
    return {
        "success": True,
        "total_files": len(files),
        "processed": len(results),
        "failed": len(errors),
        "results": results,
        "errors": errors
    }

@app.get("/invoices")
async def get_invoices(
    skip: int = 0,
    limit: int = 100,
    risk_level: Optional[str] = None,
    db = Depends(get_db)
):
    """
    Retrieve processed invoices with filtering
    """
    try:
        print(f"Get invoices request: skip={skip}, limit={limit}, risk_level={risk_level}")
        
        # Validate parameters
        if skip < 0:
            raise HTTPException(status_code=400, detail="skip must be >= 0")
        if limit <= 0 or limit > 1000:
            raise HTTPException(status_code=400, detail="limit must be between 1 and 1000")
        
        if risk_level and risk_level not in ['low', 'medium', 'high']:
            raise HTTPException(status_code=400, detail="risk_level must be low, medium, or high")
        
        # Query database for actual invoices
        from sqlalchemy import desc
        
        query = db.query(Invoice)
        
        # Filter by risk level if specified
        if risk_level:
            query = query.filter(Invoice.risk_level == risk_level)
        
        # Get total count
        total = query.count()
        
        # Apply pagination and ordering (newest first)
        invoices = query.order_by(desc(Invoice.created_at)).offset(skip).limit(limit).all()
        
        # Format invoices for response
        formatted_invoices = []
        for inv in invoices:
            formatted_invoice = {
                "file_id": inv.file_id,
                "filename": inv.filename,
                "extracted_data": inv.extracted_data or {},
                "ocr_confidence": inv.extracted_data.get("confidence_scores", {}) if inv.extracted_data else {},
                "deterministic_validation": inv.validation_results or {
                    "passed": True,
                    "risk_score": inv.risk_score or 0.0,
                    "checks": {},
                    "reasons": []
                },
                "ml_analysis": inv.ml_results or {
                    "is_anomaly": False,
                    "anomaly_score": 0.0,
                    "anomaly_reason": "",
                    "confidence": 0.8
                },
                "risk_score": inv.risk_score or 0.0,
                "risk_level": inv.risk_level or "low",
                "reasoning": inv.reasoning or ["Invoice processed"],
                "needs_verification": inv.needs_verification or False,
                "verification_fields": inv.verification_fields or [],
                "processing_time": inv.processing_time or 0.0,
                "timestamp": inv.created_at.isoformat() if inv.created_at else ""
            }
            formatted_invoices.append(formatted_invoice)
        
        return {
            "invoices": formatted_invoices,
            "total": total,
            "skip": skip,
            "limit": limit,
            "risk_level": risk_level
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Get invoices error: {e}")
        raise HTTPException(
            status_code=500, 
            detail=f"Failed to retrieve invoices: {str(e)}"
        )

def calculate_risk_score(deterministic: Dict, ml: Dict) -> float:
    """Calculate overall risk score from deterministic and ML results"""
    deterministic_score = deterministic.get('risk_score', 0.0)
    ml_score = ml.get('anomaly_score', 0.0)
    
    # Weighted combination (70% deterministic, 30% ML)
    return (deterministic_score * 0.7) + (ml_score * 0.3)

def determine_risk_level(score: float) -> str:
    """Determine risk level from score"""
    if score >= 70:
        return "high"
    elif score >= 40:
        return "medium"
    else:
        return "low"

def generate_reasoning(deterministic: Dict, ml: Dict) -> List[str]:
    """Generate detailed reasoning for risk assessment"""
    reasons = []
    
    # Add deterministic reasoning
    for check, result in deterministic.get('checks', {}).items():
        if not result.get('passed', True):
            reasons.append(result.get('reason', f"{check} failed"))
    
    # Add ML reasoning
    if ml.get('is_anomaly', False):
        reasons.append(f"ML anomaly detected: {ml.get('anomaly_reason', 'Statistical outlier')}")
    
    return reasons

def check_verification_needed(extracted: Dict, risk_score: float, risk_level: str) -> bool:
    """Check if human verification is needed"""
    # Check OCR confidence for key fields
    key_fields_confidence = extracted.get('confidence_scores', {})
    total_confidence = key_fields_confidence.get('grand_total', 1.0)
    
    # Verification needed if:
    # 1. Low confidence on total amount (< 70%)
    # 2. High risk level
    # 3. Missing critical fields
    missing_fields = [k for k, v in extracted.items() if not v or v == '']
    
    return (
        total_confidence < 0.7 or
        risk_level == 'high' or
        len(missing_fields) > 0
    )

def get_verification_fields(extracted: Dict, deterministic: Dict) -> List[str]:
    """Get list of fields requiring human verification"""
    fields = []
    
    # Check confidence scores
    confidence_scores = extracted.get('confidence_scores', {})
    for field, confidence in confidence_scores.items():
        if confidence < 0.7:
            fields.append(field)
    
    # Check failed validations
    for check, result in deterministic.get('checks', {}).items():
        if not result.get('passed', True):
            fields.append(check)
    
    return list(set(fields))

async def save_invoice_data(response: InvoiceResponse):
    """Save invoice data to database"""
    # Implement database save logic
    pass

# Phase 5: Feature Flag Validation Endpoints
@app.get("/api/v1/feature-flags/status")
async def get_feature_flags_status():
    """
    Get current state of all feature flags with readiness checks
    Returns flag states and validation results
    """
    all_flags = feature_flags.get_all_flags()
    all_validations = feature_flag_validator.validate_all()
    
    return {
        "flags": all_flags,
        "validations": all_validations,
        "timestamp": datetime.utcnow().isoformat()
    }

@app.post("/api/v1/feature-flags/validate/{flag_name}")
async def validate_feature_flag(flag_name: str):
    """
    Run pre-flight checks for a specific feature flag
    Returns validation result with issues and warnings
    """
    # Map flag name to validation method
    validation_methods = {
        "enable_jwt_auth": feature_flag_validator.validate_jwt_auth,
        "enable_async_scan": feature_flag_validator.validate_async_scan,
        "enable_db_v2": feature_flag_validator.validate_db_v2,
        "enable_security_hardening": feature_flag_validator.validate_security_hardening,
    }
    
    if flag_name not in validation_methods:
        raise HTTPException(
            status_code=404,
            detail=f"Unknown flag: {flag_name}. Valid flags: {list(validation_methods.keys())}"
        )
    
    validation_result = validation_methods[flag_name]()
    
    return {
        "flag": flag_name,
        "validation": validation_result,
        "current_state": feature_flags.get_flag_state(flag_name),
        "timestamp": datetime.utcnow().isoformat()
    }

@app.get("/invoices/{file_id}/report")
async def download_invoice_report(file_id: str, db = Depends(get_db)):
    """Download detailed invoice report as JSON"""
    try:
        invoice = db.query(Invoice).filter(Invoice.file_id == file_id).first()
        if not invoice:
            raise HTTPException(status_code=404, detail="Invoice not found")
        
        # Generate comprehensive report
        report = {
            "report_id": f"RPT-{file_id}",
            "generated_at": datetime.utcnow().isoformat(),
            "invoice_details": {
                "file_id": invoice.file_id,
                "filename": invoice.filename,
                "vendor_name": invoice.vendor_name,
                "invoice_number": invoice.invoice_number,
                "invoice_date": invoice.invoice_date,
                "total": invoice.total,
            },
            "validation_results": invoice.validation_results,
            "ml_results": invoice.ml_results,
            "risk_assessment": {
                "risk_score": invoice.risk_score,
                "risk_level": invoice.risk_level,
                "needs_verification": invoice.needs_verification,
                "verified": invoice.verified,
            },
            "extracted_data": invoice.extracted_data,
            "verification_fields": invoice.verification_fields,
        }
        
        return report
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Report generation failed: {str(e)}")

if __name__ == "__main__":
    import sys
    import os
    # Fix Unicode encoding for Windows
    if sys.platform == "win32":
        os.environ["PYTHONIOENCODING"] = "utf-8"
    
    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug
    )
