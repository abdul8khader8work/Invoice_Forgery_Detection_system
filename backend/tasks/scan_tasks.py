"""
Celery tasks for invoice scanning and processing
Migrates from BackgroundTasks to Celery for production async processing
"""
from celery import shared_task
from celery.utils.log import get_task_logger
import os
from pathlib import Path
from datetime import datetime
import traceback

logger = get_task_logger(__name__)

# Import after app initialization to avoid circular imports
# These will be imported when the task is executed
def get_ocr_service():
    from app.services.ocr_service import OCRService
    return OCRService()

def get_extraction_service():
    from app.services.extraction_service import ExtractionService
    return ExtractionService()

def get_validation_service():
    from app.services.validation_service import ValidationService
    return ValidationService()

def get_detection_service():
    from app.services.detection_service import ForgeryDetectionService, get_forgery_detection_service
    return get_forgery_detection_service()


@shared_task(
    name='tasks.scan_tasks.process_invoice_scan',
    bind=True,
    max_retries=3,
    default_retry_delay=60,
)
def process_invoice_scan(self, file_path: str, scan_id: str):
    """
    Process a single invoice scan with OCR, extraction, validation, and forgery detection
    
    Args:
        file_path: Path to the invoice file
        scan_id: Unique identifier for this scan
        
    Returns:
        Dict with scan results including extracted data, validation, and forgery detection
    """
    logger.info(f"Processing invoice scan: {scan_id} from {file_path}")
    
    try:
        # Step 1: OCR Extraction
        logger.info(f"Step 1: OCR extraction for {scan_id}")
        ocr_service = get_ocr_service()
        ocr_result = ocr_service.extract_text(Path(file_path))
        
        # Step 2: Data Extraction
        logger.info(f"Step 2: Data extraction for {scan_id}")
        extraction_service = get_extraction_service()
        extracted_data = extraction_service.extract_from_ocr_text(
            ocr_result['text']
        )
        
        # Step 3: Validation
        logger.info(f"Step 3: Validation for {scan_id}")
        validation_service = get_validation_service()
        validation_result = validation_service.validate_invoice(extracted_data)
        
        # Step 4: Forgery Detection
        logger.info(f"Step 4: Forgery detection for {scan_id}")
        detection_service = get_detection_service()
        forgery_result = detection_service.detect_forgery(
            extracted_data,
            validation_result
        )
        
        # Compile results
        result = {
            'scan_id': scan_id,
            'status': 'completed',
            'ocr_result': ocr_result,
            'extracted_data': extracted_data,
            'validation_result': validation_result,
            'forgery_result': forgery_result,
            'processed_at': datetime.utcnow().isoformat(),
            'file_path': file_path,
        }
        
        logger.info(f"Successfully completed scan: {scan_id}")
        return result
        
    except Exception as e:
        logger.error(f"Error processing scan {scan_id}: {str(e)}")
        logger.error(traceback.format_exc())
        
        # Retry with exponential backoff
        raise self.retry(exc=e, countdown=60 * (self.request.retries + 1))


@shared_task(
    name='tasks.scan_tasks.batch_process_invoices',
    bind=True,
)
def batch_process_invoices(self, file_paths: list, batch_id: str):
    """
    Process multiple invoices in batch
    
    Args:
        file_paths: List of file paths to process
        batch_id: Unique identifier for this batch
        
    Returns:
        Dict with batch results including individual scan results
    """
    logger.info(f"Processing batch: {batch_id} with {len(file_paths)} files")
    
    results = []
    failed = []
    
    for i, file_path in enumerate(file_paths):
        scan_id = f"{batch_id}_{i}"
        
        try:
            # Chain individual scan tasks
            result = process_invoice_scan.delay(file_path, scan_id)
            results.append({
                'scan_id': scan_id,
                'task_id': result.id,
                'status': 'queued',
                'file_path': file_path,
            })
        except Exception as e:
            logger.error(f"Failed to queue scan {scan_id}: {str(e)}")
            failed.append({
                'scan_id': scan_id,
                'error': str(e),
                'file_path': file_path,
            })
    
    return {
        'batch_id': batch_id,
        'total_files': len(file_paths),
        'queued': len(results),
        'failed': len(failed),
        'results': results,
        'failed_files': failed,
        'started_at': datetime.utcnow().isoformat(),
    }


