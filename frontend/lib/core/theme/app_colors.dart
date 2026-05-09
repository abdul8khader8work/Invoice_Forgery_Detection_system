import 'package:flutter/material.dart';

/// Design tokens for app colors
/// Includes AI-specific states for Grok integration
class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFF1976D2);
  static const Color primaryDark = Color(0xFF1565C0);
  static const Color primaryLight = Color(0xFF42A5F5);

  // Secondary Colors
  static const Color secondary = Color(0xFF03A9F4);
  static const Color secondaryDark = Color(0xFF0288D1);
  static const Color secondaryLight = Color(0xFF4FC3F7);

  // AI/Grok Specific Colors
  static const Color grokAccent = Color(0xFF9C27B0); // Distinct AI indicator
  static const Color grokFallback = Color(0xFF757575); // Degraded state
  static const Color grokError = Color(0xFFD32F2F); // AI failure state
  static const Color grokSuccess = Color(0xFF388E3C); // AI success state
  static const Color grokProcessing = Color(0xFF1976D2); // AI processing state

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Neutral Colors
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF212121);
  static const Color onBackground = Color(0xFF212121);

  // Text Colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFF9E9E9E);
  static const Color textDisabled = Color(0xFFBDBDBD);

  // Border Colors
  static const Color border = Color(0xFFE0E0E0);
  static const Color borderLight = Color(0xFFEEEEEE);
  static const Color borderDark = Color(0xFFBDBDBD);

  // Risk Score Colors
  static const Color riskLow = Color(0xFF4CAF50);
  static const Color riskMedium = Color(0xFFFF9800);
  static const Color riskHigh = Color(0xFFF44336);
  static const Color riskCritical = Color(0xFFB71C1C);

  // Validation Colors
  static const Color validationPass = Color(0xFF4CAF50);
  static const Color validationFail = Color(0xFFF44336);
  static const Color validationWarning = Color(0xFFFF9800);
  static const Color validationPending = Color(0xFF9E9E9E);

  // Loading States
  static const Color loadingBackground = Color(0xFFF5F5F5);
  static const Color loadingShimmer = Color(0xFFE0E0E0);

  // Dark Mode Colors (TODO: Implement dark mode support)
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkOnSurface = Color(0xFFE0E0E0);
  static const Color darkOnBackground = Color(0xFFE0E0E0);
}

/// AI Loading State Colors
class AILoadingStates {
  /// AI reasoning in progress - blue processing state
  static const Color loadingGrok = AppColors.grokProcessing;

  /// AI service unavailable - gray degraded state
  static const Color grokFallback = AppColors.grokFallback;

  /// AI analysis failed - red error state
  static const Color grokError = AppColors.grokError;

  /// AI analysis successful - green success state
  static const Color grokSuccess = AppColors.grokSuccess;
}
