import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoice_forgery_detection/core/api/api_client.dart';
import 'package:invoice_forgery_detection/core/providers/api_providers.dart';
import 'package:invoice_forgery_detection/core/services/file_download_service.dart';
import '../providers/analytics_provider.dart';
import '../widgets/risk_distribution_chart.dart';
import '../widgets/vendor_frequency_table.dart';
import '../widgets/verification_status_cards.dart';
import '../utils/chart_formatters.dart';
import '../../../layouts/main_layout.dart';
import 'package:dio/dio.dart';

/// Analytics dashboard screen
class AnalyticsDashboardScreen extends ConsumerStatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  ConsumerState<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends ConsumerState<AnalyticsDashboardScreen> {
  DateTimeRange? _selectedDateRange;

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      
      // Update analytics provider with custom date range
      ref.read(analyticsProvider.notifier).setCustomDateRange(
        picked.start,
        picked.end,
      );
      
      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Filtered: ${_formatDate(picked.start)} to ${_formatDate(picked.end)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDateRange = null;
    });
    ref.read(analyticsProvider.notifier).setTimeRange(TimeRange.last7Days);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Date filter cleared'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final analyticsState = ref.watch(analyticsProvider);
    
    return MainLayout(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_selectedDateRange != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearDateFilter,
                    tooltip: 'Clear filter',
                  ),
                Badge(
                  isLabelVisible: _selectedDateRange != null,
                  label: const Text('1'),
                  child: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: _selectDateRange,
                    tooltip: _selectedDateRange != null 
                        ? 'Filter: ${_formatDate(_selectedDateRange!.start)} - ${_formatDate(_selectedDateRange!.end)}'
                        : 'Filter by Date Range',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () => _exportAnalytics(ref),
                  tooltip: 'Export',
                ),
              ],
            ),
          ),
          Expanded(
            child: analyticsState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : analyticsState.error != null
                    ? _buildError(context, analyticsState.error!, ref)
                    : analyticsState.data != null
                        ? _buildContent(context, analyticsState.data!)
                        : _buildEmpty(context),
          ),
        ],
      ),
    );
  }
  
  Widget _buildContent(BuildContext context, AnalyticsData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analytics Dashboard',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'View scan statistics and forgery detection metrics',
            style: TextStyle(color: Colors.grey[600]),
          ),
          SizedBox(height: 32),
          AnalyticsSummaryCards(
            totalScans: data.totalScans,
            highRiskScans: data.highRiskScans,
            mediumRiskScans: data.mediumRiskScans,
            lowRiskScans: data.lowRiskScans,
            averageConfidence: data.averageConfidence,
          ),
          SizedBox(height: 32),
          VerificationStatusCards(
            verifiedScans: data.verifiedScans,
            unverifiedScans: data.unverifiedScans,
            approvedScans: data.approvedScans,
            editedScans: data.editedScans,
          ),
          SizedBox(height: 32),
          RiskDistributionChart(
            data: {
              'high': data.highRiskScans,
              'medium': data.mediumRiskScans,
              'low': data.lowRiskScans,
            },
          ),
          SizedBox(height: 32),
          if (data.riskTrend.isNotEmpty)
            RiskTrendChart(trendData: data.riskTrend),
          SizedBox(height: 32),
          VendorFrequencyTable(vendors: data.topVendors),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
  
  Widget _buildEmpty(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analytics Dashboard',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'View scan statistics and forgery detection metrics',
            style: TextStyle(color: Colors.grey[600]),
          ),
          SizedBox(height: 32),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.analytics_outlined,
                  size: 64,
                  color: Colors.grey[600],
                ),
                const SizedBox(height: 16),
                Text(
                  'No analytics data available',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start scanning invoices to see analytics',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildError(BuildContext context, String error, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analytics Dashboard',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'View scan statistics and forgery detection metrics',
            style: TextStyle(color: Colors.grey[600]),
          ),
          SizedBox(height: 32),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load analytics',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(analyticsProvider.notifier).fetchAnalytics();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _exportAnalytics(WidgetRef ref) async {
    final apiClient = ref.read(invoiceApiClientProvider);
    
    // Show format selection dialog
    final format = await showDialog<String>(
      context: ref.context,
      builder: (context) => AlertDialog(
        title: const Text('Export Analytics'),
        content: const Text('Select export format:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'csv'),
            child: const Text('CSV'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'pdf'),
            child: const Text('PDF'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    
    if (format == null) return;
    
    try {
      // Use Dio directly for binary response
      final response = await apiClient.dio.get(
        '/api/analytics/export',
        queryParameters: {'format': format},
        options: Options(responseType: ResponseType.bytes),
      );
      
      if (response.statusCode == 200) {
        try {
          await FileDownloadService.downloadFile(
            filename: 'analytics_report.$format',
            bytes: response.data,
            mimeType: format == 'csv' ? 'text/csv' : 'application/pdf',
          );
        } catch (e) {
          // Show message for desktop platforms where download is not implemented yet
          FileDownloadService.showDownloadNotAvailableMessage(
            ref.context,
            'analytics_report.$format',
          );
          return;
        }
        
        ScaffoldMessenger.of(ref.context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Text('Report downloaded: analytics_report.$format'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(ref.context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
