import 'package:flutter/material.dart';

/// Accessibility utilities for the app
class AccessibilityUtils {
  /// Check if text scaling is enabled
  static bool isTextScalingEnabled(BuildContext context) {
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    return textScaleFactor > 1.0;
  }
  
  /// Get safe text scale factor (clamp to prevent layout breakage)
  static double getSafeTextScale(BuildContext context, {double maxScale = 2.0}) {
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    return textScaleFactor.clamp(1.0, maxScale);
  }
  
  /// Create a semantic label for buttons
  static String getButtonLabel(String label, {String? hint}) {
    if (hint != null) {
      return '$label. $hint';
    }
    return label;
  }
  
  /// Create a semantic label for icons
  static String getIconLabel(String iconName, {String? action}) {
    if (action != null) {
      return '$iconName button. $action';
    }
    return '$iconName button';
  }
  
  /// Check if screen reader is active
  static bool isScreenReaderActive(BuildContext context) {
    return MediaQuery.accessibleNavigationOf(context);
  }
  
  /// Get semantic label for progress
  static String getProgressLabel(int current, int total, String item) {
    return '$item $current of $total';
  }
  
  /// Get semantic label for status
  static String getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
        return 'Completed';
      case 'failed':
      case 'error':
        return 'Failed';
      case 'pending':
      case 'loading':
        return 'In progress';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
  
  /// Announce message to screen reader
  static void announceMessage(BuildContext context, String message) {
    // This would use a proper screen reader announcement library
    // For now, we'll use a simple snackbar as fallback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  /// Check if high contrast mode is enabled
  static bool isHighContrastMode(BuildContext context) {
    return MediaQuery.highContrastOf(context);
  }
  
  /// Get appropriate color for high contrast mode
  static Color getAdaptiveColor(BuildContext context, Color normalColor) {
    if (isHighContrastMode(context)) {
      // Return high contrast colors
      return normalColor.computeLuminance() > 0.5
          ? Colors.black
          : Colors.white;
    }
    return normalColor;
  }
  
  /// Wrap widget with semantics for better accessibility
  static Widget withSemantics({
    required Widget child,
    String? label,
    String? hint,
    String? value,
    bool? increasedValue,
    bool? decreasedValue,
    bool? checked,
    bool? selected,
    bool? disabled,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool excludeSemantics = false,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      value: value,
      increasedValue: increasedValue?.toString(),
      decreasedValue: decreasedValue?.toString(),
      checked: checked,
      selected: selected,
      button: onTap != null,
      enabled: disabled != true,
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: excludeSemantics,
      child: child,
    );
  }
  
  /// Create accessible text widget with proper semantics
  static Widget accessibleText(
    String text, {
    TextStyle? style,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
    String? semanticsLabel,
  }) {
    return Semantics(
      label: semanticsLabel ?? text,
      child: Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.ellipsis,
      ),
    );
  }
  
  /// Check if platform supports haptic feedback
  static bool supportsHapticFeedback() {
    // Haptic feedback is supported on most modern platforms
    return true;
  }
  
  /// Provide haptic feedback for accessibility
  static void hapticFeedback({
    HapticFeedbackType type = HapticFeedbackType.light,
  }) {
    if (!supportsHapticFeedback()) return;
    
    // This would use a haptic feedback package
    // For now, this is a placeholder
  }
}

/// Haptic feedback types
enum HapticFeedbackType {
  light,
  medium,
  heavy,
  success,
  warning,
  error,
  selection,
  impact,
}

/// Accessible text scaling wrapper
class AccessibleTextScale extends StatelessWidget {
  final Widget child;
  final double maxScale;
  
  const AccessibleTextScale({
    super.key,
    required this.child,
    this.maxScale = 2.0,
  });
  
  @override
  Widget build(BuildContext context) {
    final textScaleFactor = AccessibilityUtils.getSafeTextScale(
      context,
      maxScale: maxScale,
    );
    
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScaleFactor),
      ),
      child: child,
    );
  }
}

/// Focus scope with accessibility support
class AccessibleFocusScope extends StatelessWidget {
  final Widget child;
  final String? focusLabel;
  final bool autofocus;
  final FocusNode? focusNode;
  
  const AccessibleFocusScope({
    super.key,
    required this.child,
    this.focusLabel,
    this.autofocus = false,
    this.focusNode,
  });
  
  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        // Handle keyboard navigation
        return KeyEventResult.ignored;
      },
      child: Semantics(
        label: focusLabel,
        child: child,
      ),
    );
  }
}
