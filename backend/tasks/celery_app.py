"""
Celery application configuration for async task processing
Uses Redis as broker and result backend
"""
from celery import Celery
import os

# Get Redis URL from environment or use default
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Create Celery app
celery_app = Celery(
    'invoice_scanner',
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=['tasks.scan_tasks']
)

# Celery configuration
celery_app.conf.update(
    # Task settings
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone='UTC',
    enable_utc=True,
    
    # Task execution
    task_track_started=True,
    task_time_limit=300,  # 5 minutes max per task
    task_soft_time_limit=240,  # 4 minutes soft limit
    
    # Result settings
    result_expires=3600,  # Results expire after 1 hour
    result_backend=REDIS_URL,
    
    # Worker settings
    worker_prefetch_multiplier=1,  # Process one task at a time
    worker_max_tasks_per_child=50,  # Restart worker after 50 tasks
    
    # Retry settings
    task_default_retry_delay=60,  # Retry after 60 seconds
    task_max_retries=3,  # Max 3 retries
    
    # Rate limiting
    task_annotations={
        'tasks.scan_tasks.process_invoice_scan': {
            'rate_limit': '10/m',  # Max 10 scans per minute
        },
    },
    
    # Routing
    task_routes={
        'tasks.scan_tasks.process_invoice_scan': {'queue': 'scan'},
        'tasks.scan_tasks.batch_process_invoices': {'queue': 'batch'},
    },
    
    # Task queues
    task_queues={
        'scan': {
            'exchange': 'scan',
            'routing_key': 'scan',
        },
        'batch': {
            'exchange': 'batch',
            'routing_key': 'batch',
        },
    },
)

# Optional: Add health check
@celery_app.task(bind=True)
def health_check(self):
    """Health check task for Celery worker"""
    return {"status": "healthy", "worker": str(self.request.hostname)}
