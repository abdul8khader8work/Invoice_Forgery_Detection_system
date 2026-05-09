import 'package:flutter/material.dart';

class AppColors {
  // Primary
  static const primary = Color(0xFFDC2626);      // Red-600
  static const primaryDark = Color(0xFFB91C1C);  // Red-700
  static const primaryLight = Color(0xFFFEE2E2); // Red-50
  
  // Risk Levels
  static const riskLow = Color(0xFF10B981);      // Green-500
  static const riskMedium = Color(0xFFF59E0B);   // Yellow-500
  static const riskHigh = Color(0xFFEF4444);     // Orange/Red-500
  static const riskCritical = Color(0xFF991B1B); // Red-900
  
  // Neutrals
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray900 = Color(0xFF111827);
  
  // Backgrounds
  static const background = gray50;
  static const cardBackground = Colors.white;
  
  // Status Colors
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);
}
