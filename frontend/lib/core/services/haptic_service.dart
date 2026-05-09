import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Haptic feedback service for tactile responses
/// Provides platform-appropriate feedback for user actions
class HapticService {
  static final HapticService _instance = HapticService._internal();
  factory HapticService() => _instance;
  HapticService._internal();

  bool _enabled = true;

  /// Enable/disable haptic feedback globally
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Light impact - subtle feedback for minor interactions
  void lightImpact() {
    if (!_enabled || kIsWeb) return;
    HapticFeedback.lightImpact();
  }

  /// Medium impact - standard feedback for most interactions
  void mediumImpact() {
    if (!_enabled || kIsWeb) return;
    HapticFeedback.mediumImpact();
  }

  /// Heavy impact - strong feedback for significant actions
  void heavyImpact() {
    if (!_enabled || kIsWeb) return;
    HapticFeedback.heavyImpact();
  }

  /// Selection click - for picker/value changes
  void selectionClick() {
    if (!_enabled || kIsWeb) return;
    HapticFeedback.selectionClick();
  }

  /// Success pattern - for successful operations
  void success() {
    if (!_enabled || kIsWeb) return;
    // Pattern: light, medium, light
    _performPattern([
      _HapticPattern(HapticFeedback.lightImpact, 50),
      _HapticPattern(HapticFeedback.mediumImpact, 100),
      _HapticPattern(HapticFeedback.lightImpact, 50),
    ]);
  }

  /// Error pattern - for failures/errors
  void error() {
    if (!_enabled || kIsWeb) return;
    // Pattern: heavy, pause, heavy
    _performPattern([
      _HapticPattern(HapticFeedback.heavyImpact, 100),
      _HapticPattern(null, 150), // pause
      _HapticPattern(HapticFeedback.heavyImpact, 100),
    ]);
  }

  /// Warning pattern - for cautions
  void warning() {
    if (!_enabled || kIsWeb) return;
    // Pattern: medium, light
    _performPattern([
      _HapticPattern(HapticFeedback.mediumImpact, 100),
      _HapticPattern(HapticFeedback.lightImpact, 50),
    ]);
  }

  /// Scan complete - celebration feedback
  void scanComplete() {
    if (!_enabled || kIsWeb) return;
    success();
  }

  /// Risk revealed - dramatic feedback for risk scores
  void riskRevealed() {
    if (!_enabled || kIsWeb) return;
    // Pattern: building intensity
    _performPattern([
      _HapticPattern(HapticFeedback.lightImpact, 50),
      _HapticPattern(HapticFeedback.lightImpact, 50),
      _HapticPattern(HapticFeedback.mediumImpact, 100),
    ]);
  }

  /// Batch finished - completion feedback
  void batchFinished({bool success = true}) {
    if (!_enabled || kIsWeb) return;
    if (success) {
      // Success pattern: ascending
      _performPattern([
        _HapticPattern(HapticFeedback.lightImpact, 50),
        _HapticPattern(HapticFeedback.mediumImpact, 100),
        _HapticPattern(HapticFeedback.heavyImpact, 150),
        _HapticPattern(HapticFeedback.mediumImpact, 50),
      ]);
    } else {
      // Partial success: mixed pattern
      _performPattern([
        _HapticPattern(HapticFeedback.mediumImpact, 100),
        _HapticPattern(HapticFeedback.lightImpact, 50),
        _HapticPattern(HapticFeedback.mediumImpact, 100),
      ]);
    }
  }

  /// Upload complete feedback
  void uploadComplete() {
    if (!_enabled || kIsWeb) return;
    mediumImpact();
  }

  /// Button press feedback
  void buttonPress() {
    if (!_enabled || kIsWeb) return;
    lightImpact();
  }

  /// Long press feedback
  void longPress() {
    if (!_enabled || kIsWeb) return;
    heavyImpact();
  }

  /// Page transition feedback
  void pageTransition() {
    if (!_enabled || kIsWeb) return;
    lightImpact();
  }

  /// Tab switch feedback
  void tabSwitch() {
    if (!_enabled || kIsWeb) return;
    selectionClick();
  }

  /// Scroll edge feedback (reached end of list)
  void scrollEdge() {
    if (!_enabled || kIsWeb) return;
    lightImpact();
  }

  /// Toggle switch feedback
  void toggle() {
    if (!_enabled || kIsWeb) return;
    selectionClick();
  }

  /// Drag start feedback
  void dragStart() {
    if (!_enabled || kIsWeb) return;
    mediumImpact();
  }

  /// Drag end feedback
  void dragEnd() {
    if (!_enabled || kIsWeb) return;
    lightImpact();
  }

  /// Perform a custom haptic pattern
  void _performPattern(List<_HapticPattern> patterns) async {
    for (final pattern in patterns) {
      if (pattern.action != null) {
        pattern.action!();
      }
      await Future.delayed(Duration(milliseconds: pattern.delayMs));
    }
  }
}

/// Internal pattern definition
class _HapticPattern {
  final Function? action;
  final int delayMs;

  _HapticPattern(this.action, this.delayMs);
}

/// Global instance
final haptic = HapticService();
