-- =====================================================
-- Active Learning Invoice Extraction System
-- PostgreSQL Schema
-- =====================================================

-- 1. TEMPLATE REGISTRY
-- Stores learned vendor templates with spatial field mappings
CREATE TABLE template_registry (
    id SERIAL PRIMARY KEY,
    vendor_fingerprint VARCHAR(64) UNIQUE NOT NULL,  -- SHA256 hash of static identifiers
    style_tag VARCHAR(100),                           -- Human-readable style name (e.g., "AWS_Invoice_2024")
    
    -- Static identifiers used for fingerprinting (stored for debugging)
    identifiers JSONB,  -- {"gstin": "12ABCDE1234F1Z5", "vat": "123456789", "email": "billing@company.com"}
    
    -- The core field map with spatial relationships
    field_map JSONB NOT NULL,  -- See example below
    
    -- Metadata
    confidence_score FLOAT DEFAULT 0.0,  -- Template reliability (0.0-1.0)
    extraction_count INTEGER DEFAULT 0,   -- How many times used
    correction_count INTEGER DEFAULT 0,   -- How many times corrected
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_used_at TIMESTAMP WITH TIME ZONE,
    last_corrected_at TIMESTAMP WITH TIME ZONE,
    
    -- Soft delete
    is_active BOOLEAN DEFAULT TRUE
);

-- Example field_map structure:
-- {
--   "total": {
--     "anchor_label": "Grand Total",
--     "anchor_patterns": ["Grand Total", "Total Amount", "Gross Total"],
--     "direction": "right",
--     "y_tolerance": 5,
--     "x_max_distance": 200,
--     "expected_type": "currency",
--     "regex_pattern": "^\\$?[\\d,]+\\.\\d{2}$",
--     "confidence_boost": 0.1
--   },
--   "date": {
--     "anchor_label": "Invoice Date",
--     "anchor_patterns": ["Date", "Invoice Date", "Issued"],
--     "direction": "right",
--     "y_tolerance": 3,
--     "expected_type": "date",
--     "regex_pattern": "\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}"
--   }
-- }

