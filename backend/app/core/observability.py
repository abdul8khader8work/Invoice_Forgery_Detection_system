"""
Observability module for metrics, structured logging, and health checks
Provides Prometheus metrics, JSON logging with correlation IDs, and enhanced health checks
"""
import json
import logging
import time
import uuid
from datetime import datetime
from typing import Optional, Dict, Any
from functools import wraps
from fastapi import Request, Response
from fastapi.responses import JSONResponse
import prometheus_client as prom
from prometheus_client import Counter, Histogram, Gauge, Info
from contextvars import ContextVar

# Context variable for correlation ID
correlation_id_ctx: ContextVar[Optional[str]] = ContextVar('correlation_id', default=None)

# Prometheus Metrics
request_count = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

request_duration = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint']
)

scan_duration = Histogram(
    'scan_duration_seconds',
    'Invoice scan duration in seconds',
    ['risk_level']
)

error_count = Counter(
    'errors_total',
    'Total errors',
    ['error_type', 'endpoint']
)

active_scans = Gauge(
    'active_scans',
    'Number of currently active scans'
)

feature_flag_evaluations = Counter(
    'feature_flag_evaluations_total',
    'Feature flag evaluations',
    ['flag_name', 'result']
)

app_info = Info(
    'app_info',
    'Application information'
)

# Initialize app info
app_info.info({
    'version': '1.0.0',
    'name': 'invoice-forgery-detection'
})


class StructuredLogger:
    """Structured JSON logger with correlation ID support"""
    
    def __init__(self, name: str):
        self.logger = logging.getLogger(name)
        self.logger.setLevel(logging.INFO)
        
        # Remove existing handlers
        self.logger.handlers.clear()
        
        # Add JSON handler
        handler = logging.StreamHandler()
        handler.setFormatter(JSONFormatter())
        self.logger.addHandler(handler)
    
    def _log(self, level: str, message: str, extra: Optional[Dict] = None):
        correlation_id = correlation_id_ctx.get()
        log_data = {
            'timestamp': datetime.utcnow().isoformat(),
            'level': level,
            'message': message,
            'correlation_id': correlation_id,
            **(extra or {})
        }
        self.logger.log(getattr(logging, level), json.dumps(log_data))
    
    def info(self, message: str, extra: Optional[Dict] = None):
        self._log('INFO', message, extra)
    
    def warning(self, message: str, extra: Optional[Dict] = None):
        self._log('WARNING', message, extra)
    
    def error(self, message: str, extra: Optional[Dict] = None):
        self._log('ERROR', message, extra)
    
    def debug(self, message: str, extra: Optional[Dict] = None):
        self._log('DEBUG', message, extra)


class JSONFormatter(logging.Formatter):
    """Custom JSON formatter for structured logging"""
    
    def format(self, record):
        log_obj = {
            'timestamp': datetime.utcnow().isoformat(),
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
        }
        
        if hasattr(record, 'correlation_id'):
            log_obj['correlation_id'] = record.correlation_id
        
        if record.exc_info:
            log_obj['exception'] = self.formatException(record.exc_info)
        
        return json.dumps(log_obj)


def get_correlation_id() -> str:
    """Get or generate correlation ID"""
    cid = correlation_id_ctx.get()
    if cid is None:
        cid = str(uuid.uuid4())
        correlation_id_ctx.set(cid)
    return cid


def log_feature_flag(flag_name: str, result: bool, logger: StructuredLogger):
    """Log feature flag evaluation for audit trail"""
    logger.info(
        f"Feature flag evaluated: {flag_name} = {result}",
        extra={
            'flag_name': flag_name,
            'flag_result': result,
            'event_type': 'feature_flag_evaluation'
        }
    )
    feature_flag_evaluations.labels(flag_name=flag_name, result=str(result)).inc()


def track_request_metrics(method: str, endpoint: str, status: int, duration: float):
    """Track request metrics"""
    request_count.labels(method=method, endpoint=endpoint, status=status).inc()
    request_duration.labels(method=method, endpoint=endpoint).observe(duration)


