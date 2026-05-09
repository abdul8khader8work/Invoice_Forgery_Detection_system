"""
Celery worker entry point for invoice scanning
Run with: celery -A workers.scan_worker worker -l info
"""
from tasks.celery_app import celery_app
import os

# Set worker name
os.environ.setdefault('CELERY_WORKER_NAME', 'scan_worker')

if __name__ == '__main__':
    celery_app.worker_main()
