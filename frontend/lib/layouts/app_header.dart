import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Color(0xFF16213E),
        border: Border(
          bottom: BorderSide(color: Colors.white10),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.space2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 24),
          ),
          const SizedBox(width: AppSpacing.space3),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('InvoiceGuard', style: AppTextStyles.heading3.copyWith(color: Colors.white)),
              Text('Forgery Detection System', style: AppTextStyles.caption.copyWith(color: Colors.grey[400])),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
