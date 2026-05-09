from pydantic import BaseModel
from typing import Dict, Any, List, Optional
from datetime import datetime

class LineItem(BaseModel):
    item_number: str
    description: str
    quantity: float
    unit: str
    unit_price: float
    amount: float

class InvoiceScanRequest(BaseModel):
    pass  # File upload handled by multipart

class InvoiceResponse(BaseModel):
    file_id: str
    filename: str
    extracted_data: Dict[str, Any]
    ocr_confidence: float
    deterministic_validation: Dict[str, Any]
    ml_analysis: Dict[str, Any]
    risk_score: float
    risk_level: str
    reasoning: List[str]
    needs_verification: bool
    verification_fields: List[str]
    processing_time: float
    timestamp: str
    # New fields for enhanced extraction
    line_items: List[LineItem] = []
    payment_method: Optional[str] = None
    vendor_address: Optional[str] = None
    vendor_phone: Optional[str] = None
    validation_score: Optional[int] = None
    ml_score: Optional[float] = None

class ValidationResult(BaseModel):
    passed: bool
    reason: str
    confidence: float
    details: Optional[Dict[str, Any]] = None
