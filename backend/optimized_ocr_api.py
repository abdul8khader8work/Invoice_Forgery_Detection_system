"""
Optimized Batch Processing API with Concurrent Architecture
High-performance PaddleOCR-only endpoint for batch invoice processing
Asynchronous Producer-Consumer pattern with max_workers=2
"""

import os
import cv2
import numpy as np
from fastapi import FastAPI, File, UploadFile, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import logging
import tempfile
import shutil
from pathlib import Path
import time
import asyncio
from concurrent.futures import ThreadPoolExecutor, as_completed
import gc

# Import optimized services
from app.services.optimized_paddleocr import OptimizedPaddleOCRProcessor, OptimizedInvoiceResult
from app.services.ocr_post_processor import OCRPostProcessor, VendorDatabase

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Optimized Invoice OCR API",
    description="High-performance PaddleOCR-only batch processing with memory management",
    version="2.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global processor instance (initialized once)
processor = None
post_processor = None

# Memory-safe settings
MAX_WORKERS = 1  # PaddleOCR is not thread-safe, process sequentially
MAX_BATCH_SIZE = 5


def get_processor():
    """Get or initialize the global processor instance"""
    global processor
    if processor is None:
        processor = OptimizedPaddleOCRProcessor(
            confidence_threshold=0.85,
            max_image_size=(1920, 1080),
            enable_grayscale=True
        )
    return processor


def get_post_processor():
    """Get or initialize the post-processor instance"""
    global post_processor
    if post_processor is None:
        # Initialize with common vendor database
        vendors = [
            "Microsoft Corporation",
            "Amazon Web Services",
            "Google LLC",
            "Apple Inc.",
            "Adobe Systems",
            "Oracle Corporation",
            "IBM Corporation",
            "Cisco Systems",
            "Intel Corporation",
            "Dell Technologies",
            "HP Inc.",
            "Lenovo Group",
            "Samsung Electronics",
            "Sony Corporation"
        ]
        vendor_db = VendorDatabase(vendors)
        post_processor = OCRPostProcessor(vendor_db)
    return post_processor


# Pydantic response models
class BatchProcessingResult(BaseModel):
    success: bool
    message: str
    batch_id: str
    total_invoices: int
    processed_invoices: List[Dict[str, Any]]
    manual_review_required: List[str]
    total_processing_time_ms: float
    average_memory_per_invoice_mb: float


class SingleInvoiceResult(BaseModel):
    success: bool
    invoice_id: str
    processing_time_ms: float
    extracted_data: Dict[str, Any]
    manual_review_required: bool
    review_reasons: List[str]
    memory_peak_mb: float


