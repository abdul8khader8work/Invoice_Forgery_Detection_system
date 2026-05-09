import 'package:flutter/material.dart';
import '../providers/analytics_provider.dart';
import '../utils/chart_formatters.dart';

/// Vendor frequency table widget
class VendorFrequencyTable extends StatelessWidget {
  final List<VendorData> vendors;
  
  const VendorFrequencyTable({
    super.key,
    required this.vendors,
  });
  
  @override
  Widget build(BuildContext context) {
    if (vendors.isEmpty) {
      return _buildEmptyTable();
    }
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Vendors by Scan Count',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(
                    label: Text(
                      'Vendor Name',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Scans',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(
                      'High Risk',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(
                      'Avg Risk Score',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    numeric: true,
                  ),
                ],
                rows: vendors.map((vendor) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          vendor.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      DataCell(
                        Text(ChartFormatters.formatNumber(vendor.scanCount)),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: vendor.highRiskCount > 0
                                ? Colors.red[100]
                                : Colors.green[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ChartFormatters.formatNumber(vendor.highRiskCount),
                            style: TextStyle(
                              color: vendor.highRiskCount > 0
                                  ? Colors.red[700]
                                  : Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _getRiskColor(vendor.averageRiskScore),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              ChartFormatters.formatRiskScore(vendor.averageRiskScore),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyTable() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.table_chart,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No vendor data available',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Color _getRiskColor(double score) {
    if (score >= 0.7) return const Color(0xFFEF4444);
    if (score >= 0.4) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }
}

/// Analytics summary cards widget
class AnalyticsSummaryCards extends StatelessWidget {
  final int totalScans;
  final int highRiskScans;
  final int mediumRiskScans;
  final int lowRiskScans;
  final double averageConfidence;

  const AnalyticsSummaryCards({
    super.key,
    required this.totalScans,
    required this.highRiskScans,
    required this.mediumRiskScans,
    required this.lowRiskScans,
    required this.averageConfidence,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: isMobile ? 12 : 16,
        crossAxisSpacing: isMobile ? 12 : 16,
        childAspectRatio: isMobile ? 1.2 : 1.5,
        children: [
          _buildSummaryCard(
            'Total Scans',
            ChartFormatters.formatNumber(totalScans),
            Icons.scanner,
            Colors.blue,
            isMobile,
          ),
          _buildSummaryCard(
            'High Risk',
            ChartFormatters.formatNumber(highRiskScans),
            Icons.warning,
            Colors.red,
            isMobile,
          ),
          _buildSummaryCard(
            'Medium Risk',
            ChartFormatters.formatNumber(mediumRiskScans),
            Icons.info,
            Colors.orange,
            isMobile,
          ),
          _buildSummaryCard(
            'Avg Confidence',
            ChartFormatters.formatPercentage(averageConfidence),
            Icons.trending_up,
            Colors.green,
            isMobile,
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, bool isMobile) {
    return SizedBox(
      height: isMobile ? 100 : 120,
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: isMobile ? 28 : 32),
              SizedBox(height: isMobile ? 6 : 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 10 : 12,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: isMobile ? 2 : 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: isMobile ? 18 : 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
