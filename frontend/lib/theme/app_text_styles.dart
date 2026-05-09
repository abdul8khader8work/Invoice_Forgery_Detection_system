import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  // Default font styling (Tailwind doesn't set custom fonts by default)
  // You can use system fonts or add Google Fonts

  static const TextStyle heading1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.gray900,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.gray900,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.gray900,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.gray700,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.gray500,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    color: AppColors.gray700,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    color: AppColors.gray700,
  );
}
