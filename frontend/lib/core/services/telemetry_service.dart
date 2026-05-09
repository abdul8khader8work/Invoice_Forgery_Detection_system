import 'package:flutter/foundation.dart';

/// Telemetry backend interface for pluggable analytics providers
abstract class TelemetryBackend {
  Future<void> trackEvent(String eventName, {Map<String, dynamic>? parameters});
  Future<void> trackScreenView(String screenName, {Map<String, dynamic>? parameters});
}

/// Mock telemetry backend (default)
class MockTelemetryBackend implements TelemetryBackend {
  @override
  Future<void> trackEvent(String eventName, {Map<String, dynamic>? parameters}) async {
    print('[TELEMETRY MOCK] Event: $eventName ${parameters ?? ''}');
  }

  @override
  Future<void> trackScreenView(String screenName, {Map<String, dynamic>? parameters}) async {
    print('[TELEMETRY MOCK] Screen: $screenName ${parameters ?? ''}');
  }
}

/// Pluggable telemetry service for usage logging
/// Supports Firebase Analytics, PostHog, Custom API, or Mock
class TelemetryService {
  static final TelemetryService _instance = TelemetryService._internal();
  factory TelemetryService() => _instance;
  TelemetryService._internal();

  TelemetryBackend? _backend;

  /// Initialize with custom backend
  void setBackend(TelemetryBackend backend) {
    _backend = backend;
  }

  /// Get current backend (mock if none set)
  TelemetryBackend get _currentBackend => _backend ?? MockTelemetryBackend();

  /// Check if real telemetry is enabled
  static bool get isRealTelemetryEnabled {
    final enabled = const String.fromEnvironment(
      'ENABLE_REAL_TELEMETRY',
      defaultValue: 'false',
    );
    return enabled.toLowerCase() == 'true';
  }

  /// Log screen view
  Future<void> logScreenView(String screenName, {Map<String, dynamic>? parameters}) async {
    await _currentBackend.trackScreenView(screenName, parameters: parameters);
  }

  /// Log scan start
  Future<void> logScanStart({String? fileType, int? fileSize}) async {
    await _currentBackend.trackEvent('scan_start', parameters: {
      'file_type': fileType ?? 'unknown',
      'file_size_bytes': fileSize,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Log scan complete
  Future<void> logScanComplete({
    required double durationMs,
    required bool success,
    required bool grokFallback,
    required double apiLatencyMs,
  }) async {
    await _currentBackend.trackEvent('scan_complete', parameters: {
      'duration_ms': durationMs,
      'success': success,
      'grok_fallback': grokFallback,
      'api_latency_ms': apiLatencyMs,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Log Grok fallback trigger
  Future<void> logGrokFallback(String reason) async {
    await _currentBackend.trackEvent('grok_fallback', parameters: {
      'reason': reason,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Log API error
  Future<void> logApiError(String endpoint, String error, int? statusCode) async {
    await _currentBackend.trackEvent('api_error', parameters: {
      'endpoint': endpoint,
      'error': error,
      'status_code': statusCode,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Log feature flag usage
  Future<void> logFeatureFlagUsage(String flagName, bool enabled) async {
    await _currentBackend.trackEvent('feature_flag', parameters: {
      'flag_name': flagName,
      'enabled': enabled,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track user action (alias for trackEvent)
  Future<void> trackUserAction(String action, {Map<String, dynamic>? parameters}) async {
    await _currentBackend.trackEvent(action, parameters: parameters);
  }

  /// Track screen view (alias for logScreenView)
  Future<void> trackScreenView(String screenName, {Map<String, dynamic>? parameters}) async {
    await _currentBackend.trackScreenView(screenName, parameters: parameters);
  }
}