-- 2. EXTRACTION LOGS
-- Audit trail for every extraction attempt
CREATE TABLE extraction_logs (
    id SERIAL PRIMARY KEY,
    file_id VARCHAR(36) NOT NULL,
    template_id INTEGER REFERENCES template_registry(id) ON DELETE SET NULL,
    
    -- Input/OCR data
    ocr_engine VARCHAR(50) DEFAULT 'paddleocr',  -- paddleocr, tesseract, easyocr
    raw_ocr_output JSONB,  -- Full OCR result with bounding boxes
    
    -- Extraction results
    extracted_data JSONB,  -- Final key-value pairs
    confidence_scores JSONB,  -- Per-field confidence
    
    -- Template matching info
    template_match_score FLOAT,  -- How well the template matched (0.0-1.0)
    vendor_fingerprint VARCHAR(64),  -- Fingerprint used for this extraction
    
    -- Feedback state
    was_corrected BOOLEAN DEFAULT FALSE,
    corrected_data JSONB,  -- User corrections if any
    correction_metadata JSONB,  -- {"corrected_by": "user@email", "correction_time": "..."}
    
    -- Performance metrics
    processing_time_ms INTEGER,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. SPATIAL CORRECTIONS
-- Track individual field corrections for learning
CREATE TABLE spatial_corrections (
    id SERIAL PRIMARY KEY,
    log_id INTEGER REFERENCES extraction_logs(id) ON DELETE CASCADE,
    template_id INTEGER REFERENCES template_registry(id) ON DELETE CASCADE,
    
    field_name VARCHAR(50) NOT NULL,
    
    -- Original extraction
    original_bbox JSONB,  -- {"x": 100, "y": 200, "w": 80, "h": 20}
    original_value TEXT,
    original_confidence FLOAT,
    
    -- User correction
    corrected_bbox JSONB,  -- New bounding box from user
    corrected_value TEXT,
    
    -- Spatial delta (what we learned)
    delta_x INTEGER,  -- Horizontal offset correction
    delta_y INTEGER,  -- Vertical offset correction
    
    -- Validation
    was_applied_to_template BOOLEAN DEFAULT FALSE,  -- Did we update the template?
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. VENDOR IDENTIFIERS (for fingerprinting)
-- Known static identifiers to help with vendor matching
CREATE TABLE vendor_identifiers (
    id SERIAL PRIMARY KEY,
    vendor_name VARCHAR(200),
    identifier_type VARCHAR(50),  -- gstin, vat, tax_id, email, phone
    identifier_value VARCHAR(100),
    template_id INTEGER REFERENCES template_registry(id) ON DELETE CASCADE,
    
    UNIQUE(identifier_type, identifier_value)
);

-- Indexes for performance
CREATE INDEX idx_template_fingerprint ON template_registry(vendor_fingerprint) WHERE is_active = TRUE;
CREATE INDEX idx_template_style_tag ON template_registry(style_tag);
CREATE INDEX idx_extraction_logs_file_id ON extraction_logs(file_id);
CREATE INDEX idx_extraction_logs_template ON extraction_logs(template_id);
CREATE INDEX idx_extraction_logs_created ON extraction_logs(created_at DESC);
CREATE INDEX idx_corrections_template ON spatial_corrections(template_id);
CREATE INDEX idx_corrections_field ON spatial_corrections(field_name);

-- GIN indexes for JSONB queries
CREATE INDEX idx_template_field_map ON template_registry USING GIN (field_map);
CREATE INDEX idx_extraction_raw_ocr ON extraction_logs USING GIN (raw_ocr_output);

-- =====================================================
-- Helper Functions
-- =====================================================

-- Function to calculate Levenshtein distance for fuzzy matching
CREATE OR REPLACE FUNCTION levenshtein_distance(s1 TEXT, s2 TEXT)
RETURNS INTEGER AS $$
DECLARE
    len1 INTEGER := LENGTH(s1);
    len2 INTEGER := LENGTH(s2);
    d INTEGER[][];
    i INTEGER;
    j INTEGER;
    cost INTEGER;
BEGIN
    IF len1 = 0 THEN RETURN len2; END IF;
    IF len2 = 0 THEN RETURN len1; END IF;
    
    -- Initialize matrix
    d := ARRAY(SELECT ARRAY(SELECT 0 FROM generate_series(1, len2 + 1)) FROM generate_series(1, len1 + 1));
    
    FOR i IN 0..len1 LOOP d[i+1][1] := i; END LOOP;
    FOR j IN 0..len2 LOOP d[1][j+1] := j; END LOOP;
    
    FOR i IN 1..len1 LOOP
        FOR j IN 1..len2 LOOP
            IF SUBSTRING(s1, i, 1) = SUBSTRING(s2, j, 1) THEN
                cost := 0;
            ELSE
                cost := 1;
            END IF;
            d[i+1][j+1] := LEAST(
                d[i][j+1] + 1,      -- deletion
                d[i+1][j] + 1,      -- insertion
                d[i][j] + cost      -- substitution
            );
        END LOOP;
    END LOOP;
    
    RETURN d[len1+1][len2+1];
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to get or create template fingerprint
CREATE OR REPLACE FUNCTION get_or_create_template(
    p_fingerprint VARCHAR(64),
    p_identifiers JSONB DEFAULT '{}',
    p_field_map JSONB DEFAULT '{}'
) RETURNS INTEGER AS $$
DECLARE
    v_template_id INTEGER;
BEGIN
    SELECT id INTO v_template_id 
    FROM template_registry 
    WHERE vendor_fingerprint = p_fingerprint AND is_active = TRUE;
    
    IF v_template_id IS NULL THEN
        INSERT INTO template_registry (
            vendor_fingerprint, 
            identifiers, 
            field_map,
            confidence_score
        ) VALUES (
            p_fingerprint, 
            p_identifiers, 
            p_field_map,
            0.5  -- Starting confidence
        ) RETURNING id INTO v_template_id;
    END IF;
    
    RETURN v_template_id;
END;
$$ LANGUAGE plpgsql;