class HealthResponse(BaseModel):
    status: str
    processor_ready: bool
    post_processor_ready: bool
    memory_optimization_enabled: bool


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Check system health and component status"""
    try:
        proc = get_processor()
        post_proc = get_post_processor()
        return HealthResponse(
            status="healthy",
            processor_ready=proc is not None,
            post_processor_ready=post_proc is not None,
            memory_optimization_enabled=True
        )
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return HealthResponse(
            status="unhealthy",
            processor_ready=False,
            post_processor_ready=False,
            memory_optimization_enabled=False
        )


@app.post("/process-batch", response_model=BatchProcessingResult)
async def process_batch(files: List[UploadFile] = File(...)):
    """
    Process a batch of invoices with optimized PaddleOCR.
    Maximum 5 invoices per batch for memory efficiency.
    
    - **files**: List of invoice images (JPG, PNG) or PDFs
    
    Returns processed results with manual review flags for low confidence.
    """
    if len(files) > MAX_BATCH_SIZE:
        raise HTTPException(
            status_code=400,
            detail=f"Maximum {MAX_BATCH_SIZE} invoices allowed per batch for memory optimization"
        )
    
    if len(files) == 0:
        raise HTTPException(
            status_code=400,
            detail="At least one file must be provided"
        )
    
    batch_id = f"batch_{int(time.time())}"
    start_time = time.time()
    
    try:
        # Collect file data and detect types
        files_data = []  # List of (invoice_id, data, file_type)
        for file in files:
            # Accept images and PDFs
            valid_types = ['image/', 'application/pdf']
            if not file.content_type or not any(file.content_type.startswith(t) for t in valid_types):
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid file type: {file.filename}. Must be an image (JPG/PNG) or PDF."
                )
            
            # Validate file size (max 10MB per image)
            contents = await file.read()
            if len(contents) > 10 * 1024 * 1024:
                raise HTTPException(
                    status_code=400,
                    detail=f"File too large: {file.filename}. Maximum 10MB allowed."
                )
            
            # Determine file type
            file_type = 'pdf' if file.content_type.startswith('application/pdf') else 'image'
            invoice_id = Path(file.filename).stem
            
            files_data.append((invoice_id, contents, file_type))
            logger.info(f"Queued {file.filename} as {file_type}")
        
        # Process batch concurrently with controlled parallelism
        proc = get_processor()
        post_proc = get_post_processor()

        # Use concurrent processing with max_workers=2 for memory safety
        raw_results = proc.process_batch_concurrent(files_data, max_workers=MAX_WORKERS)

        processed_invoices = []
        manual_review_required = []
        total_memory = 0.0

        # Apply post-processing to all results
        for result in raw_results:
            # Apply post-processing to handle OCR imperfections
            ocr_texts = [r.text for r in result.ocr_results]
            post_processed_data = post_proc.process_invoice_data(ocr_texts)

            # Merge with original extracted data
            result.extracted_data.update(post_processed_data)

            # Convert to dict for response
            invoice_dict = result.to_dict()
            processed_invoices.append(invoice_dict)

            # Track manual review requirements
            if result.manual_review_required:
                manual_review_required.append(result.invoice_id)

            total_memory += result.memory_peak_mb
        
        # Calculate metrics
        total_processing_time = (time.time() - start_time) * 1000
        avg_memory = total_memory / len(files) if files else 0
        
        logger.info("Batch processing completed")

        return BatchProcessingResult(
            success=True,
            message=f"Successfully processed {len(files)} invoices",
            batch_id=batch_id,
            total_invoices=len(files),
            processed_invoices=processed_invoices,
            manual_review_required=manual_review_required,
            total_processing_time_ms=round(total_processing_time, 2),
            average_memory_per_invoice_mb=round(avg_memory, 2)
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Batch processing failed: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Batch processing failed: {str(e)}"
        )


@app.post("/process-single", response_model=SingleInvoiceResult)
async def process_single(file: UploadFile = File(...)):
    """
    Process a single invoice with optimized PaddleOCR.
    Includes post-processing for OCR imperfections.
    """
    # Accept images and PDFs
    valid_types = ['image/', 'application/pdf']
    if not file.content_type or not any(file.content_type.startswith(t) for t in valid_types):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid file type: {file.filename}. Must be an image (JPG/PNG) or PDF."
        )
    
    # Validate file size
    contents = await file.read()
    if len(contents) > 10 * 1024 * 1024:
        raise HTTPException(
            status_code=400,
            detail=f"File too large: {file.filename}. Maximum 10MB allowed."
        )
    
    try:
        # Determine file type
        file_type = 'pdf' if file.content_type.startswith('application/pdf') else 'image'
        invoice_id = Path(file.filename).stem
        
        # Process with optimized PaddleOCR (handles both images and PDFs)
        proc = get_processor()
        result = proc._process_single_file_with_cleanup(invoice_id, contents, file_type)
        
        # Apply post-processing
        post_proc = get_post_processor()
        ocr_texts = [r.text for r in result.ocr_results]
        post_processed_data = post_proc.process_invoice_data(ocr_texts)
        
        # Merge data
        result.extracted_data.update(post_processed_data)
        
        return SingleInvoiceResult(
            success=True,
            invoice_id=result.invoice_id,
            processing_time_ms=result.processing_time_ms,
            extracted_data=result.extracted_data,
            manual_review_required=result.manual_review_required,
            review_reasons=result.review_reasons,
            memory_peak_mb=result.memory_peak_mb
        )
        
    except Exception as e:
        logger.error(f"Single invoice processing failed: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Processing failed: {str(e)}"
        )


@app.get("/")
async def root():
    """API information"""
    return {
        "name": "Optimized Invoice OCR API",
        "version": "2.0.0",
        "features": [
            "PaddleOCR-only processing (zero redundancy)",
            "Memory optimization with explicit garbage collection",
            "Image resizing and grayscale conversion",
            "Generator-based batch processing for responsive UI",
            "Confidence gate (0.85) with Manual Review flagging",
            "Post-extraction logic (regex correction, fuzzy matching)",
            "PDF support (auto-converted to images)"
        ],
        "endpoints": {
            "POST /process-batch": "Process up to 5 invoices in a batch",
            "POST /process-single": "Process a single invoice",
            "GET /health": "Health check"
        },
        "optimizations": {
            "max_batch_size": MAX_BATCH_SIZE,
            "max_workers": MAX_WORKERS,
            "confidence_threshold": 0.85,
            "max_image_size": "1920x1080",
            "grayscale_enabled": True,
            "memory_management": "Explicit GC after each invoice"
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