def track_error(error_type: str, endpoint: str):
    """Track error metrics"""
    error_count.labels(error_type=error_type, endpoint=endpoint).inc()


def track_scan_duration(risk_level: str, duration: float):
    """Track scan duration metrics"""
    scan_duration.labels(risk_level=risk_level).observe(duration)


def increment_active_scans():
    """Increment active scans gauge"""
    active_scans.inc()


def decrement_active_scans():
    """Decrement active scans gauge"""
    active_scans.dec()


class ObservabilityMiddleware:
    """Middleware for automatic observability"""
    
    def __init__(self, app):
        self.app = app
        self.logger = StructuredLogger('observability')
    
    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            await self.app(scope, receive, send)
            return
        
        # Generate or extract correlation ID
        headers = dict(scope.get('headers', []))
        correlation_id = headers.get(b'x-correlation-id', b'').decode()
        
        if not correlation_id:
            correlation_id = str(uuid.uuid4())
        
        correlation_id_ctx.set(correlation_id)
        
        # Track request start time
        start_time = time.time()
        
        # Intercept send to capture status
        async def send_wrapper(message):
            if message['type'] == 'http.response.start':
                status = message['status']
                duration = time.time() - start_time
                method = scope['method']
                path = scope['path']
                
                track_request_metrics(method, path, status, duration)
                
                self.logger.info(
                    f"{method} {path} - Status: {status}",
                    extra={
                        'method': method,
                        'path': path,
                        'status': status,
                        'duration': duration,
                        'correlation_id': correlation_id
                    }
                )
            
            # Add correlation ID to response headers
            if message['type'] == 'http.response.start':
                headers = message.get('headers', [])
                headers.append((b'x-correlation-id', correlation_id.encode()))
                message['headers'] = headers
            
            await send(message)
        
        await self.app(scope, receive, send_wrapper)


class LivenessProbe:
    """Liveness probe - checks if the app is running"""
    
    @staticmethod
    def check() -> Dict[str, Any]:
        return {
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat()
        }


class ReadinessProbe:
    """Readiness probe - checks if the app is ready to serve traffic"""
    
    @staticmethod
    def check() -> Dict[str, Any]:
        checks = {
            'database': False,
            'ocr_service': False,
            'ml_service': False,
        }
        
        try:
            # Check database connection
            from app.models.database import get_db
            db = next(get_db())
            db.execute("SELECT 1")
            checks['database'] = True
        except Exception as e:
            pass
        
        try:
            # Check OCR service
            from app.services.ocr_service import OCRService
            ocr = OCRService()
            if ocr.is_available():
                checks['ocr_service'] = True
        except Exception as e:
            pass
        
        try:
            # Check ML service
            from app.services.ml_service import MLService
            ml = MLService()
            checks['ml_service'] = True
        except Exception as e:
            pass
        
        all_healthy = all(checks.values())
        
        return {
            'status': 'ready' if all_healthy else 'not_ready',
            'checks': checks,
            'timestamp': datetime.utcnow().isoformat()
        }


def metrics_endpoint():
    """Prometheus metrics endpoint"""
    from prometheus_client import generate_latest
    from fastapi.responses import Response
    
    return Response(
        content=generate_latest(),
        media_type="text/plain; version=0.0.4; charset=utf-8"
    )


# Decorator for tracking function execution time
def track_execution(metric_name: str, labels: Optional[Dict] = None):
    """Decorator to track function execution time"""
    def decorator(func):
        @wraps(func)
        async def async_wrapper(*args, **kwargs):
            start_time = time.time()
            try:
                result = await func(*args, **kwargs)
                duration = time.time() - start_time
                # Track success metric
                return result
            except Exception as e:
                duration = time.time() - start_time
                # Track error metric
                raise
        
        @wraps(func)
        def sync_wrapper(*args, **kwargs):
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                duration = time.time() - start_time
                # Track success metric
                return result
            except Exception as e:
                duration = time.time() - start_time
                # Track error metric
                raise
        
        if asyncio.iscoroutinefunction(func):
            return async_wrapper
        else:
            return sync_wrapper
    
    return decorator


import asyncio
