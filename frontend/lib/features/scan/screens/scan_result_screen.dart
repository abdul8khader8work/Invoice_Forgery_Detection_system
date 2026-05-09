import 'dart:convert';
import 'package:invoice_forgery_detection/core/services/file_download_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:invoice_forgery_detection/core/theme/app_colors.dart';
import 'package:invoice_forgery_detection/core/theme/app_typography.dart';
import 'package:invoice_forgery_detection/core/theme/app_spacing.dart';
import 'package:invoice_forgery_detection/core/theme/app_elevation.dart';
import 'package:invoice_forgery_detection/core/api/models/scan_response.dart';
import 'package:invoice_forgery_detection/core/api/api_client.dart';
import 'package:invoice_forgery_detection/core/providers/api_providers.dart';

class ChatMessage {
  final String role;
  final String content;
  
  ChatMessage({required this.role, required this.content});
}

/// Scan result screen with risk gauge, confidence badges, expandable reasoning, and fallback banner
class ScanResultScreen extends ConsumerStatefulWidget {
  final ScanResponse result;

  const ScanResultScreen({super.key, required this.result});

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen> {
  final List<ChatMessage> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  bool _isChatLoading = false;
  final ScrollController _chatScrollController = ScrollController();
  
  // ✅ Store initial risk values to prevent changes on refresh
  late final double _initialRiskScore;
  late final String _initialRiskLevel;
  
  @override
  void initState() {
    super.initState();
    // Capture initial risk values when screen is first created
    _initialRiskScore = widget.result.riskScore ?? 0.0;
    _initialRiskLevel = widget.result.riskLevel ?? 'UNKNOWN';
    print('📊 Initial Risk Score captured: $_initialRiskScore ($_initialRiskLevel)');
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _sendChatMessage() async {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _chatMessages.add(ChatMessage(
        role: 'user',
        content: message,
      ));
      _isChatLoading = true;
      _chatController.clear();
    });

    // Scroll to bottom
    _scrollToBottom();

    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      
      // Create a separate Dio instance without retry for FormData requests
      final chatDio = Dio(BaseOptions(
        baseUrl: apiClient.dio.options.baseUrl,
        connectTimeout: apiClient.dio.options.connectTimeout,
        receiveTimeout: apiClient.dio.options.receiveTimeout,
        sendTimeout: apiClient.dio.options.sendTimeout,
      ));

      // Add logging interceptor only
      chatDio.interceptors.add(LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ));
      
      // Prepare form data
      final formData = FormData();
      formData.fields.add(MapEntry('query', message));
      formData.fields.add(MapEntry('extracted_data', jsonEncode(widget.result.extractedData)));
      
      // Get conversation history
      final history = _chatMessages
          .where((m) => m.role != 'user' || _chatMessages.indexOf(m) < _chatMessages.length - 1)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      formData.fields.add(MapEntry('conversation_history', jsonEncode(history)));

      final response = await chatDio.post('/chat/query', data: formData);
      
