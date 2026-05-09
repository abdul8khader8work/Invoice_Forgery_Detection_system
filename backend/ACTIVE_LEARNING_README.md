# Active Learning Invoice Extraction System

## Architecture Overview

This system implements a **production-ready Active Learning pipeline** for invoice data extraction that learns from user corrections to improve accuracy over time.

## Core Philosophy: "Learning is Just Storing Offsets"

Instead of building a generic AI that "understands" every invoice, the system:
1. **Fingerprints vendors** using static identifiers (GSTIN, VAT, Email)
2. **Remembers spatial relationships** between labels and values
3. **Learns from corrections** when users adjust bounding boxes
4. **Improves per-vendor** extraction accuracy over time

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     FLUTTER FRONTEND                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Upload       │  │ Scan Results │  │ Active Learning      │  │
│  │ Invoice      │→ │ with Risk   │→ │ Verification Screen  │  │
│  │              │  │ Score       │  │ (User Corrections)   │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FASTAPI BACKEND                               │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │         ACTIVE LEARNING PIPELINE                         │  │
│  │                                                          │  │
│  │  1. PaddleOCR Engine (preprocessing + OCR)              │  │
│  │     ↓                                                   │  │
│  │  2. Vendor Fingerprinting (GSTIN/VAT extraction)      │  │
│  │     ↓                                                   │  │
│  │  3. Template Registry (match/create template)         │  │
│  │     ↓                                                   │  │
│  │  4. Spatial Intelligence (proximity-based extraction)  │  │
│  │     ↓                                                   │  │
│  │  5. Multi-Engine Voting (template + heuristic)        │  │
│  │     ↓                                                   │  │
│  │  6. Confidence Scoring (per-field + overall)            │  │
│  │     ↓                                                   │  │
│  │  7. Feedback Loop (/templates/refine endpoint)          │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  POSTGRESQL DATABASE                             │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │ template_registry│  │ extraction_logs  │  │spatial_      │  │
│  │                  │  │                  │  │corrections   │  │
│  │ • fingerprint    │  │ • file_id        │  │              │  │
│  │ • field_map      │  │ • raw_ocr        │  │ • delta_x/y  │  │
│  │ • confidence     │  │ • extracted_data │  │ • bbox data  │  │
│  │ • learned_offset │  │ • was_corrected  │  │              │  │
│  └──────────────────┘  └──────────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Dynamic Anchor Registry

### Database Schema

```sql
-- Template Registry stores learned vendor patterns
CREATE TABLE template_registry (
    id SERIAL PRIMARY KEY,
    vendor_fingerprint VARCHAR(64) UNIQUE NOT NULL,  -- SHA256 of GSTIN/VAT/Email
    style_tag VARCHAR(100),                           -- Human-readable name
    identifiers JSONB,                                 -- {gstin: "...", vat: "..."}
    field_map JSONB NOT NULL,                         -- Spatial relationships
    confidence_score FLOAT DEFAULT 0.0,
    extraction_count INTEGER DEFAULT 0,
    correction_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    last_used_at TIMESTAMP,
    last_corrected_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);
```

### Field Map Structure

```json
{
  "total": {
    "anchor_label": "Grand Total",
    "anchor_patterns": ["Grand Total", "Total Amount", "Gross Total"],
    "direction": "right",
    "y_tolerance": 5,
    "x_max_distance": 250,
    "expected_type": "currency",
    "regex_pattern": "^\\$?[\\d,]+\\.\\d{2}$",
    "learned_offset_x": 120,        -- Learned from user corrections
    "learned_offset_y": 0,
    "extraction_count": 15,
    "last_corrected_at": "2024-01-15T10:30:00"
  }
}
```

### Fuzzy String Matching

The system uses **Levenshtein distance** to match OCR text with anchor patterns, tolerating 1-character typos:

```python
# "6STIN" matches "GSTIN" with 1 typo
is_match, confidence = fuzzy.is_anchor_match(
    ocr_text="6STIN",
    anchor_patterns=["GSTIN"],
    max_typos=1
)
# Returns: (True, 0.8)
```

---

## Phase 2: Spatial Intelligence Layer

### Proximity Search Algorithm

Instead of fixed coordinates, the system searches **relative to anchor labels**:

```python
def find_neighbor(
    anchor_bbox: BoundingBox,      # Label "Grand Total"
    direction: str,                # "right"
    y_tolerance: int = 5,           # ±5px vertical tolerance
    x_max_distance: int = 200,      # Max horizontal distance
    constraint_regex: str = None   # Must match currency pattern
) -> Optional[BoundingBox]:        # Returns value box
```

### Multi-Engine Voting

When template confidence is low, the system runs a **heuristic scan** and votes:

```python
# Template-based extraction
template_result = spatial_engine.extract_field(field_map)

# Heuristic regex patterns
heuristic_result = run_heuristic_scan(field_name)

# Vote and pick winner
value, confidence, source = voting_engine.vote(
    template_result=template_result,
    heuristic_result=heuristic_result
)
```

---

## Phase 3: Feedback Loop (The Learning Mechanism)

### Correction Endpoint

```
POST /active-learning/templates/refine
```

