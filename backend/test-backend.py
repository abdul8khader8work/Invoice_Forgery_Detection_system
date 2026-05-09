# Simple test to verify backend works
try:
    from app.core.config import settings
    print("✅ Config loaded successfully!")
    print(f"Database URL: {settings.database_url}")
    print(f"Host: {settings.host}:{settings.port}")
    
    # Test database
    from app.models.database import create_tables
    create_tables()
    print("✅ Database tables created!")
    
    # Test imports
    from app.services.ocr_service import OCRService
    from app.services.extraction_service import ExtractionService
    from app.services.validation_service import ValidationService
    from app.services.ml_service import MLService
    print("✅ All services imported successfully!")
    
    print("\n🎉 Backend is ready to start!")
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()

input("\nPress Enter to continue...")
