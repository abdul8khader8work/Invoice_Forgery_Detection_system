import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final String? trend;
  final bool showTrend;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    this.trend,
    this.showTrend = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.space2),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (showTrend && trend != null)
                Row(
                  children: [
                    Icon(
                      trend!.startsWith('+') ? Icons.trending_up : Icons.trending_down,
                      size: 16,
                      color: trend!.startsWith('+') ? AppColors.success : AppColors.error,
                    ),
                    const SizedBox(width: AppSpacing.space1),
                    Text(
                      trend!,
                      style: AppTextStyles.caption.copyWith(
                        color: trend!.startsWith('+') ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.gray900,
            ),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            title,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