**Request:**
```json
{
  "file_id": "uuid",
  "log_id": 12345,
  "style_tag": "AWS_Invoice_2024",
  "corrections": [
    {
      "field_name": "total",
      "original_value": "$1,23.45",
      "corrected_value": "$123.45",
      "original_bbox": {"x": 500, "y": 300, "width": 100, "height": 20},
      "corrected_bbox": {"x": 520, "y": 300, "width": 90, "height": 20},
      "anchor_bbox": {"x": 400, "y": 300, "width": 80, "height": 20}
    }
  ]
}
```

**Action:**
1. Calculate delta: `delta_x = 520 - 400 = +120px`
2. Update template field map with `learned_offset_x: 120`
3. Increment template confidence score
4. Log correction for audit trail

### Confidence Scoring

Every extraction returns a **confidence score (0.0 to 1.0)** based on:

```python
confidence = (
    template_match_score * 0.3 +      # Is this a known vendor?
    data_validation_score * 0.3 +      # Does value match expected type?
    spatial_alignment_score * 0.2 +     # Is value near label?
    field_consistency_score * 0.2      # Do fields make sense together?
)
```

---

## API Endpoints

### Main Processing

```
POST /active-learning/process-invoice
```
- Accepts: Image/PDF file
- Optional: `style_hint` to force specific template
- Returns: Extracted data with confidence scores

### Feedback Loop

```
POST /active-learning/templates/refine
```
- Accepts: User corrections with bounding box data
- Action: Updates template field map
- Returns: Updated template confidence

### Management

```
GET /active-learning/templates              # List learned templates
GET /active-learning/templates/{id}         # Get template details
GET /active-learning/extraction-logs/{id}   # Get extraction details
GET /active-learning/analytics/template-performance  # Analytics
```

---

## File Structure

```
backend/
├── app/
│   ├── api/
│   │   └── active_learning_routes.py      # FastAPI endpoints
│   ├── models/
│   │   ├── database.py                    # Core SQLAlchemy models
│   │   └── active_learning_models.py      # Template/Log models
│   ├── services/
│   │   ├── template_registry.py           # Fingerprint & registry
│   │   ├── spatial_intelligence.py        # Proximity search
│   │   └── paddle_ocr_engine.py           # OCR + extraction
│   └── db/
│       └── active_learning_schema.sql     # PostgreSQL schema
└── main.py                                # App entry point

frontend/
├── lib/
│   ├── services/
│   │   └── active_learning_service.dart    # API client
│   └── screens/
│       └── active_learning_verification_screen.dart  # Correction UI
```

---

## Installation

### Backend Dependencies

```bash
pip install paddlepaddle==2.5.2
pip install paddleocr==2.7.0.3
pip install python-Levenshtein==0.21.1
```

### Database Setup

```bash
# Run schema
psql -U postgres -d invoice_system -f app/db/active_learning_schema.sql
```

---

## Usage Example

### Process Invoice

```python
from app.services.paddle_ocr_engine import process_invoice_image

result = process_invoice_image(
    image_path="invoice.pdf",
    style_hint=None  # Auto-detect template
)

print(result)
# {
#   "vendor_fingerprint": "abc123...",
#   "template_id": 42,
#   "style_tag": "AWS_Invoice_2024",
#   "extracted_data": {
#     "vendor_name": "Amazon Web Services",
#     "total": "$1,234.56",
#     ...
#   },
#   "confidence_scores": {
#     "total": 0.92,
#     "date": 0.88,
#     ...
#   },
#   "needs_verification": False
# }
```

### Submit Correction

```bash
curl -X POST http://localhost:8000/active-learning/templates/refine \
  -H "Content-Type: application/json" \
  -d '{
    "file_id": "uuid",
    "log_id": 123,
    "style_tag": "AWS_Invoice",
    "corrections": [{
      "field_name": "total",
      "original_value": "$1,23.45",
      "corrected_value": "$123.45",
      "original_bbox": {"x": 500, "y": 300, "width": 100, "height": 20},
      "corrected_bbox": {"x": 520, "y": 300, "width": 90, "height": 20},
      "anchor_bbox": {"x": 400, "y": 300, "width": 80, "height": 20}
    }]
  }'
```

---

## Key Design Decisions

1. **Spatial over Fixed Coordinates**: Relative positioning handles different zoom levels, rotations, and layouts

2. **Per-Vendor Learning**: Each vendor gets its own template, preventing confusion between different invoice formats

3. **Multi-Engine Voting**: Template + Heuristic provides robust extraction even when templates are new

4. **Audit Everything**: Every extraction and correction is logged for debugging and improvement

5. **Confidence-Based Verification**: Fields below 70% confidence trigger human verification

---

## Next Steps

1. **Flutter Integration**: Wire up `active_learning_verification_screen.dart` to the main scan flow
2. **Template Analytics**: Build dashboard showing which vendors need more corrections
3. **Auto-Template Merging**: When fingerprints are similar, merge templates automatically
4. **Batch Processing**: Process multiple invoices and learn from the batch

---

## The Reality Check

> "Learning is just storing offsets. If a user moves a bounding box to the right to find the 'Total,' your backend needs to save that +X offset for that specific vendor_id."

This system doesn't use "AI magic" — it uses:
- **Pattern matching** (fingerprints)
- **Relative geometry** (spatial search)
- **Statistical voting** (confidence scores)
- **Explicit memory** (template registry)

The "smart" part is the **feedback loop** that converts user corrections into learned spatial relationships.
