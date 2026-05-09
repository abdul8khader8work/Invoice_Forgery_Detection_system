"""
Active Learning API Routes
FastAPI endpoints for the feedback loop and invoice processing
"""

import os
import uuid
import tempfile
from pathlib import Path
from typing import Optional, List, Dict, Any
from datetime import datetime
from fastapi import APIRouter, File, UploadFile, Form, HTTPException, Depends, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.models.database import get_db
from app.models.active_learning_models import (
    TemplateRegistry, ExtractionLog, SpatialCorrection
)
from app.services.template_registry import (
    TemplateRegistryManager, VendorFingerprint, FuzzyMatcher
)
from app.services.spatial_intelligence import SpatialIntelligenceEngine
from app.services.simple_extraction import SimpleInvoiceExtractor, extract_invoice
from app.services.coordinate_registry import get_coordinate_registry
from app.services.field_discovery import SmartExtractionEngine, extract_smart
from app.services.llm_extractor import get_groq_extractor

router = APIRouter(prefix="/active-learning", tags=["Active Learning"])


# ============================================================================
# Pydantic Models
# ============================================================================

class FieldCorrection(BaseModel):
    """Single field correction from user"""
    field_name: str
    original_value: str
    corrected_value: str
    original_bbox: Dict[str, float]  # {x, y, width, height}
    corrected_bbox: Dict[str, float]
    anchor_bbox: Optional[Dict[str, float]] = None


class RefineTemplateRequest(BaseModel):
    """Request to refine template based on user corrections"""
    file_id: str
    log_id: int
    style_tag: str
    corrections: List[FieldCorrection]
    corrected_by: Optional[str] = "user"


class RefineTemplateResponse(BaseModel):
    """Response from template refinement"""
    success: bool
    template_id: int
    fields_updated: List[str]
    new_confidence_score: float
    spatial_deltas_applied: Dict[str, Dict[str, int]]


class ProcessInvoiceRequest(BaseModel):
    """Optional parameters for invoice processing"""
    style_hint: Optional[str] = None
    force_new_template: bool = False
    use_llm: bool = True  # Default to LLM extraction


class ProcessInvoiceResponse(BaseModel):
    """Complete invoice processing response"""
    success: bool
    file_id: str
    vendor_fingerprint: str
    template_id: int
    style_tag: str
    is_new_template: bool
    extracted_data: Dict[str, Any]
    confidence_scores: Dict[str, float]
    overall_confidence: float
    needs_verification: bool
    verification_fields: List[str]
    processing_time_ms: int
    log_id: int
    validation_warnings: List[Dict[str, Any]] = []
    field_coverage: Dict[str, Any] = {}


class TemplateInfo(BaseModel):
    """Template information for listing"""
    id: int
    style_tag: str
    confidence_score: float
    extraction_count: int
    correction_count: int
    created_at: datetime
    last_used_at: Optional[datetime]


# ============================================================================
# Feedback Loop Endpoint (The Core Learning Mechanism)
# ============================================================================