      setState(() {
        _chatMessages.add(ChatMessage(
          role: 'assistant',
          content: response.data['answer'] ?? 'No response',
        ));
        _isChatLoading = false;
      });
      
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _chatMessages.add(ChatMessage(
          role: 'assistant',
          content: 'Error: ${e.toString()}',
        ));
        _isChatLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ SAFEAREA FIX: Wrap entire screen for desktop compatibility
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan Results'),
          backgroundColor: AppColors.primary,
          actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              try {
                final apiClient = ref.read(invoiceApiClientProvider);
                // refresh scan status from backend
                if (widget.result.fileId != null) {
                  final statusResponse = await apiClient.getScanStatus(widget.result.fileId!);
                  // convert map to scanresponse
                  final refreshedResult = ScanResponse.fromJson(statusResponse);
                  // navigate to refreshed result screen
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ScanResultScreen(result: refreshedResult),
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('failed to refresh: $e')),
                  );
                }
              }
            },
            tooltip: 'refresh status',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareInvoice(context, ref),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 900;
          return SingleChildScrollView(
            padding: EdgeInsets.all(isDesktop ? 32 : AppSpacing.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 1000 : double.infinity,
                // ✅ Removed minHeight to prevent desktop blank screen
                // Content determines height naturally
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min, // ✅ ADD: Prevent layout overflow
                children: [
                  // Grok fallback banner
            if (widget.result.error?.toLowerCase().contains('grok') ?? false)
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
                        'AI analysis unavailable - results from rule-based analysis',
                        style: AppTypography.aiFallback,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 600.ms),
            if (widget.result.error?.toLowerCase().contains('grok') ?? false)
              SizedBox(height: AppSpacing.lg),

            // Risk score card
            Card(
              elevation: AppElevation.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Risk Score',
                          style: AppTypography.titleLarge,
                        ),
                        // ✅ Use stored initial value to prevent changes on refresh
                        _buildRiskBadge(_initialRiskLevel),
                      ],
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // ✅ Use stored initial value to prevent changes on refresh
                    _buildRiskGauge(_initialRiskScore),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 600.ms),
            SizedBox(height: AppSpacing.lg),

            // Extracted data card
            _buildExpandableCard(
              title: 'Extracted Data',
              icon: Icons.receipt,
              child: _buildExtractedData(widget.result.extractedData),
            ).animate().fadeIn(duration: 600.ms, delay: 200.ms),
            SizedBox(height: AppSpacing.lg),

            // Validation results card
            if (widget.result.deterministicValidation != null)
              _buildExpandableCard(
                title: 'Validation Results',
                icon: Icons.check_circle,
                child: _buildValidationResults(widget.result.deterministicValidation),
              ).animate().fadeIn(duration: 600.ms, delay: 400.ms),
            SizedBox(height: AppSpacing.lg),

            // ML analysis card
            _buildExpandableCard(
              title: 'ML Analysis',
              icon: Icons.psychology,
              child: _buildMLAnalysis(widget.result.mlAnalysis),
            ).animate().fadeIn(duration: 600.ms, delay: 800.ms),
            SizedBox(height: AppSpacing.lg),

            // AI Chat card
            _buildExpandableCard(
              title: 'AI Chat',
              icon: Icons.chat,
              child: _buildAIChat(),
            ).animate().fadeIn(duration: 600.ms, delay: 1000.ms),

            SizedBox(height: AppSpacing.xl),

            // Action buttons
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Download report',
                        hint: 'Download detailed analysis report',
                        child: ElevatedButton.icon(
                          onPressed: () => _downloadReport(context, ref, widget.result),
                          icon: const Icon(Icons.download),
                          label: const Text('download report'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
                            minimumSize: const Size(0, 56),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Edit data',
                        hint: 'Edit extracted invoice data',
                        child: OutlinedButton.icon(
                          onPressed: () => _editExtractedData(context, ref, widget.result),
                          icon: const Icon(Icons.edit),
                          label: const Text('edit data'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
                            minimumSize: const Size(0, 56),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Approve invoice',
                        hint: 'Approve this invoice as valid',
                        child: OutlinedButton.icon(
                          onPressed: () => _approveInvoice(context, ref, widget.result),
                          icon: const Icon(Icons.check_circle),
                          label: const Text('approve'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: BorderSide(color: AppColors.success),
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
                            minimumSize: const Size(0, 56),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.md),
                // Secondary actions
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Verify invoice',
                        hint: 'Verify invoice with audit trail',
                        child: OutlinedButton.icon(
                          onPressed: () => _verifyInvoice(context, ref, widget.result),
                          icon: const Icon(Icons.verified),
                          label: const Text('verify'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
                            minimumSize: const Size(0, 56),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'View audit history',
                        hint: 'View audit history for this invoice',
                        child: OutlinedButton.icon(
                          onPressed: () => _viewAuditHistory(context, ref, widget.result),
                          icon: const Icon(Icons.history),
                          label: const Text('audit history'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
                            minimumSize: const Size(0, 56),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ).animate().fadeIn(duration: 600.ms, delay: 1200.ms),
          ],
        ),
      ),
    );
  },
),
),
);
}