@shared_task(
    name='tasks.scan_tasks.cleanup_old_scans',
    bind=True,
)
def cleanup_old_scans(self, days_old: int = 30):
    """
    Cleanup old scan results and temporary files
    
    Args:
        days_old: Delete scans older than this many days
    """
    logger.info(f"Cleaning up scans older than {days_old} days")
    
    try:
        from app.models.database import get_db, Invoice
        from datetime import timedelta
        from sqlalchemy import delete
        
        db = next(get_db())
        cutoff_date = datetime.utcnow() - timedelta(days=days_old)
        
        # Delete old invoices from database
        delete_stmt = delete(Invoice).where(Invoice.created_at < cutoff_date)
        result = db.execute(delete_stmt)
        db.commit()
        
        deleted_count = result.rowcount
        logger.info(f"Deleted {deleted_count} old scan records")
        
        # Cleanup old files from uploads directory
        uploads_dir = Path("uploads")
        if uploads_dir.exists():
            deleted_files = 0
            for file in uploads_dir.glob("*"):
                if file.is_file():
                    file_age = datetime.now() - datetime.fromtimestamp(file.stat().st_mtime)
                    if file_age.days > days_old:
                        file.unlink()
                        deleted_files += 1
            
            logger.info(f"Deleted {deleted_files} old files from uploads directory")
        
        return {
            'status': 'completed',
            'deleted_records': deleted_count,
            'deleted_files': deleted_files if 'deleted_files' in locals() else 0,
        }
        
    except Exception as e:
        logger.error(f"Error during cleanup: {str(e)}")
        raise


@shared_task(
    name='tasks.scan_tasks.generate_analytics',
    bind=True,
)
def generate_analytics(self, time_range: str = '30d'):
    """
    Generate analytics data for dashboard
    
    Args:
        time_range: Time range for analytics (7d, 30d, 90d)
    """
    logger.info(f"Generating analytics for time range: {time_range}")
    
    try:
        from app.models.database import get_db, Invoice
        from datetime import timedelta
        from sqlalchemy import func, and_
        
        db = next(get_db())
        
        # Calculate date range
        if time_range == '7d':
            start_date = datetime.utcnow() - timedelta(days=7)
        elif time_range == '90d':
            start_date = datetime.utcnow() - timedelta(days=90)
        else:  # default 30d
            start_date = datetime.utcnow() - timedelta(days=30)
        
        # Query analytics data
        total_scans = db.query(func.count(Invoice.id)).filter(
            Invoice.created_at >= start_date
        ).scalar()
        
        high_risk = db.query(func.count(Invoice.id)).filter(
            and_(
                Invoice.created_at >= start_date,
                Invoice.risk_level == 'high'
            )
        ).scalar()
        
        medium_risk = db.query(func.count(Invoice.id)).filter(
            and_(
                Invoice.created_at >= start_date,
                Invoice.risk_level == 'medium'
            )
        ).scalar()
        
        low_risk = db.query(func.count(Invoice.id)).filter(
            and_(
                Invoice.created_at >= start_date,
                Invoice.risk_level == 'low'
            )
        ).scalar()
        
        # Average confidence
        avg_confidence = db.query(func.avg(Invoice.confidence)).filter(
            Invoice.created_at >= start_date
        ).scalar() or 0.0
        
        result = {
            'time_range': time_range,
            'total_scans': total_scans,
            'high_risk_scans': high_risk,
            'medium_risk_scans': medium_risk,
            'low_risk_scans': low_risk,
            'average_confidence': float(avg_confidence),
            'generated_at': datetime.utcnow().isoformat(),
        }
        
        logger.info(f"Analytics generated: {result}")
        return result
        
    except Exception as e:
        logger.error(f"Error generating analytics: {str(e)}")
        raise