@router.post("/templates/refine", response_model=RefineTemplateResponse)
async def refine_template(
    request: RefineTemplateRequest,
    db: Session = Depends(get_db)
):
    """
    The CRITICAL learning endpoint.
    
    When a user corrects field positions in the Flutter UI,
    this endpoint calculates the spatial delta and updates the template.
    
    Example: User moves "Total" field 50px to the right →
    We save that +50px offset for that vendor's "total" field.
    """
    
    # Retrieve the extraction log
    log = db.query(ExtractionLog).get(request.log_id)
    if not log:
        raise HTTPException(status_code=404, detail=f"Log {request.log_id} not found")
    
    # Get or create template
    template_manager = TemplateRegistryManager(db)
    template = db.query(TemplateRegistry).get(log.template_id)
    
    if not template:
        # Create new template if none exists
        fp = VendorFingerprint(**log.vendor_fingerprint)
        template, _ = template_manager.get_or_create_template(fp, request.style_tag)
        log.template_id = template.id
    
    fields_updated = []
    spatial_deltas = {}
    
    # Process each correction
    for correction in request.corrections:
        # Calculate spatial delta
        delta_x = correction.corrected_bbox['x'] - (correction.anchor_bbox or correction.original_bbox)['x']
        delta_y = correction.corrected_bbox['y'] - (correction.anchor_bbox or correction.original_bbox)['y']
        
        # Update template field map
        field_map = template.field_map or {}
        field_config = field_map.get(correction.field_name, {})
        
        # Store learned offset
        field_config['learned_offset_x'] = delta_x
        field_config['learned_offset_y'] = delta_y
        field_config['extraction_count'] = field_config.get('extraction_count', 0) + 1
        field_config['last_corrected_at'] = datetime.utcnow().isoformat()
        
        field_map[correction.field_name] = field_config
        fields_updated.append(correction.field_name)
        
        spatial_deltas[correction.field_name] = {
            'delta_x': int(delta_x),
            'delta_y': int(delta_y)
        }
        
        # Log the correction
        spatial_correction = SpatialCorrection(
            log_id=request.log_id,
            template_id=template.id,
            field_name=correction.field_name,
            original_bbox=correction.original_bbox,
            original_value=correction.original_value,
            corrected_bbox=correction.corrected_bbox,
            corrected_value=correction.corrected_value,
            delta_x=int(delta_x),
            delta_y=int(delta_y),
            was_applied_to_template=True
        )
        db.add(spatial_correction)
    
    # Update template
    template.field_map = field_map
    template.correction_count += len(request.corrections)
    template.confidence_score = min(1.0, template.confidence_score + (0.02 * len(request.corrections)))
    template.last_corrected_at = datetime.utcnow()
    
    # Update log
    log.was_corrected = True
    log.corrected_data = {
        'corrections': [
            {
                'field': c.field_name,
                'from': c.original_value,
                'to': c.corrected_value
            }
            for c in request.corrections
        ],
        'corrected_by': request.corrected_by,
        'correction_time': datetime.utcnow().isoformat()
    }
    
    db.commit()
    
    return RefineTemplateResponse(
        success=True,
        template_id=template.id,
        fields_updated=fields_updated,
        new_confidence_score=template.confidence_score,
        spatial_deltas_applied=spatial_deltas
    )


# ============================================================================
# Main Invoice Processing Endpoint
# ============================================================================

