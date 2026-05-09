import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Feature flags configuration
/// Supports runtime toggle via debug overlay and .env fallback
class FeatureFlags {
  static const String _enableNewScanUI = 'ENABLE_NEW_SCAN_UI';

  /// Check if new scan UI is enabled
  static bool get enableNewScanUI {
    // Priority 1: Dart-define (compile-time)
    final dartDefine = const String.fromEnvironment(
      _enableNewScanUI,
      defaultValue: '',
    );

    if (dartDefine.isNotEmpty) {
      return dartDefine.toLowerCase() == 'true';
    }

    // Priority 2: .env file (runtime)
    try {
      if (!kIsWeb) {
        // Only load .env on non-web platforms
        // Web .env loading requires additional setup
        final envValue = dotenv.env[_enableNewScanUI] ?? '';
        if (envValue.isNotEmpty) {
          return envValue.toLowerCase() == 'true';
        }
      }
    } catch (e) {
      // Fallback to default if .env loading fails
      print('Failed to load .env: $e');
    }

    // Default: enabled (Phase 3 rollout)
    return true;
  }

  /// Set feature flag at runtime (for debug overlay)
  static Future<void> setEnableNewScanUI(bool enabled) async {
    if (!kIsWeb) {
      try {
        await dotenv.load(fileName: '.env');
        // Update in-memory .env (doesn't persist to file)
        // This is for testing/debug purposes only
        dotenv.env[_enableNewScanUI] = enabled ? 'true' : 'false';
      } catch (e) {
        print('Failed to update feature flag: $e');
      }
    }
  }

  /// Get all feature flags as a map (for debug display)
  static Map<String, bool> getAllFlags() {
    return {
      _enableNewScanUI: enableNewScanUI,
    };
  }
}
