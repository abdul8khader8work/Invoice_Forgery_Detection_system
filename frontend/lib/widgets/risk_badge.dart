import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class RiskBadge extends StatelessWidget {
  final String level; // 'low', 'medium', 'high', 'critical'
  final double? fontSize;

  const RiskBadge({
    super.key,
    required this.level,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = {
      'low': {'bg': Color(0xFFDCFCE7), 'text': Color(0xFF166534)},
      'medium': {'bg': Color(0xFFFEF3C7), 'text': Color(0xFF92400E)},
      'high': {'bg': Color(0xFFFFEDD5), 'text': Color(0xFF9A3412)},
      'critical': {'bg': Color(0xFFFEE2E2), 'text': Color(0xFF991B1B)},
    };
    
    final levelColors = colors[level.toLowerCase()] ?? colors['low']!;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space1,
      ),
      decoration: BoxDecoration(
        color: levelColors['bg'],
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        level.toUpperCase(),
        style: TextStyle(
          fontSize: fontSize ?? 12,
          fontWeight: FontWeight.w500,
          color: levelColors['text'],
        ),
      ),
    );
  }
}