@router.post("/process-invoice", response_model=ProcessInvoiceResponse)
async def process_invoice(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    style_hint: Optional[str] = Form(None),
    force_new_template: bool = Form(False),
    use_llm: bool = Form(True),
    db: Session = Depends(get_db)
):
    """
    Process invoice with LLM or OCR extraction
    
    Features:
    - LLM extraction (default): Uses Groq API for high accuracy
    - PDF → Image at 300 DPI (no PyMuPDF)
    - Mathematical validation (subtotal + tax == total)
    - Returns validation warnings in response
    
    Get free API key from: https://console.groq.com/keys
    Set as environment variable: GROQ_API_KEY
    
    Example Warning:
    {
        "type": "mathematical_inconsistency",
        "severity": "high",
        "message": "subtotal ($10.00) + tax ($2.00) = $12.00 ≠ total ($15.00)"
    }
    """
    
    # Validate file
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided")
    
    allowed_extensions = {'.jpg', '.jpeg', '.png', '.pdf'}
    file_ext = Path(file.filename).suffix.lower()
    
    if file_ext not in allowed_extensions:
        raise HTTPException(
            status_code=400,
            detail=f"File type {file_ext} not allowed. Use: {allowed_extensions}"
        )
    
    # Generate file ID
    file_id = str(uuid.uuid4())
    
    # Save uploaded file temporarily
    temp_dir = tempfile.mkdtemp()
    file_path = os.path.join(temp_dir, file.filename)
    
    try:
        content = await file.read()
        
        if len(content) == 0:
            raise HTTPException(status_code=400, detail="Empty file")
        
        if len(content) > 10 * 1024 * 1024:  # 10MB limit
            raise HTTPException(status_code=400, detail="File too large (max 10MB)")
        
        with open(file_path, "wb") as f:
            f.write(content)
        
        # Convert PDF to image if needed
        if file_ext == '.pdf':
            from pdf2image import convert_from_path
            images = convert_from_path(file_path, dpi=200, first_page=1, last_page=1)
            if images:
                image_path = os.path.join(temp_dir, f"{file_id}.png")
                images[0].save(image_path, 'PNG')
            else:
                raise HTTPException(status_code=400, detail="Could not convert PDF")
        else:
            image_path = file_path
        
        # Try LLM extraction first (if enabled)
        if use_llm:
            try:
                logger.info("Using LLM extraction via Groq API")
                llm_extractor = get_groq_extractor()
                result = llm_extractor.extract_and_validate(image_path)
                
                response = {
                    'success': True,
                    'file_id': file_id,
                    'vendor_fingerprint': result['extracted_data'].get('vendor_name', 'unknown'),
                    'template_id': 0,
                    'style_tag': style_hint or 'llm_extracted',
                    'is_new_template': True,
                    'extracted_data': result['extracted_data'],
                    'confidence_scores': {},
                    'overall_confidence': result.get('confidence', 0.8),
                    'needs_verification': result.get('needs_verification', False),
                    'verification_fields': [w.get('field') for w in result.get('validation_warnings', [])],
                    'processing_time_ms': 0,  # Will be measured
                    'validation_warnings': result.get('validation_warnings', []),
                    'field_coverage': {},
                    'log_id': 0,
                    'extraction_method': 'llm_groq'
                }
                
                return ProcessInvoiceResponse(**response)
                
            except Exception as e:
                logger.warning(f"LLM extraction failed: {e}. Falling back to OCR extraction.")
        
        # Fallback to OCR extraction
        logger.info("Using OCR extraction (field discovery)")
        extractor = SimpleInvoiceExtractor(db)
        result = extractor.extract_invoice(image_path, style_hint)
        
        # Build response
        response = {
            'success': True,
            'file_id': file_id,
            'vendor_fingerprint': result.get('style_tag', 'unknown'),
            'template_id': 0,
            'style_tag': result.get('style_tag', 'generic'),
            'is_new_template': result.get('is_new_template', True),
            'extracted_data': result.get('extracted_data', {}),
            'confidence_scores': {},
            'overall_confidence': result.get('overall_confidence', 0),
            'needs_verification': result.get('needs_verification', True),
            'verification_fields': [w.get('field', 'unknown') for w in result.get('validation_warnings', [])],
            'processing_time_ms': result.get('processing_time_ms', 0),
            'validation_warnings': result.get('validation_warnings', []),
            'field_coverage': result.get('field_coverage', {}),
            'log_id': 0,
            'extraction_method': 'ocr_field_discovery'
        }
        
        return ProcessInvoiceResponse(**response)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Processing error: {e}")
        raise HTTPException(status_code=500, detail=f"Processing error: {str(e)}")
    
    finally:
        # Cleanup
        if os.path.exists(file_path):
            os.remove(file_path)
        if 'image_path' in locals() and image_path != file_path and os.path.exists(image_path):
            os.remove(image_path)
        if os.path.exists(temp_dir):
            os.rmdir(temp_dir)


# ============================================================================
# Template Management Endpoints
# ============================================================================

