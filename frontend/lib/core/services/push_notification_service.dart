import 'dart:async';
import 'package:flutter/foundation.dart';

/// Push notification service stub - Firebase dependencies disabled for web compatibility
/// Feature flag: ENABLE_PUSH_NOTIFICATIONS (default: false)
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  bool _initialized = false;
  bool _enabled = false;

  /// Initialize push notifications (stub implementation)
  Future<void> initialize({bool enabled = false}) async {
    if (_initialized) return;
    
    _enabled = enabled;
    if (!enabled) {
      debugPrint('Push notifications disabled by feature flag');
      return;
    }

    debugPrint('Push notification service stub initialized - Firebase dependencies disabled');
    _initialized = true;
  }

  /// Get FCM token (stub implementation)
  Future<String?> getToken() async {
    if (!_enabled) return null;
    debugPrint('FCM token unavailable - Firebase dependencies disabled');
    return null;
  }

  /// Subscribe to a topic (stub implementation)
  Future<void> subscribeToTopic(String topic) async {
    if (!_enabled) return;
    debugPrint('Topic subscription unavailable - Firebase dependencies disabled: $topic');
  }

  /// Unsubscribe from a topic (stub implementation)
  Future<void> unsubscribeFromTopic(String topic) async {
    if (!_enabled) return;
    debugPrint('Topic unsubscription unavailable - Firebase dependencies disabled: $topic');
  }

  /// Check if notifications are enabled
  bool get isEnabled => _enabled;

  /// Dispose resources
  void dispose() {
    debugPrint('Push notification service disposed');
  }
}
