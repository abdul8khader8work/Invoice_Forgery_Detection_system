"""
Smart Ingestion Endpoint for Invoice Forgery Detection System
FastAPI endpoint for file upload with validation and preprocessing
"""

from fastapi import APIRouter, File, UploadFile, HTTPException, status
from fastapi.responses import JSONResponse
from typing import Dict, Any
from pathlib import Path
import tempfile
import os

from app.services.smart_ingestion_service import SmartIngestionService

router = APIRouter(prefix="/ingest", tags=["smart-ingestion"])

# Initialize service
smart_ingestion = SmartIngestionService()

# Allowed file extensions and MIME types
ALLOWED_EXTENSIONS = {'.pdf', '.jpg', '.jpeg', '.png'}
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB


@router.post("/", response_model=Dict[str, Any])
async def smart_ingest(file: UploadFile = File(...)):
    """
    Smart Ingestion Endpoint:
    1. Validates file format and size
    2. Verifies file signature (security)
    3. Converts PDF to image if needed
    4. Applies OpenCV preprocessing
    5. Auto-crops and deskews document
    6. Returns cleaned image ready for OCR
    
    Returns:
        - status: "clean" on success, "error" on failure
        - file_path: Path to processed image
        - message: Status message
        - processing_info: Details about preprocessing steps
    """
    
    # Check if file is provided
    if not file or not file.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No file provided"
        )
    
    # Get file extension
    file_ext = Path(file.filename).suffix.lower()
    
    # Validate extension
    if file_ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file format: {file_ext}. Allowed: PDF, JPG, JPEG, PNG"
        )
    
    try:
        # Read file content
        file_content = await file.read()
        file_size = len(file_content)
        
        # Validate file size
        if file_size == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="File is empty"
            )
        
        if file_size > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"File too large: {file_size / (1024*1024):.1f}MB. Maximum: 10MB"
            )
        
        # Process through Smart Ingestion pipeline
        result = smart_ingestion.process_file(file_content, file.filename)
        
        # Handle processing result
        if result['success']:
            return JSONResponse(
                status_code=status.HTTP_200_OK,
                content={
                    "status": "clean",
                    "file_path": result['file_path'],
                    "message": result['message'],
                    "processing_info": result['processing_info']
                }
            )
        else:
            # Check if it's a document boundary detection error
            if "Invoice boundaries not found" in result['message']:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=result['message']
                )
            else:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=result['message']
                )
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Processing error: {str(e)}"
        )


@router.get("/health")
async def ingestion_health():
    """Health check for smart ingestion service"""
    return {
        "status": "healthy",
        "service": "smart-ingestion",
        "features": [
            "file-signature-verification",
            "pdf-conversion",
            "opencv-preprocessing",
            "auto-crop",
            "deskewing"
        ]
    }


@router.delete("/cleanup")
async def cleanup_temp_files():
    """Clean up old temporary files"""
    try:
        smart_ingestion.cleanup_temp_files(max_age_hours=24)
        return {"message": "Cleanup completed successfully"}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Cleanup failed: {str(e)}"
        )
