"""
Invoice OCR Pipeline - FastAPI Application
Phase 4: API Layer with error handling
"""

import os
import io
import cv2
import numpy as np
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
import logging

# Import pipeline modules
from app.services.image_processor import ImageProcessor, ProcessedImage
from app.services.paddle_ocr_extractor import PaddleOCRExtractor, OCROutput
from app.services.data_extractor import DataExtractor, InvoiceData

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Invoice OCR Pipeline API",
    description="Advanced OCR preprocessing and extraction using PaddleOCR",
    version="1.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize pipeline components
image_processor = ImageProcessor(target_dpi=300)
ocr_extractor = PaddleOCRExtractor(
    use_angle_cls=True,
    lang='en',
    confidence_threshold=0.85,
    show_log=False
)
data_extractor = DataExtractor()


# Pydantic response models
class ExtractionResult(BaseModel):
    success: bool
    message: str
    invoice_data: Dict[str, Any]
    ocr_metadata: Dict[str, Any]
    processing_time_ms: float


class HealthResponse(BaseModel):
    status: str
    components: Dict[str, str]


class ErrorResponse(BaseModel):
    error: str
    detail: str
    suggestion: Optional[str] = None


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Check system health and component status"""
    return HealthResponse(
        status="healthy",
        components={
            "image_processor": "ready",
            "paddle_ocr": "initialized",
            "data_extractor": "ready"
        }
    )


@app.post("/extract", response_model=ExtractionResult)
async def extract_invoice(file: UploadFile = File(...)):
    """
    Process invoice image and extract structured data.
    
    - **file**: Invoice image (JPG, PNG) or PDF
    
    Returns extracted fields: vendor_name, invoice_date, total_amount, tax_amount, invoice_number
    """
    import time
    start_time = time.time()
    
    try:
        # Validate file
        if not file.content_type or not (
            file.content_type.startswith("image/") or 
            file.content_type == "application/pdf"
        ):
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type: {file.content_type}. Must be image (JPG/PNG) or PDF."
            )
        
        # Read file
        contents = await file.read()
        if len(contents) == 0:
            raise HTTPException(status_code=400, detail="Empty file uploaded")
        
        # Decode image
        if file.content_type == "application/pdf":
            # For PDF, we'd need pdf2image or similar
            raise HTTPException(
                status_code=400, 
                detail="PDF processing requires additional setup. Please convert to image first."
            )
        
        nparr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            raise HTTPException(
                status_code=400,
                detail="Failed to decode image. File may be corrupted."
            )
        
        logger.info(f"Processing image: {file.filename}, shape: {image.shape}")
        
        # Phase 1: Image Preprocessing
        try:
            processed = image_processor.process(image)
            logger.info(f"Image preprocessed: {processed.original_shape} -> {processed.processed_shape}")
        except Exception as e:
            logger.error(f"Image preprocessing failed: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Image preprocessing failed: {str(e)}"
            )
        
        # Phase 2: OCR Extraction
        try:
            ocr_output = ocr_extractor.extract(processed.image)
            logger.info(f"OCR complete: {len(ocr_output.results)} results")
        except ValueError as e:
            logger.warning(f"OCR extraction issue: {e}")
            # Return partial response
            processing_time = (time.time() - start_time) * 1000
            return ExtractionResult(
                success=False,
                message=str(e),
                invoice_data={},
                ocr_metadata={
                    "error": str(e),
                    "preprocessing": {
                        "original_shape": processed.original_shape,
                        "processed_shape": processed.processed_shape,
                        "perspective_corrected": processed.perspective_corrected
                    }
                },
                processing_time_ms=round(processing_time, 2)
            )
        except Exception as e:
            logger.error(f"OCR extraction failed: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"OCR extraction failed: {str(e)}"
            )
        
        # Phase 3: Data Extraction
        try:
            invoice_data = data_extractor.extract(ocr_output)
            logger.info(f"Data extraction complete: {len(invoice_data.fields)} fields")
        except Exception as e:
            logger.error(f"Data extraction failed: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Data extraction failed: {str(e)}"
            )
        
        # Calculate processing time
        processing_time = (time.time() - start_time) * 1000
        
        return ExtractionResult(
            success=True,
            message="Invoice extraction completed successfully",
            invoice_data=invoice_data.to_dict(),
            ocr_metadata={
                "preprocessing": {
                    "original_shape": processed.original_shape,
                    "processed_shape": processed.processed_shape,
                    "perspective_corrected": processed.perspective_corrected
                },
                "ocr": {
                    "total_detected": len(ocr_output.results) + ocr_output.filtered_count,
                    "kept": len(ocr_output.results),
                    "filtered": ocr_output.filtered_count,
                    "confidence_threshold": 0.85
                },
                "extraction": {
                    "fields_found": len(invoice_data.fields),
                    "average_confidence": invoice_data.extraction_confidence
                }
            },
            processing_time_ms=round(processing_time, 2)
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error: {str(e)}"
        )


@app.post("/preprocess")
async def preprocess_only(file: UploadFile = File(...)):
    """
    Only run image preprocessing without OCR.
    Useful for debugging image quality issues.
    """
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            raise HTTPException(status_code=400, detail="Failed to decode image")
        
        processed = image_processor.process(image)
        
        return {
            "success": True,
            "original_shape": processed.original_shape,
            "processed_shape": processed.processed_shape,
            "perspective_corrected": processed.perspective_corrected,
            "target_dpi": processed.dpi
        }
        
    except Exception as e:
        logger.error(f"Preprocessing failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/ocr-raw")
async def ocr_raw(file: UploadFile = File(...)):
    """
    Run OCR without data extraction.
    Returns raw OCR results with bounding boxes.
    """
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            raise HTTPException(status_code=400, detail="Failed to decode image")
        
        # Preprocess
        processed = image_processor.process(image)
        
        # OCR
        ocr_output = ocr_extractor.extract_raw(processed.image)
        
        return {
            "success": True,
            "ocr_results": ocr_output,
            "count": len(ocr_output)
        }
        
    except Exception as e:
        logger.error(f"OCR failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/")
async def root():
    """API information"""
    return {
        "name": "Invoice OCR Pipeline API",
        "version": "1.0.0",
        "phases": [
            "Phase 1: Image Preprocessing (DPI scaling, binarization, perspective correction)",
            "Phase 2: OCR Extraction (PaddleOCR with confidence filtering)",
            "Phase 3: Data Extraction (Regex + Spatial heuristics)"
        ],
        "endpoints": {
            "POST /extract": "Full pipeline - upload image, get extracted invoice data",
            "POST /preprocess": "Image preprocessing only",
            "POST /ocr-raw": "OCR without data extraction",
            "GET /health": "Health check"
        }
    }


# Error handlers
@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    return {
        "error": exc.status_code,
        "detail": exc.detail,
        "suggestion": "Check file format and try again with a clear invoice image"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
