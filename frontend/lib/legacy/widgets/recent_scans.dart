import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/scan_result.dart';
import '../services/api_service.dart';
import '../screens/invoice_preview_screen.dart';
import '../utils/file_downloader.dart';

class RecentScans extends StatefulWidget {
  const RecentScans({super.key});

  @override
  State<RecentScans> createState() => _RecentScansState();
}

class _RecentScansState extends State<RecentScans> {
  final ApiService _apiService = ApiService();
  List<ScanResult> _invoices = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final invoicesList = await _apiService.getInvoices(limit: 10);
      
      setState(() {
        _invoices = invoicesList
            .map((json) => ScanResult.fromJson(json))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load invoices: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading recent scans...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.error, color: Colors.red[400], size: 48),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700]),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadInvoices,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_invoices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              Icons.folder_open,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No recent scans',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload your first invoice to get started',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Scans (${_invoices.length})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadInvoices,
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _invoices.length,
          itemBuilder: (context, index) {
            final invoice = _invoices[index];
            return _buildInvoiceCard(invoice);
          },
        ),
      ],
    );
  }

  Widget _buildInvoiceCard(ScanResult invoice) {
    final riskColor = _getRiskColor(invoice.riskLevel);
    final riskIcon = _getRiskIcon(invoice.riskLevel);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getFileIcon(invoice.filename),
                  color: Colors.blue,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.filename,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(invoice.timestamp),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: riskColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(riskIcon, color: riskColor, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        invoice.riskLevel.toUpperCase(),
                        style: TextStyle(
                          color: riskColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem(
                    'Vendor',
                    invoice.extractedData['vendor_name'] ?? 'Unknown',
                    Icons.business,
                  ),
                ),
                Expanded(
                  child: _buildDetailItem(
                    'Amount',
                    '\$${_formatAmount(invoice.extractedData['total'])}',
                    Icons.attach_money,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem(
                    'Invoice #',
                    invoice.extractedData['invoice_number'] ?? 'N/A',
                    Icons.receipt,
                  ),
                ),
                Expanded(
                  child: _buildDetailItem(
                    'Risk Score',
                    '${invoice.riskScore.toStringAsFixed(1)}%',
                    Icons.analytics,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _previewInvoice(invoice),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Preview'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _exportReport(invoice),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Export'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _deleteInvoice(invoice),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[400]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _previewInvoice(ScanResult invoice) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InvoicePreviewScreen(invoice: invoice),
      ),
    );
  }

  void _exportReport(ScanResult invoice) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildExportOptions(invoice),
    );
  }

  Future<void> _deleteInvoice(ScanResult invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text('Are you sure you want to delete "${invoice.filename}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiService.deleteInvoice(invoice.fileId);
        setState(() {
          _invoices.removeWhere((inv) => inv.fileId == invoice.fileId);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invoice deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  Widget _buildExportOptions(ScanResult invoice) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export Options',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose what to export for ${invoice.filename}',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
            title: const Text('Export Report as PDF'),
            subtitle: const Text('Download validation report'),
            onTap: () {
              Navigator.pop(context);
              _downloadReport(invoice, 'pdf');
            },
          ),
          ListTile(
            leading: const Icon(Icons.description, color: Colors.blue),
            title: const Text('Export Report as JSON'),
            subtitle: const Text('Download raw analysis data'),
            onTap: () {
              Navigator.pop(context);
              _downloadReport(invoice, 'json');
            },
          ),
          ListTile(
            leading: const Icon(Icons.image, color: Colors.green),
            title: const Text('Export Original Invoice'),
            subtitle: const Text('Download scanned document'),
            onTap: () {
              Navigator.pop(context);
              _downloadInvoice(invoice);
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
    );
  }

  Future<void> _downloadReport(ScanResult invoice, String format) async {
    try {
      if (format == 'JSON') {
        final reportData = {
          'file_id': invoice.fileId,
          'filename': invoice.filename,
          'extracted_data': invoice.extractedData,
          'deterministic_validation': invoice.deterministicValidation,
          'ml_analysis': invoice.mlAnalysis,
          'risk_score': invoice.riskScore,
          'risk_level': invoice.riskLevel,
          'reasoning': invoice.reasoning,
          'needs_verification': invoice.needsVerification,
          'verification_fields': invoice.verificationFields,
          'processing_time': invoice.processingTime,
          'timestamp': invoice.timestamp,
        };
        FileDownloader.downloadJson(reportData, '${invoice.filename}_report.json');
      } else if (format == 'PDF') {
        // Create a simple text representation for now (can be enhanced with pdf package)
        final pdfContent = '''
INVOICE ANALYSIS REPORT
=======================

File: ${invoice.filename}
Date: ${invoice.timestamp}
Risk Score: ${invoice.riskScore.toStringAsFixed(2)}%
Risk Level: ${invoice.riskLevel.toUpperCase()}

EXTRACTED DATA:
${invoice.extractedData.entries.map((e) => '${e.key}: ${e.value}').join('\n')}

VALIDATION RESULTS:
${invoice.deterministicValidation.entries.map((e) => '${e.key}: ${e.value}').join('\n')}

REASONING:
${invoice.reasoning.join('\n')}

ML ANALYSIS:
${invoice.mlAnalysis.entries.map((e) => '${e.key}: ${e.value}').join('\n')}
''';
        FileDownloader.downloadText(pdfContent, '${invoice.filename}_report.txt');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report downloaded as $format'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadInvoice(ScanResult invoice) async {
    try {
      if (invoice.fileBytes != null) {
        final ext = invoice.filename.split('.').last.toLowerCase();
        String mimeType = 'application/octet-stream';
        if (['jpg', 'jpeg'].contains(ext)) mimeType = 'image/jpeg';
        else if (ext == 'png') mimeType = 'image/png';
        else if (ext == 'pdf') mimeType = 'application/pdf';
        
        FileDownloader.downloadBytes(invoice.fileBytes!, invoice.filename, mimeType);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Original invoice downloaded'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Original file not available for download'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

  IconData _getRiskIcon(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return Icons.warning;
      case 'medium':
        return Icons.info;
      case 'low':
      default:
        return Icons.check_circle;
    }
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
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

  String _formatDate(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
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
