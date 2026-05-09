"""
SQLAlchemy Models for Active Learning System
"""

from sqlalchemy import Column, Integer, String, Float, DateTime, Text, Boolean, ForeignKey, JSON
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime

Base = declarative_base()


class TemplateRegistry(Base):
    """Stores learned vendor templates with spatial field mappings"""
    __tablename__ = "template_registry"
    
    id = Column(Integer, primary_key=True)
    vendor_fingerprint = Column(String(64), unique=True, nullable=False, index=True)
    style_tag = Column(String(100))
    
    # JSON fields
    identifiers = Column(JSON, default=dict)  # GSTIN, VAT, etc.
    field_map = Column(JSON, nullable=False, default=dict)  # Spatial relationships
    
    # Metadata
    confidence_score = Column(Float, default=0.0)
    extraction_count = Column(Integer, default=0)
    correction_count = Column(Integer, default=0)
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    last_used_at = Column(DateTime)
    last_corrected_at = Column(DateTime)
    
    # Soft delete
    is_active = Column(Boolean, default=True)
    
    # Relationships
    identifiers_rel = relationship("VendorIdentifier", back_populates="template", cascade="all, delete-orphan")
    extraction_logs = relationship("ExtractionLog", back_populates="template")


class VendorIdentifier(Base):
    """Individual vendor identifiers for reverse lookup"""
    __tablename__ = "vendor_identifiers"
    
    id = Column(Integer, primary_key=True)
    template_id = Column(Integer, ForeignKey("template_registry.id"), nullable=False)
    
    identifier_type = Column(String(50), nullable=False)  # gstin, vat, email, phone
    identifier_value = Column(String(100), nullable=False, index=True)
    
    # Relationship
    template = relationship("TemplateRegistry", back_populates="identifiers_rel")


class ExtractionLog(Base):
    """Audit trail for every extraction attempt"""
    __tablename__ = "extraction_logs"
    
    id = Column(Integer, primary_key=True)
    file_id = Column(String(36), nullable=False, index=True)
    template_id = Column(Integer, ForeignKey("template_registry.id"), nullable=True)
    
    # OCR data
    ocr_engine = Column(String(50), default='paddleocr')
    raw_ocr_output = Column(JSON)
    
    # Extraction results
    extracted_data = Column(JSON)
    confidence_scores = Column(JSON)
    
    # Template matching
    template_match_score = Column(Float)
    vendor_fingerprint = Column(String(64))
    
    # Feedback state
    was_corrected = Column(Boolean, default=False)
    corrected_data = Column(JSON)
    correction_metadata = Column(JSON)
    
    # Performance
    processing_time_ms = Column(Integer)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    template = relationship("TemplateRegistry", back_populates="extraction_logs")
    corrections = relationship("SpatialCorrection", back_populates="log", cascade="all, delete-orphan")


class SpatialCorrection(Base):
    """Track individual field corrections for learning"""
    __tablename__ = "spatial_corrections"
    
    id = Column(Integer, primary_key=True)
    log_id = Column(Integer, ForeignKey("extraction_logs.id"), nullable=False)
    template_id = Column(Integer, ForeignKey("template_registry.id"), nullable=True)
    
    field_name = Column(String(50), nullable=False)
    
    # Original extraction
    original_bbox = Column(JSON)
    original_value = Column(Text)
    original_confidence = Column(Float)
    
    # User correction
    corrected_bbox = Column(JSON)
    corrected_value = Column(Text)
    
    # Spatial delta
    delta_x = Column(Integer)
    delta_y = Column(Integer)
    
    # Was this applied to template?
    was_applied_to_template = Column(Boolean, default=False)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    log = relationship("ExtractionLog", back_populates="corrections")
