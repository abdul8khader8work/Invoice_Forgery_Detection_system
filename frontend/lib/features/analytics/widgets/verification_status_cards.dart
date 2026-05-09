import 'package:flutter/material.dart';
import 'package:invoice_forgery_detection/core/theme/app_colors.dart';
import 'package:invoice_forgery_detection/core/theme/app_spacing.dart';
import 'package:invoice_forgery_detection/core/theme/app_elevation.dart';

class VerificationStatusCards extends StatelessWidget {
  final int verifiedScans;
  final int unverifiedScans;
  final int approvedScans;
  final int editedScans;

  const VerificationStatusCards({
    super.key,
    required this.verifiedScans,
    required this.unverifiedScans,
    required this.approvedScans,
    required this.editedScans,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return Card(
      elevation: AppElevation.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verification Status',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: AppSpacing.md),
            GridView.count(
              crossAxisCount: isMobile ? 2 : 4,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: isMobile ? 0.9 : 1.0,
              children: [
                _buildStatusCard(
                  context,
                  'Verified',
                  verifiedScans,
                  AppColors.success,
                  Icons.verified,
                  isMobile,
                ),
                _buildStatusCard(
                  context,
                  'Unverified',
                  unverifiedScans,
                  AppColors.warning,
                  Icons.pending,
                  isMobile,
                ),
                _buildStatusCard(
                  context,
                  'Approved',
                  approvedScans,
                  AppColors.primary,
                  Icons.check_circle,
                  isMobile,
                ),
                _buildStatusCard(
                  context,
                  'Edited',
                  editedScans,
                  AppColors.secondary,
                  Icons.edit,
                  isMobile,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    String label,
    int count,
    Color color,
    IconData icon,
    bool isMobile,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? AppSpacing.sm : AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: isMobile ? 28 : 32),
            SizedBox(height: AppSpacing.xs),
            Text(
              count.toString(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 18 : null,
              ),
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[700],
                fontSize: isMobile ? 10 : null,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
