import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/scan_result.dart';
import '../services/api_service.dart';

class InvoicePreviewScreen extends StatefulWidget {
  final ScanResult invoice;

  const InvoicePreviewScreen({
    Key? key,
    required this.invoice,
  }) : super(key: key);

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  int _currentTab = 0;
  bool _isLoadingImage = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.invoice.filename),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _showExportOptions(),
            tooltip: 'Export',
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab selector
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    'Invoice & Report',
                    0,
                    Icons.splitscreen,
                  ),
                ),
                Expanded(
                  child: _buildTabButton(
                    'Invoice Only',
                    1,
                    Icons.image,
                  ),
                ),
                Expanded(
                  child: _buildTabButton(
                    'Report Only',
                    2,
                    Icons.assessment,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index, IconData icon) {
    final isSelected = _currentTab == index;
    return InkWell(
      onTap: () => setState(() => _currentTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.blue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.blue : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentTab) {
      case 0:
        return _buildSplitView();
      case 1:
        return _buildInvoiceView();
      case 2:
        return _buildReportView();
      default:
        return _buildSplitView();
    }
  }

  Widget _buildSplitView() {
    return Row(
      children: [
        // Left side - Invoice
        Expanded(
          flex: 1,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.image, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Original Invoice',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildInvoiceImage(),
                ),
              ],
            ),
          ),
        ),
        // Right side - Report
        Expanded(
          flex: 1,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.assessment, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Validation Report',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildReportContent(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _buildInvoiceImage(),
      ),
    );
  }

  Widget _buildReportView() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: _buildReportContent(),
    );
  }

  Widget _buildInvoiceImage() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getFileIcon(),
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              widget.invoice.filename,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Invoice preview not available',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _downloadInvoice(),
              icon: const Icon(Icons.download),
              label: const Text('Download Original'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Risk Assessment Card
          _buildRiskCard(),
          const SizedBox(height: 16),

          // Invoice Details Card
          _buildDetailsCard(),
          const SizedBox(height: 16),

          // Validation Results Card
          _buildValidationCard(),
          const SizedBox(height: 16),

          // ML Analysis Card
          _buildMLAnalysisCard(),
          const SizedBox(height: 16),

          // Reasoning Card
          _buildReasoningCard(),
        ],
      ),
    );
  }

  Widget _buildRiskCard() {
    final riskColor = _getRiskColor(widget.invoice.riskLevel);

    return Card(
      color: riskColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _getRiskIcon(),
              size: 48,
              color: riskColor,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Risk Assessment',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.invoice.riskLevel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: riskColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Risk Score: ${widget.invoice.riskScore.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Invoice Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Vendor', widget.invoice.extractedData['vendor_name'] ?? 'Unknown'),
            _buildDetailRow('Invoice Number', widget.invoice.extractedData['invoice_number'] ?? 'N/A'),
            _buildDetailRow('Invoice Date', widget.invoice.extractedData['invoice_date'] ?? 'N/A'),
            _buildDetailRow('Subtotal', '\$${_formatAmount(widget.invoice.extractedData['subtotal'])}'),
            _buildDetailRow('Tax', '\$${_formatAmount(widget.invoice.extractedData['tax'])}'),
            _buildDetailRow('Total', '\$${_formatAmount(widget.invoice.extractedData['total'])}', isBold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationCard() {
    final validation = widget.invoice.deterministicValidation;
    final passed = validation['passed'] ?? false;
    final checks = validation['checks'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  passed ? Icons.check_circle : Icons.warning,
                  color: passed ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Validation Checks',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...checks.entries.map((entry) {
              final checkData = entry.value as Map<String, dynamic>;
              final checkPassed = checkData['passed'] ?? false;
              return _buildCheckItem(
                entry.key.replaceAll('_', ' ').toUpperCase(),
                checkPassed,
                checkData['reason'] ?? '',
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildMLAnalysisCard() {
    final ml = widget.invoice.mlAnalysis;
    final isAnomaly = ml['is_anomaly'] ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ML Analysis',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Anomaly Detected', isAnomaly ? 'Yes' : 'No'),
            _buildDetailRow('Anomaly Score', '${(ml['anomaly_score'] ?? 0).toStringAsFixed(2)}'),
            _buildDetailRow('Anomaly Reason', ml['anomaly_reason'] ?? 'N/A'),
            _buildDetailRow('Confidence', '${((ml['confidence'] ?? 0) * 100).toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }

  Widget _buildReasoningCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Analysis Reasoning',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...widget.invoice.reasoning.map((reason) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_right, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(reason),
                  ),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String label, bool passed, String reason) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.cancel,
            color: passed ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                if (reason.isNotEmpty)
                  Text(
                    reason,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export Options',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Export Report as PDF'),
              onTap: () {
                Navigator.pop(context);
                _exportPDF();
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.blue),
              title: const Text('Export Report as JSON'),
              onTap: () {
                Navigator.pop(context);
                _exportJSON();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.green),
              title: const Text('Export Original Invoice'),
              onTap: () {
                Navigator.pop(context);
                _downloadInvoice();
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPDF() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Exporting report as PDF...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportJSON() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Exporting report as JSON...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _downloadInvoice() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloading invoice...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  IconData _getFileIcon() {
    final ext = widget.invoice.filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
      default:
        return Colors.green;
    }
  }

  IconData _getRiskIcon() {
    switch (widget.invoice.riskLevel.toLowerCase()) {
      case 'high':
        return Icons.warning;
      case 'medium':
        return Icons.info;
      case 'low':
      default:
        return Icons.check_circle;
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0.00';
    if (amount is double || amount is int) {
      return amount.toStringAsFixed(2);
    }
    return amount.toString();
  }
}
