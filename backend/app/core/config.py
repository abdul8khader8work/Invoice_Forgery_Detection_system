from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # Database - PostgreSQL
    database_url: str = "postgresql://postgres:password@localhost:5432/invoice_system"
    
    # OCR Configuration
    tesseract_cmd: str = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    easyocr_enabled: bool = False  # Disabled due to PyTorch DLL issues on Windows
    easyocr_langs: list = ['en']
    
    # File Upload
    max_file_size: int = 10 * 1024 * 1024  # 10MB
    upload_dir: str = "uploads"
    
    # ML Configuration
    model_path: str = "models/isolation_forest.pkl"
    anomaly_threshold: float = 0.1
    
    # Validation Rules
    tax_rate_tolerance: float = 0.05  # 5% tolerance
    future_date_days: int = 7  # Allow invoices up to 7 days in future
    
    # API Configuration
    api_v1_str: str = "/api"
    
    # Groq AI Configuration
    groq_api_key: Optional[str] = None
    
    # Celery & Redis Configuration
    redis_url: str = "redis://localhost:6379/0"
    celery_broker_url: str = "redis://localhost:6379/0"
    celery_result_backend: str = "redis://localhost:6379/0"
    enable_celery: bool = False  # Feature flag to enable Celery (fallback to BackgroundTasks)
    
    # Development settings
    debug: bool = True
    host: str = "0.0.0.0"
    port: int = 8000
    
    model_config = {
        'protected_namespaces': ('settings_',)
    }

settings = Settings()
