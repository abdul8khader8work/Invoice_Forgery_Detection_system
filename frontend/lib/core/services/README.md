# Core Services

This directory contains core service layers for the Flutter application.

## Grok Service (Future Implementation)

**File**: `grok_service.dart`

### Requirements

The Grok service must implement:

1. **Exponential Backoff**: Retry failed requests with exponential backoff (2^N seconds)
2. **Token Counting**: Log input/output token usage per request for cost monitoring
3. **Graceful Degradation**: Fall back to rule-based results without crashing
4. **Rate Limiting**: Respect Groq API RPM/TPM limits with queue management
5. **Async-First**: Never block UI - use isolates/background tasks
6. **Error Handling**: Map API errors to user-friendly messages

### Implementation Pattern (Future)

```dart
// TODO: Implement typed Grok client with retry/backoff
class GrokService {
  Future<GrokResponse> extractInvoiceData(String ocrText) async {
    // Implement exponential backoff (3 attempts)
    // Implement token counting
    // Implement graceful degradation
    // Implement rate limiting
  }
  
  Future<bool> isAvailable() async {
    // Check if Grok API is reachable
  }
}
```

### Current Status

- **Status**: Placeholder - not yet implemented
- **Current Implementation**: Direct HTTP calls in backend (`llm_extractor.py`)
- **Migration Plan**: When migrating to new architecture, implement this service

### Dependencies (Future)

- `dio`: HTTP client for API calls
- `flutter_secure_storage`: For API key management
- `retrofit`: Type-safe API client generation

### Notes

- All Grok API calls should go through backend proxy to protect API keys
- Frontend should never call Grok API directly
- Fallback to rule-based validation must be seamless
