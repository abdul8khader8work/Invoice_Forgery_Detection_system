# Grok API Integration Documentation

## Overview
This system integrates with the **Grok API (xAI)** for natural language risk explanations, anomaly reasoning, and validation summarization in the Invoice Forgery Detection System.

## API Key Management

### Backend
- **Location**: Environment variables (`.env` file)
- **Variable Name**: `GROQ_API_KEY` (Note: Uses Groq API, not xAI Grok directly)
- **Storage**: Never hardcode API keys in source code
- **Rotation**: API key rotation should not require app redeploy (use backend proxy pattern)

### Frontend (Future)
- **Storage**: `flutter_secure_storage` for JWT tokens
- **Pattern**: Backend proxy - frontend never calls Grok API directly
- **Security**: All Grok API calls go through backend to protect API keys

## Request/Response Shape

### Request Structure
```python
# Current implementation in llm_extractor.py
{
    "model": "llama-3.3-70b-versatile",
    "messages": [
        {
            "role": "user",
            "content": "<OCR text or invoice data>"
        }
    ],
    "temperature": 0.1,
    "max_tokens": 4096,
    "response_format": {"type": "json_object"}
}
```

### Response Structure
```python
{
    "choices": [
        {
            "message": {
                "content": "<JSON string with extracted invoice data>",
                "role": "assistant"
            }
        }
    ]
}
```

### Parsed Response Fields
```python
{
    "vendor_name": str,
    "invoice_number": str,
    "invoice_date": str,
    "subtotal": float,
    "tax": float,
    "total": float,
    "line_items": list,
    "confidence": float,  # 0.0 to 1.0
    "extraction_method": "llm_groq_ocr",
    "model_used": "llama-3.3-70b-versatile"
}
```

## Error Codes & Handling

### Common Errors
1. **ConnectTimeout**: SSL handshake timeout
   - **Retry**: Exponential backoff (3 attempts)
   - **Fallback**: Use rule-based extraction only
   - **User Message**: "AI service unavailable - using rule-based analysis"

2. **ReadTimeout**: API response timeout
   - **Retry**: Exponential backoff (3 attempts)
   - **Fallback**: Use rule-based extraction only
   - **User Message**: "AI service slow - using rule-based analysis"

3. **RateLimitError**: Too many requests
   - **Retry**: Exponential backoff with longer delays
   - **Queueing**: Implement request queue for batch processing
   - **Fallback**: Process with rule-based validation
   - **User Message**: "AI rate limit reached - using rule-based analysis"

4. **AuthenticationError**: Invalid API key
   - **Retry**: Immediate fail (no retry)
   - **Fallback**: Use rule-based extraction only
   - **Admin Alert**: Notify admin of API key issue

## Rate Limiting

### Groq API Limits
- **RPM (Requests Per Minute)**: Varies by plan
- **TPM (Tokens Per Minute)**: Varies by plan

### Implementation Strategy
1. **Exponential Backoff**: 
   - Attempt 1: Immediate
   - Attempt 2: Wait 2^1 = 2 seconds
   - Attempt 3: Wait 2^2 = 4 seconds

2. **Request Queueing** (Future):
   - Implement queue for batch processing
   - Prioritize single invoice scans over batch
   - Queue management via Celery or FastAPI BackgroundTasks

3. **Token Usage Logging**:
   - Log input tokens per request
   - Log output tokens per request
   - Track cumulative usage for cost monitoring

## Fallback Behavior

### Graceful Degradation
When Grok API fails, the system must:
1. **Never crash the application**
2. **Show rule-based results only** (deterministic validation + ML anomaly detection)
3. **Display user-friendly message** explaining AI is unavailable
4. **Continue with full processing pipeline** (validation, ML, forgery detection, XAI)

### Fallback UI States
- **loadingGrok**: Spinner with "AI analysis in progress..."
- **grokFallback**: "AI service unavailable - using rule-based analysis"
- **grokError**: "AI analysis failed - showing partial results"

### Example Fallback Flow
```python
try:
    extracted = llm_extractor.extract_from_ocr_text(ocr_text)
except Exception as e:
    logger.warning(f"Grok API failed: {e}, falling back to rule-based extraction")
    extracted = extraction_service.extract_invoice_data(ocr_text)
    extracted['extraction_method'] = 'rule_based_fallback'
    extracted['confidence'] = 0.5  # Lower confidence for fallback
```

## Cost Awareness

### Token Counting
- **Input Tokens**: Length of OCR text / prompt
- **Output Tokens**: Length of LLM response
- **Logging**: Log token usage per request in audit logs

### Monitoring
- Track daily/monthly token usage
- Set up alerts for unusual usage spikes
- Implement cost optimization (e.g., truncate very long OCR text)

## Async-First Architecture

### Current Implementation
```python
# In main.py /scan endpoint
llm_extractor = get_groq_extractor()
extracted = llm_extractor.extract_from_ocr_text(ocr_text)
```

### Future Requirements
- **Never block UI**: Grok calls should use background tasks
- **Isolates**: Use Flutter isolates for non-blocking AI calls
- **Web Workers**: Use Web Workers for Flutter Web
- **Streaming**: Consider streaming responses for better UX

### Async Pattern (Future Backend)
```python
@router.post("/api/scan/async")
async def scan_async(file: UploadFile, background_tasks: BackgroundTasks):
    task_id = str(uuid.uuid4())
    background_tasks.add_task(process_invoice_async, task_id, file)
    return {"task_id": task_id, "status": "pending"}

# Flutter polls /api/scan/status/{task_id}
```

## Current Usage in Backend

### Endpoints Using Grok
1. **POST /scan** - Single invoice scan
   - Uses: `llm_extractor.extract_from_ocr_text()` for PDFs
   - Uses: `llm_extractor.extract_from_image_path()` for images

2. **POST /scan-batch** - Batch invoice scan
   - Uses: Same LLM extractor methods
   - Optimization: PaddleOCR for faster OCR + LLM for extraction

### Integration Points
- **File**: `backend/app/services/llm_extractor.py`
- **Class**: `LLMInvoiceExtractor`
- **Methods**:
  - `extract_from_ocr_text(ocr_text: str) -> Dict[str, Any]`
  - `extract_from_image_path(image_path: str) -> Dict[str, Any]`

## Testing

### Test Scenarios
1. **Normal Flow**: Grok API returns successful response
2. **Timeout**: Grok API times out, fallback to rule-based
3. **Rate Limit**: Groq API rate limit exceeded, fallback to rule-based
4. **Invalid Response**: Grok API returns invalid JSON, fallback to rule-based
5. **Network Error**: Network failure, fallback to rule-based

### Integration Test Requirements
- Mock Grok API timeout → assert app shows rule-based results without crash
- Assert risk score + reasoning fields exist (even if Grok is skipped)
- Verify user sees appropriate fallback message

## Migration Notes

### When Migrating to New Architecture
- **Preserve**: All Grok API interaction patterns
- **Enhance**: Add request queueing, better error handling
- **Maintain**: Backward compatibility with current endpoints
- **Add**: Type-safe client generation from OpenAPI spec

### Breaking Changes to Avoid
- Do NOT change the Grok API request/response format
- Do NOT remove fallback behavior
- Do NOT make UI blocking on Grok API calls
- Do NOT hardcode API keys in frontend

## Future Enhancements

1. **Request Queueing**: Implement Celery or FastAPI BackgroundTasks for queue management
2. **Streaming Responses**: Stream LLM responses for better UX
3. **Caching**: Cache Grok API responses for identical invoices
4. **Model Selection**: Allow configuration of different Groq models
5. **Cost Optimization**: Implement smart token usage optimization
