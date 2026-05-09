import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../layouts/main_layout.dart';
import '../../../core/providers/api_providers.dart';

/// Scan history screen with real data fetching
class ScanHistoryScreen extends ConsumerStatefulWidget {
  const ScanHistoryScreen({super.key});

  @override
  ConsumerState<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends ConsumerState<ScanHistoryScreen> {
  List<dynamic> _scans = [];
  List<dynamic> _filteredScans = [];
  bool _isLoading = true;
  String? _error;
  String _filterStatus = 'all'; // all, verified, unverified

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      final response = await apiClient.getInvoices(limit: 50);
      
      setState(() {
        _scans = response['invoices'] as List<dynamic>? ?? [];
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    if (_filterStatus == 'all') {
      _filteredScans = _scans;
    } else if (_filterStatus == 'verified') {
      _filteredScans = _scans.where((scan) => scan['verified'] == true).toList();
    } else if (_filterStatus == 'unverified') {
      _filteredScans = _scans.where((scan) => scan['verified'] != true).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadHistory,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scan History',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'View past invoice scans and their verification status',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  SizedBox(height: 32),
                  _buildFilterBar(),
                  SizedBox(height: 16),
                  SizedBox(
                    height: 400,
                    child: _buildBody(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            const Text('Filter: ', style: TextStyle(fontWeight: FontWeight.w600)),
            FilterChip(
              label: const Text('All'),
              selected: _filterStatus == 'all',
              onSelected: (selected) {
                setState(() {
                  _filterStatus = 'all';
                  _applyFilter();
                });
              },
            ),
            FilterChip(
              label: const Text('Verified'),
              selected: _filterStatus == 'verified',
              onSelected: (selected) {
                setState(() {
                  _filterStatus = 'verified';
                  _applyFilter();
                });
              },
            ),
            FilterChip(
              label: const Text('Unverified'),
              selected: _filterStatus == 'unverified',
              onSelected: (selected) {
                setState(() {
                  _filterStatus = 'unverified';
                  _applyFilter();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error loading history: $_error', style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadHistory,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredScans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No scans found',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredScans.length,
      itemBuilder: (context, index) {
        final scan = _filteredScans[index];
        return _buildScanCard(scan);
      },
    );
  }

  Widget _buildScanCard(dynamic scan) {
    final vendorName = scan['vendor_name'] ?? 'Unknown Vendor';
    final invoiceDate = scan['invoice_date'] ?? 'No date';
    final total = scan['total']?.toString() ?? '0.00';
    final riskLevel = scan['risk_level'] ?? 'UNKNOWN';
    final verified = scan['verified'] == true;
    final approvedBy = scan['approved_by'];
    final fileId = scan['file_id'];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(_getRiskIcon(riskLevel)),
        title: Text(vendorName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$invoiceDate • ₹$total', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: Text(
                    riskLevel.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  backgroundColor: _getRiskColor(riskLevel),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Chip(
                  label: Text(
                    verified ? 'VERIFIED' : 'UNVERIFIED',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  backgroundColor: verified ? Colors.green : Colors.orange,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                if (approvedBy != null) ...[
                  const SizedBox(width: 4),
                  Chip(
                    label: Text(
                      'APPROVED',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    backgroundColor: Colors.blue,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.history),
          onPressed: () => _showAuditHistory(fileId),
          tooltip: 'View audit history',
        ),
        onTap: () => _showScanDetails(scan),
      ),
    );
  }

  IconData _getRiskIcon(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return Icons.warning;
      case 'medium':
        return Icons.info;
      case 'low':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showScanDetails(dynamic scan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(scan['vendor_name'] ?? 'Unknown'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Total', '₹${scan['total']?.toString() ?? 'N/A'}'),
              _detailRow('Date', scan['invoice_date'] ?? 'N/A'),
              _detailRow('Risk Level', scan['risk_level'] ?? 'N/A'),
              _detailRow('Verified', scan['verified'] == true ? 'Yes' : 'No'),
              if (scan['approved_by'] != null)
                _detailRow('Approved By', scan['approved_by']),
              if (scan['edited_by'] != null)
                _detailRow('Edited By', scan['edited_by']),
              _detailRow('Invoice Number', scan['invoice_number'] ?? 'N/A'),
            ],
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
  }

  Future<void> _showAuditHistory(String? fileId) async {
    if (fileId == null) return;

    try {
      final apiClient = ref.read(invoiceApiClientProvider);
      final response = await apiClient.dio.get('/api/invoices/$fileId/audit');
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Audit History'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: response.data['audit_history']?.length ?? 0,
              itemBuilder: (context, index) {
                final log = response.data['audit_history'][index];
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load audit history: $e')),
        );
      }
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