void _downloadReport(BuildContext context, WidgetRef ref, ScanResponse result) async {
    if (result.fileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('cannot download report: no file id available'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      final report = await apiClient.downloadInvoiceReport(result.fileId!);
      
      try {
        await FileDownloadService.downloadJsonFile(
          filename: 'invoice_report_${result.fileId}.json',
          jsonData: report,
        );
      } catch (e) {
        // Show message for desktop platforms where download is not implemented yet
        FileDownloadService.showDownloadNotAvailableMessage(
          context,
          'invoice_report_${result.fileId}.json',
        );
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report downloaded successfully for invoice ${result.fileId}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('failed to download report: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _shareInvoice(BuildContext context, WidgetRef ref) async {
    if (widget.result.fileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('cannot share: no file id available'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      final response = await apiClient.dio.post('/invoices/${widget.result.fileId}/share');
      
      if (response.data['success'] == true) {
        final shareUrl = response.data['share_url'];
        
        // Copy to clipboard
        await FileDownloadService.copyToClipboard(shareUrl);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Share link copied: $shareUrl'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('failed to share: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _editExtractedData(BuildContext context, WidgetRef ref, ScanResponse result) {
    if (result.fileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('cannot edit: no file id available'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // create text editing controllers
    final vendorNameController = TextEditingController(text: result.extractedData?['vendor_name'] ?? '');
    final invoiceNumberController = TextEditingController(text: result.extractedData?['invoice_number'] ?? '');
    final totalController = TextEditingController(text: result.extractedData?['total']?.toString() ?? '');
    final paymentMethodController = TextEditingController(text: result.extractedData?['payment_method'] ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('edit invoice data'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('vendor name:'),
              TextField(controller: vendorNameController, decoration: const InputDecoration(hintText: 'enter vendor name')),
              const SizedBox(height: 16),
              const Text('invoice number:'),
              TextField(controller: invoiceNumberController, decoration: const InputDecoration(hintText: 'enter invoice number')),
              const SizedBox(height: 16),
              const Text('total amount:'),
              TextField(controller: totalController, decoration: const InputDecoration(hintText: 'enter total amount'), keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              const Text('payment method:'),
              TextField(controller: paymentMethodController, decoration: const InputDecoration(hintText: 'enter payment method (e.g., upi, cash, card)')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final apiClient = ref.read(invoiceApiClientProvider);
                await apiClient.editInvoiceData(result.fileId!, {
                  'extracted_data': {
                    'vendor_name': vendorNameController.text,
                    'invoice_number': invoiceNumberController.text,
                    'total': double.tryParse(totalController.text) ?? result.extractedData?['total'],
                    'payment_method': paymentMethodController.text,
                  }
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('invoice data updated successfully'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('failed to update invoice: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _approveInvoice(BuildContext context, WidgetRef ref, ScanResponse result) async {
    if (result.fileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('cannot approve: no file id available'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      await apiClient.approveInvoice(result.fileId!);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('invoice ${result.fileId} approved successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      // optionally refresh the screen or navigate back
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('failed to approve invoice: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildRiskGauge(double score) {
    final progress = score / 100;
    return Stack(
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 12,
            backgroundColor: AppColors.loadingShimmer,
            valueColor: AlwaysStoppedAnimation<Color>(
              _getRiskColor(score < 33 ? 'low' : score < 66 ? 'medium' : 'high'),
            ),
          ),
        ),
        Center(
          child: Text(
            '${score.toInt()}',
            style: AppTypography.displayLarge.copyWith(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: _getRiskColor(score < 33 ? 'low' : score < 66 ? 'medium' : 'high'),
            ),
          ),
        ),
      ],
    );
  }

  Color _getRiskColor(String? level) {
    switch (level?.toLowerCase()) {
      case 'low':
        return AppColors.riskLow;
      case 'medium':
        return AppColors.riskMedium;
      case 'high':
        return AppColors.riskHigh;
      case 'critical':
        return AppColors.riskCritical;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildRiskBadge(String? riskLevel) {
    final color = _getRiskColor(riskLevel);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        riskLevel?.toUpperCase() ?? 'UNKNOWN',
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildExpandableCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: AppElevation.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: AppTypography.titleMedium,
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedData(Map<String, dynamic>? data) {
    if (data == null) {
      return const Text('No data extracted');
    }

    try {
      final fields = [
        {'key': 'vendor_name', 'label': 'Vendor'},
        {'key': 'invoice_number', 'label': 'Invoice Number'},
        {'key': 'invoice_date', 'label': 'Invoice Date'},
        {'key': 'subtotal', 'label': 'Subtotal'},
        {'key': 'tax', 'label': 'Tax'},
        {'key': 'total', 'label': 'Total'},
        {'key': 'payment_method', 'label': 'Payment Method'},
        {'key': 'vendor_address', 'label': 'Vendor Address'},
        {'key': 'vendor_phone', 'label': 'Vendor Phone'},
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Validation Score
          if (data['validation_score'] != null)
          Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    'Validation Score:',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${data['validation_score']}/100',
                    style: AppTypography.bodyMedium.copyWith(
                      color: data['validation_score'] >= 80 ? AppColors.success : AppColors.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Basic fields
        ...fields.map((field) {
          final value = data[field['key']];
          return Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    '${field['label']}:',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value?.toString() ?? 'Not found',
                    style: AppTypography.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        
        // Line items section
        if (data['line_items'] != null && data['line_items'] is List && (data['line_items'] as List).isNotEmpty) ...[
          SizedBox(height: AppSpacing.md),
          Text(
            'Line Items:',
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DataTable(
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Description', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Price', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: (data['line_items'] as List).asMap().entries.map((entry) {
                int index = entry.key + 1;
                var item = entry.value;
                return DataRow(
                  cells: [
                    DataCell(Text('$index')),
                    DataCell(Text(item['description']?.toString() ?? '')),
                    DataCell(Text('${item['quantity']?.toString() ?? ''} ${item['unit']?.toString() ?? ''}')),
                    DataCell(Text(item['unit_price']?.toStringAsFixed(2) ?? '')),
                    DataCell(Text(item['amount']?.toStringAsFixed(2) ?? '')),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
    } catch (e) {
      print('❌ Error rendering extracted data: $e');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Error displaying extracted data',
            style: AppTypography.bodyMedium.copyWith(color: Colors.red),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Some fields may be missing or have unexpected format',
            style: AppTypography.bodySmall,
          ),
        ],
      );
    }
  }

  Widget _buildValidationResults(Map<String, dynamic>? data) {
    if (data == null) {
      return const Text('No validation results');
    }

    // Get math validation score from checks
    final mathValidation = data['checks']?['math_validation'];
    final mathScore = mathValidation?['score'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Math Validation Score: ${mathScore.toString()}/100',
          style: AppTypography.bodyMedium.copyWith(
            color: mathScore >= 80 ? AppColors.success : (mathScore >= 50 ? AppColors.warning : AppColors.error),
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        if (mathValidation != null && mathValidation['findings'] != null && (mathValidation['findings'] as List).isNotEmpty)
          Text(
            'Issues Found: ${(mathValidation['findings'] as List).length}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.warning,
            ),
          ),
        SizedBox(height: AppSpacing.sm),
        SizedBox(height: AppSpacing.sm),
        if (data['field_validations'] != null)
          ...List<Map<String, dynamic>>.from(data['field_validations'])
              .map((field) => Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                          field['is_valid'] == true ? Icons.check_circle : Icons.cancel,
                          color: field['is_valid'] == true
                              ? AppColors.success
                              : AppColors.error,
                          size: 20,
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          field['field'] ?? 'Unknown field',
                          style: AppTypography.bodyMedium,
                        ),
                      ],
                    ),
                  )),
      ],
    );
  }

  Widget _buildMLAnalysis(Map<String, dynamic>? data) {
    if (data == null) {
      return const Text('No ML analysis results');
    }

    final anomalyScore = data['anomaly_score'] as double?;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          anomalyScore != null && anomalyScore > 0
              ? 'Anomaly Score: ${anomalyScore.toStringAsFixed(1)}/100'
              : 'Anomaly Score: Not calculated (insufficient data)',
          style: AppTypography.bodyMedium.copyWith(
            color: anomalyScore != null
                ? (anomalyScore < 30 ? AppColors.success : AppColors.warning)
                : AppColors.textSecondary,
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        if (data['anomalies_detected'] != null)
          Text(
            'Anomalies Detected: ${data['anomalies_detected'] ? 'Yes' : 'No'}',
            style: AppTypography.bodyMedium.copyWith(
              color: data['anomalies_detected']
                  ? AppColors.warning
                  : AppColors.success,
            ),
          ),
      ],
    );
  }

  Widget _buildAIChat() {
    return Column(
      children: [
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: ListView.builder(
            controller: _chatScrollController,
            padding: EdgeInsets.all(AppSpacing.md),
            itemCount: _chatMessages.length,
            itemBuilder: (context, index) {
              final message = _chatMessages[index];
              final isUser = message.role == 'user';
              return Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isUser)
                      Icon(Icons.person, size: 20, color: AppColors.primary)
                    else
                      Icon(Icons.smart_toy, size: 20, color: AppColors.secondary),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: isUser ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          message.content,
                          style: AppTypography.bodyMedium.copyWith(
                            color: isUser ? Colors.black87 : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                decoration: InputDecoration(
                  hintText: 'Ask about this invoice...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
                onSubmitted: (_) => _sendChatMessage(),
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: _isChatLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send, color: AppColors.primary),
              onPressed: _isChatLoading ? null : _sendChatMessage,
            ),
          ],
        ),
        if (_chatMessages.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Ask questions about this invoice (e.g., "What is the total amount?", "Explain the validation findings")',
              style: AppTypography.bodySmall.copyWith(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _verifyInvoice(BuildContext context, WidgetRef ref, ScanResponse result) async {
    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      await apiClient.verifyInvoice(
        result.fileId ?? '',
        verified: true,
        notes: 'Verified by user',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice verified successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to verify invoice: $e')),
        );
      }
    }
  }

  Future<void> _viewAuditHistory(BuildContext context, WidgetRef ref, ScanResponse result) async {
    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      final response = await apiClient.getInvoiceAuditHistory(result.fileId ?? '');
      
      if (!context.mounted) return;
      
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Audit History'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: response['audit_history']?.length ?? 0,
              itemBuilder: (context, index) {
                final log = response['audit_history'][index];
                return ListTile(
                  title: Text(log['action']?.toUpperCase() ?? 'Unknown'),
                  subtitle: Text(log['details'] ?? ''),
                  trailing: Text(log['created_at']?.substring(0, 10) ?? ''),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load audit history: $e')),
        );
      }
    }
  }
}
