"""
Batch Report API Endpoints
Provides endpoints for generating consolidated batch reports.
"""
from fastapi import APIRouter, HTTPException, Depends, BackgroundTasks
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from sqlalchemy.orm import Session
import json
import io

from app.services.batch_report_service import BatchReportService
from app.models.database import get_db

router = APIRouter(prefix="/api/batch-reports", tags=["batch-reports"])


class BatchReportRequest(BaseModel):
    batch_id: str
    invoice_ids: List[str]
    include_anomalies: bool = True
    include_validations: bool = True
    include_ml_scores: bool = True


class BatchReportResponse(BaseModel):
    batch_id: str
    generated_at: str
    total_invoices: int
    successful_scans: int
    failed_scans: int
    total_amount: float
    risk_distribution: dict
    anomalies_detected: int
    invoices: List[dict]
    pdf_url: Optional[str] = None


# In-memory storage for generated reports (for demo purposes)
# In production, this should be stored in database or file system
_report_cache = {}


@router.post("/generate", response_model=BatchReportResponse)
async def generate_batch_report(
    request: BatchReportRequest,
    db: Session = Depends(get_db)
):
    """
    Generate consolidated report for a batch of invoices.
    Aggregates individual scan results into single report.
    """
    try:
        service = BatchReportService(db)
        
        # Aggregate batch results
        batch_data = service.aggregate_batch_results(request.invoice_ids)
        
        # Generate PDF report
        pdf_bytes = service.generate_pdf_report(batch_data, request.batch_id)
        
        # Store PDF bytes in cache (in production, save to file system or S3)
        pdf_url = None
        if pdf_bytes:
            _report_cache[request.batch_id] = pdf_bytes
            pdf_url = f"/api/batch-reports/{request.batch_id}/download"
        
        # Build response
        response = BatchReportResponse(
            batch_id=request.batch_id,
            generated_at=datetime.now().isoformat(),
            total_invoices=batch_data['total_invoices'],
            successful_scans=batch_data['successful_scans'],
            failed_scans=batch_data['failed_scans'],
            total_amount=batch_data['total_amount'],
            risk_distribution=batch_data['risk_distribution'],
            anomalies_detected=batch_data['anomalies_detected'],
            invoices=batch_data['invoices'],
            pdf_url=pdf_url,
        )
        
        return response
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error generating batch report: {str(e)}"
        )


@router.get("/{batch_id}")
async def get_batch_report(batch_id: str, db: Session = Depends(get_db)):
    """
    Retrieve existing batch report by ID.
    Returns the cached report data.
    """
    if batch_id not in _report_cache:
        raise HTTPException(
            status_code=404,
            detail=f"Batch report {batch_id} not found"
        )
    
    return {
        "batch_id": batch_id,
        "status": "available",
        "download_url": f"/api/batch-reports/{batch_id}/download"
    }


@router.get("/{batch_id}/download")
async def download_batch_report_pdf(batch_id: str):
    """
    Download batch report as PDF.
    Returns the PDF file for the specified batch.
    """
    if batch_id not in _report_cache:
        raise HTTPException(
            status_code=404,
            detail=f"Batch report {batch_id} not found"
        )
    
    pdf_bytes = _report_cache[batch_id]
    
    # Return PDF file
    from fastapi.responses import Response
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename=batch_report_{batch_id}.pdf"
        }
    )


@router.delete("/{batch_id}")
async def delete_batch_report(batch_id: str):
    """
    Delete a cached batch report.
    """
    if batch_id not in _report_cache:
        raise HTTPException(
            status_code=404,
            detail=f"Batch report {batch_id} not found"
        )
    
    del _report_cache[batch_id]
    
    return {"message": f"Batch report {batch_id} deleted successfully"}
