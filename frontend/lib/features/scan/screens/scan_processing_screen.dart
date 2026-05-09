import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:invoice_forgery_detection/core/theme/app_colors.dart';
import 'package:invoice_forgery_detection/core/theme/app_typography.dart';
import 'package:invoice_forgery_detection/core/theme/app_spacing.dart';
import 'package:invoice_forgery_detection/core/providers/scan_providers.dart';
import 'package:invoice_forgery_detection/core/services/analytics_refresh_service.dart';
import 'package:invoice_forgery_detection/features/scan/screens/scan_result_screen.dart';

/// Scan processing screen with skeleton loaders, step-by-step visualization, and Grok polling UI
class ScanProcessingScreen extends ConsumerStatefulWidget {
  final dynamic file; // Can be String (path) or Uint8List (bytes)

  const ScanProcessingScreen({super.key, required this.file});

  @override
  ConsumerState<ScanProcessingScreen> createState() => _ScanProcessingScreenState();
}

class _ScanProcessingScreenState extends ConsumerState<ScanProcessingScreen> {
  @override
  void initState() {
    super.initState();
    // Start scanning when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scanUploadProvider.notifier).scanInvoice(widget.file);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanUploadProvider);

    // Navigate to result screen when complete
    if (scanState.result != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ✅ MOUNTED CHECK: Ensure widget is still mounted
        if (!mounted) return;
        
        try {
          // Trigger analytics refresh after successful scan
          AnalyticsRefreshService().triggerRefresh();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ScanResultScreen(result: scanState.result!),
            ),
          );
        } catch (e) {
          print('❌ Navigation error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error displaying results: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Processing Invoice'),
        backgroundColor: AppColors.primary,
      ),
      body: scanState.error != null
          ? _buildErrorView(scanState.error!)
          : _buildProcessingView(scanState),
    );
  }

  Widget _buildProcessingView(ScanUploadState state) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress indicator
          LinearProgressIndicator(
            value: state.progress,
            backgroundColor: AppColors.loadingShimmer,
            valueColor: AlwaysStoppedAnimation<Color>(
              state.isGrokProcessing ? AppColors.grokAccent : AppColors.primary,
            ),
          ).animate().fadeIn(duration: 600.ms),
          SizedBox(height: AppSpacing.md),
          Text(
            '${(state.progress * 100).toInt()}% Complete',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ).animate().fadeIn(duration: 600.ms),
          SizedBox(height: AppSpacing.xl),

          // Processing steps
          _buildStep(
            '1. File Upload',
            state.progress >= 0.2,
            'Uploading file to server',
          ),
          _buildStep(
            '2. OCR Processing',
            state.progress >= 0.4,
            'Extracting text from document',
          ),
          _buildStep(
            '3. AI Analysis',
            state.progress >= 0.6,
            state.isGrokProcessing
                ? 'Running Grok AI analysis...'
                : 'Processing with fallback rules',
            isAI: true,
            isProcessing: state.isGrokProcessing,
          ),
          _buildStep(
            '4. Validation',
            state.progress >= 0.8,
            'Running deterministic validation',
          ),
          _buildStep(
            '5. ML Detection',
            state.progress >= 1.0,
            'Running anomaly detection',
          ),

          SizedBox(height: AppSpacing.xl),

          // Grok status indicator
          if (state.isGrokProcessing)
            Container(
              padding: EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.grokAccent.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.grokAccent),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.grokAccent),
                    ),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'AI Analysis in Progress...',
                      style: AppTypography.aiLoading,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 600.ms),

          // Fallback indicator
          if (state.isGrokFallback)
            Container(
              padding: EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.grokFallback.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.grokFallback),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.grokFallback),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'AI service unavailable - using rule-based analysis',
                      style: AppTypography.aiFallback,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 600.ms),
        ],
      ),
    );
  }

  Widget _buildStep(String title, bool completed, String description,
      {bool isAI = false, bool isProcessing = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: completed
                  ? isAI
                      ? AppColors.grokAccent
                      : AppColors.success
                  : AppColors.loadingShimmer,
              shape: BoxShape.circle,
            ),
            child: completed
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : isProcessing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isAI ? AppColors.grokAccent : AppColors.textSecondary,
                          ),
                        ),
                      )
                    : null,
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    color: completed ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
                if (!completed && !isProcessing)
                  // Skeleton loader for description
                  Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.loadingShimmer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ).animate().shimmer(duration: 1500.ms),
                if (completed || isProcessing)
                  Text(
                    description,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ).animate().fadeIn(duration: 600.ms),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ).animate().scale(duration: 400.ms),
            SizedBox(height: AppSpacing.md),
            Text(
              'Processing Failed',
              style: AppTypography.headlineSmall.copyWith(
                color: AppColors.error,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              error,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Go Back'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Retry the scan
                      ref.read(scanUploadProvider.notifier).scanInvoice(widget.file);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