@router.get("/templates", response_model=List[TemplateInfo])
async def list_templates(
    min_confidence: float = 0.0,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """List all learned templates ordered by confidence"""
    
    templates = db.query(TemplateRegistry).filter(
        TemplateRegistry.confidence_score >= min_confidence,
        TemplateRegistry.is_active == True
    ).order_by(TemplateRegistry.confidence_score.desc()).limit(limit).all()
    
    return [
        TemplateInfo(
            id=t.id,
            style_tag=t.style_tag,
            confidence_score=t.confidence_score,
            extraction_count=t.extraction_count,
            correction_count=t.correction_count,
            created_at=t.created_at,
            last_used_at=t.last_used_at
        )
        for t in templates
    ]


@router.get("/templates/{template_id}")
async def get_template(template_id: int, db: Session = Depends(get_db)):
    """Get detailed template information including field map"""
    
    template = db.query(TemplateRegistry).get(template_id)
    if not template:
        raise HTTPException(status_code=404, detail="Template not found")
    
    return {
        'id': template.id,
        'vendor_fingerprint': template.vendor_fingerprint,
        'style_tag': template.style_tag,
        'identifiers': template.identifiers,
        'field_map': template.field_map,
        'confidence_score': template.confidence_score,
        'extraction_count': template.extraction_count,
        'correction_count': template.correction_count,
        'created_at': template.created_at.isoformat(),
        'last_used_at': template.last_used_at.isoformat() if template.last_used_at else None,
        'last_corrected_at': template.last_corrected_at.isoformat() if template.last_corrected_at else None
    }


@router.put("/templates/{template_id}/field-map")
async def update_field_map(
    template_id: int,
    field_updates: Dict[str, Dict[str, Any]],
    db: Session = Depends(get_db)
):
    """
    Manually update a template's field map
    Useful for administrative corrections
    """
    
    template = db.query(TemplateRegistry).get(template_id)
    if not template:
        raise HTTPException(status_code=404, detail="Template not found")
    
    field_map = template.field_map or {}
    
    for field_name, updates in field_updates.items():
        if field_name in field_map:
            field_map[field_name].update(updates)
        else:
            field_map[field_name] = updates
    
    template.field_map = field_map
    template.last_corrected_at = datetime.utcnow()
    db.commit()
    
    return {
        'success': True,
        'template_id': template_id,
        'updated_fields': list(field_updates.keys())
    }


# ============================================================================
# Extraction Log & Analytics Endpoints
# ============================================================================

@router.get("/extraction-logs/{file_id}")
async def get_extraction_log(file_id: str, db: Session = Depends(get_db)):
    """Get extraction log by file ID for displaying correction UI"""
    
    log = db.query(ExtractionLog).filter(ExtractionLog.file_id == file_id).first()
    if not log:
        raise HTTPException(status_code=404, detail="Extraction log not found")
    
    return {
        'log_id': log.id,
        'file_id': log.file_id,
        'template_id': log.template_id,
        'template_match_score': log.template_match_score,
        'extracted_data': log.extracted_data,
        'confidence_scores': log.confidence_scores,
        'raw_ocr_output': log.raw_ocr_output,
        'was_corrected': log.was_corrected,
        'corrected_data': log.corrected_data,
        'processing_time_ms': log.processing_time_ms,
        'created_at': log.created_at.isoformat()
    }


@router.get("/analytics/template-performance")
async def get_template_performance(
    days: int = 30,
    db: Session = Depends(get_db)
):
    """Get analytics on template performance"""
    
    from datetime import datetime, timedelta
    
    cutoff_date = datetime.utcnow() - timedelta(days=days)
    
    # Get extraction stats
    total_extractions = db.query(ExtractionLog).filter(
        ExtractionLog.created_at >= cutoff_date
    ).count()
    
    corrected_extractions = db.query(ExtractionLog).filter(
        ExtractionLog.created_at >= cutoff_date,
        ExtractionLog.was_corrected == True
    ).count()
    
    # Get per-template stats
    from sqlalchemy import func
    
    template_stats = db.query(
        TemplateRegistry.id,
        TemplateRegistry.style_tag,
        TemplateRegistry.confidence_score,
        func.count(ExtractionLog.id).label('extraction_count'),
        func.avg(ExtractionLog.template_match_score).label('avg_match_score')
    ).outerjoin(
        ExtractionLog, 
        TemplateRegistry.id == ExtractionLog.template_id
    ).filter(
        ExtractionLog.created_at >= cutoff_date
    ).group_by(TemplateRegistry.id).all()
    
    return {
        'period_days': days,
        'total_extractions': total_extractions,
        'corrected_extractions': corrected_extractions,
        'correction_rate': corrected_extractions / total_extractions if total_extractions > 0 else 0,
        'template_performance': [
            {
                'template_id': t.id,
                'style_tag': t.style_tag,
                'confidence_score': t.confidence_score,
                'extraction_count': t.extraction_count,
                'avg_match_score': float(t.avg_match_score) if t.avg_match_score else 0
            }
            for t in template_stats
        ]
    }


# ============================================================================
# Utility Endpoints
# ============================================================================

@router.post("/utils/fuzzy-match")
async def test_fuzzy_match(text1: str, text2: str):
    """Test fuzzy string matching (for debugging)"""
    
    matcher = FuzzyMatcher()
    distance = matcher.levenshtein_distance(text1, text2)
    similarity = matcher.similarity_ratio(text1, text2)
    
    return {
        'text1': text1,
        'text2': text2,
        'levenshtein_distance': distance,
        'similarity_ratio': similarity,
        'is_match': similarity > 0.8
    }


@router.post("/utils/extract-fingerprint")
async def extract_fingerprint(ocr_text: str):
    """Test vendor fingerprint extraction (for debugging)"""
    
    # Mock OCR boxes from text
    boxes = [{'text': line, 'x': 0, 'y': 0, 'width': 100, 'height': 20} 
             for line in ocr_text.split('\n')]
    
    manager = TemplateRegistryManager()
    fp = manager.extract_vendor_fingerprint(boxes)
    
    return {
        'fingerprint': fp.__dict__,
        'hash': fp.compute_hash()
    }
