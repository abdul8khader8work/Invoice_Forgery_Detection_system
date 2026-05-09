from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Text, Boolean, JSON
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime

from app.core.config import settings

Base = declarative_base()

class Invoice(Base):
    __tablename__ = "invoices"
    
    id = Column(Integer, primary_key=True, index=True)
    file_id = Column(String, unique=True, index=True)
    filename = Column(String)
    vendor_name = Column(String, nullable=True)
    invoice_number = Column(String, nullable=True)
    invoice_date = Column(String, nullable=True)
    subtotal = Column(Float, nullable=True)
    tax = Column(Float, nullable=True)
    total = Column(Float, nullable=True)
    risk_score = Column(Float)
    risk_level = Column(String)
    reasoning = Column(Text)
    needs_verification = Column(Boolean, default=False)
    verified = Column(Boolean, default=False)
    # Edit/approve/verify tracking fields
    edited_by = Column(String, nullable=True)
    approved_by = Column(String, nullable=True)
    approved_at = Column(DateTime, nullable=True)
    verified_by = Column(String, nullable=True)
    verified_at = Column(DateTime, nullable=True)
    verification_notes = Column(Text, nullable=True)
    # JSON fields for storing complex data
    extracted_data = Column(JSON, nullable=True)
    validation_results = Column(JSON, nullable=True)
    ml_results = Column(JSON, nullable=True)
    verification_fields = Column(JSON, nullable=True)
    processing_time = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class AuditLog(Base):
    __tablename__ = "audit_logs"
    
    id = Column(Integer, primary_key=True, index=True)
    file_id = Column(String, index=True)
    action = Column(String)  # scan, verify, export
    details = Column(Text)
    user_id = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

# Database setup - PostgreSQL with connection pooling
# ✅ INCREASED: Pool size to handle concurrent Flutter app requests
engine = create_engine(
    settings.database_url,
    pool_size=20,              # ✅ Increased from 10 to 20 (permanent connections)
    max_overflow=30,           # ✅ Increased from 20 to 30 (overflow connections)
    pool_timeout=60,           # ✅ NEW: Wait up to 60 seconds for available connection
    pool_pre_ping=True,        # Verify connections before using
    pool_recycle=300,          # Recycle connections after 5 minutes
    echo=False                 # Set to True for SQL debugging
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def create_tables():
    Base.metadata.create_all(bind=engine)
    
    # Create default admin user if not exists
    from app.models.user import User
    from passlib.context import CryptContext
    
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    
    db = SessionLocal()
    try:
        existing_admin = db.query(User).filter(User.email == 'admin@invoiceguard.com').first()
        if not existing_admin:
            admin_user = User(
                email='admin@invoiceguard.com',
                hashed_password=pwd_context.hash('admin123'),
                full_name='Admin User',
                is_active=True,
                is_admin=True
            )
            db.add(admin_user)
            db.commit()
            print("✅ Default admin user created: admin@invoiceguard.com / admin123")
        else:
            print("ℹ️ Admin user already exists")
    finally:
        db.close()
