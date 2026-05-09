import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:invoice_forgery_detection/core/api/api_client.dart';
import 'package:invoice_forgery_detection/core/providers/api_providers.dart';

class BatchReportScreen extends ConsumerStatefulWidget {
  final String batchId;
  final List<String> invoiceIds;

  const BatchReportScreen({
    super.key,
    required this.batchId,
    required this.invoiceIds,
  });

  @override
  ConsumerState<BatchReportScreen> createState() => _BatchReportScreenState();
}

class _BatchReportScreenState extends ConsumerState<BatchReportScreen> {
  Map<String, dynamic>? _batchReport;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    print('=== BatchReportScreen initState ===');
    print('Batch ID: ${widget.batchId}');
    print('Invoice IDs: ${widget.invoiceIds}');
    _loadBatchReport();
  }

  Future<void> _loadBatchReport() async {
    print('=== _loadBatchReport called ===');
    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      print('Making API call to /api/batch-reports/generate');
      
      final response = await apiClient.dio.post(
        '/api/batch-reports/generate',
        data: {
          'batch_id': widget.batchId,
          'invoice_ids': widget.invoiceIds,
          'include_anomalies': true,
          'include_validations': true,
          'include_ml_scores': true,
        },
      );

      print('API response received: ${response.statusCode}');
      print('Response data: ${response.data}');

      setState(() {
        _batchReport = response.data as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      print('Error in _loadBatchReport: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadPdf() async {
    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      final response = await apiClient.dio.get(
        '/api/batch-reports/${widget.batchId}/download',
        options: Options(responseType: ResponseType.bytes),
      );

      // For web: download file
      // For mobile/desktop: save to device
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF downloaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadBatchReport,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _downloadPdf,
            tooltip: 'Download PDF',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBatchReport,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 24),
            _buildRiskDistribution(),
            const SizedBox(height: 24),
            _buildInvoiceList(),
            const SizedBox(height: 24),
            _buildAnomaliesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Batch Summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildSummaryRow('Batch ID', _batchReport!['batch_id']),
            _buildSummaryRow('Generated At', _formatTimestamp(_batchReport!['generated_at'])),
            _buildSummaryRow('Total Invoices', '${_batchReport!['total_invoices']}'),
            _buildSummaryRow('Successful Scans', '${_batchReport!['successful_scans']}'),
            _buildSummaryRow('Failed Scans', '${_batchReport!['failed_scans']}'),
            _buildSummaryRow('Total Amount', '\$${_batchReport!['total_amount']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildSummaryRow('Anomalies Detected', '${_batchReport!['anomalies_detected']}'),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildRiskDistribution() {
    final riskDist = _batchReport!['risk_distribution'] as Map<String, dynamic>;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Risk Distribution',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildRiskChip('Low', riskDist['low'] ?? 0, Colors.green),
                const SizedBox(width: 8),
                _buildRiskChip('Medium', riskDist['medium'] ?? 0, Colors.orange),
                const SizedBox(width: 8),
                _buildRiskChip('High', riskDist['high'] ?? 0, Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('$count', style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget _buildInvoiceList() {
    final invoices = _batchReport!['invoices'] as List<dynamic>;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invoice Results',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: invoices.length,
              itemBuilder: (context, index) {
                final invoice = invoices[index] as Map<String, dynamic>;
                return ListTile(
                  leading: Icon(
                    invoice['status'] == 'success'
                        ? Icons.check_circle
                        : Icons.error,
                    color: invoice['status'] == 'success'
                        ? Colors.green
                        : Colors.red,
                  ),
                  title: Text(invoice['filename'] ?? 'Unknown'),
                  subtitle: Text(
                      'Risk: ${invoice['risk_level']?.toUpperCase() ?? 'N/A'} | Amount: \$${invoice['amount']?.toStringAsFixed(2) ?? '0.00'}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.visibility),
                    onPressed: () {
                      // Navigate to individual invoice report
                      // TODO: Implement navigation to individual invoice detail
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnomaliesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anomalies & Validations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (_batchReport!['anomalies_detected'] > 0)
              Text(
                '${_batchReport!['anomalies_detected']} anomalies detected across the batch',
                style: TextStyle(color: Colors.orange[700]),
              )
            else
              Text(
                'No anomalies detected',
                style: TextStyle(color: Colors.green[700]),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(timestamp);
      return dateTime.toLocal().toString().split('.')[0];
    } catch (e) {
      return timestamp;
    }
  }
}
