import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/analytics_provider.dart';
import '../utils/chart_formatters.dart';

/// Risk distribution pie chart widget
class RiskDistributionChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const RiskDistributionChart({super.key, required this.data});
  
  @override
  Widget build(BuildContext context) {
    // ✅ FIX 1: Extract data correctly from API response
    final highRisk = data['high'] ?? 0;
    final mediumRisk = data['medium'] ?? 0;
    final lowRisk = data['low'] ?? 0;
    final total = highRisk + mediumRisk + lowRisk;

    // Handle empty state
    if (total == 0) {
      return _buildEmptyState();
    }

    // ✅ FIX 2: Calculate percentages correctly
    final highPercent = ((highRisk / total) * 100).toStringAsFixed(1);
    final mediumPercent = ((mediumRisk / total) * 100).toStringAsFixed(1);
    final lowPercent = ((lowRisk / total) * 100).toStringAsFixed(1);

    print('📊 Risk Distribution:');
    print('   High: $highRisk ($highPercent%)');
    print('   Medium: $mediumRisk ($mediumPercent%)');
    print('   Low: $lowRisk ($lowPercent%)');
    print('   Total: $total');
    
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Risk Distribution',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                // ✅ FIX 3: Pie chart with correct percentages
                Expanded(
                  child: SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sections: [
                          // High Risk Section
                          PieChartSectionData(
                            value: highRisk.toDouble(),
                            title: highRisk > 0 ? '$highPercent%' : '',
                            color: Colors.red,
                            radius: 80,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          // Medium Risk Section
                          PieChartSectionData(
                            value: mediumRisk.toDouble(),
                            title: mediumRisk > 0 ? '$mediumPercent%' : '',
                            color: Colors.orange,
                            radius: 80,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          // Low Risk Section
                          PieChartSectionData(
                            value: lowRisk.toDouble(),
                            title: lowRisk > 0 ? '$lowPercent%' : '',
                            color: Colors.green,
                            radius: 80,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        sectionsSpace: 2,
                        centerSpaceRadius: 60,
                        startDegreeOffset: 90, // ✅ Start from top
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 32),
                // ✅ FIX 4: Legend with actual counts
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLegendItem('High Risk', highRisk, Colors.red, highPercent),
                      const SizedBox(height: 12),
                      _buildLegendItem('Medium Risk', mediumRisk, Colors.orange, mediumPercent),
                      const SizedBox(height: 12),
                      _buildLegendItem('Low Risk', lowRisk, Colors.green, lowPercent),
                    ],
                  ),
                ),
              ],
            ),
            // ✅ FIX 5: Show total count
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Total Invoices: $total',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyChart() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.pie_chart_outline,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No data available',
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
  
  Widget _buildLegendItem(String label, int count, Color color, String percent) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.pie_chart_outline,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No data available',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload invoices to see risk distribution',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Risk trend line chart widget
class RiskTrendChart extends StatelessWidget {
  final List<RiskTrendData> trendData;
  
  const RiskTrendChart({
    super.key,
    required this.trendData,
  });
  
  @override
  Widget build(BuildContext context) {
    if (trendData.isEmpty) {
      return _buildEmptyChart();
    }
    
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      // ✅ FIX 1: Allow tooltip overflow
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.only(
          left: 16,
          top: 16,
          right: 100, // ✅ Extra 100px on right for tooltips
          bottom: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Risk Trend Over Time',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // ✅ FIX 2: Add extra padding for tooltips
            SizedBox(
              height: 300, // Increased from 250
              child: Stack(
                clipBehavior: Clip.none, // ✅ Allow overflow
                children: [
                  LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: _calculateYInterval(),
                        verticalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey[200],
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.grey[200],
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: _calculateYInterval(),
                        reservedSize: 30, // ✅ More space for numbers
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40, // ✅ More space for dates
                        interval: _calculateXInterval(),
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < trendData.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                ChartFormatters.formatDateString(
                                  trendData[value.toInt()].date,
                                  format: 'MMM dd',
                                ),
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (trendData.length - 1).toDouble(),
                  minY: 0,
                  maxY: _getMaxCount() + 2, // ✅ Add buffer at top
                  lineBarsData: [
                    _buildLineBar(trendData, 'highRisk', const Color(0xFFDC2626)),
                    _buildLineBar(trendData, 'mediumRisk', const Color(0xFFF97316)),
                    _buildLineBar(trendData, 'lowRisk', const Color(0xFF059669)),
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    // ✅ FIX 4: Better tooltip positioning
                    touchTooltipData: LineTouchTooltipData(
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      tooltipMargin: 20, // ✅ Increased margin for edge points
                      tooltipRoundedRadius: 8,
                      // ✅ FIX 5: Tooltip styling (fl_chart 0.69.2 compatible)
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((touchedSpot) {
                          final color = touchedSpot.bar.color!;
                          final label = color == const Color(0xFFDC2626) 
                              ? 'High Risk' 
                              : color == const Color(0xFFF97316) 
                                  ? 'Medium Risk' 
                                  : 'Low Risk';
                          
                          // ✅ FIX: Add edge detection in tooltip text
                          final isLastPoint = touchedSpot.x.toInt() == trendData.length - 1;
                          final isFirstPoint = touchedSpot.x.toInt() == 0;
                          final edgeIndicator = isLastPoint ? ' ←' : isFirstPoint ? ' →' : '';
                          
                          return LineTooltipItem(
                            '$label: ${touchedSpot.y.toInt()}$edgeIndicator',
                            TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              backgroundColor: Colors.blueGrey[800],
                            ),
                          );
                        }).toList();
                      },
                    ),
                    // ✅ FIX 6: Handle edge cases for tooltips
                    getTouchedSpotIndicator: (barData, spotIndexes) {
                      return spotIndexes.map((spotIndex) {
                        return TouchedSpotIndicatorData(
                          FlLine(
                            color: Colors.grey[400],
                            strokeWidth: 1,
                          ),
                          FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, bar, index) {
                              return FlDotCirclePainter(
                                radius: 8, // ✅ Larger indicator on hover
                                color: bar.color!.withOpacity(0.3),
                              );
                            },
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
                ], // ✅ Close Stack children
              ),
            ),
            const SizedBox(height: 16),
            _buildTrendLegend(),
          ],
        ),
      ),
    );
  }
  
  LineChartBarData _buildLineBar(List<RiskTrendData> data, String riskField, Color color) {
    return LineChartBarData(
      color: color,
      isCurved: true,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) {
          return FlDotCirclePainter(
            radius: 5, // ✅ Larger dots for easier hover
            color: color,
            strokeWidth: 2,
            strokeColor: Colors.white,
          );
        },
      ),
      belowBarData: BarAreaData(show: false),
      spots: List.generate(
        data.length,
        (index) => FlSpot(
          index.toDouble(),
          _getRiskValue(data[index], riskField).toDouble(),
        ),
      ),
    );
  }
  
  double _getMaxCount() {
    if (trendData.isEmpty) return 10;
    return trendData.map((d) => 
      d.highRisk + d.mediumRisk + d.lowRisk
    ).reduce((a, b) => a > b ? a : b).toDouble();
  }
  
  // ✅ HELPER: Calculate Y-axis interval based on data range
  double _calculateYInterval() {
    final maxCount = _getMaxCount();
    if (maxCount <= 5) return 1;
    if (maxCount <= 10) return 2;
    if (maxCount <= 25) return 5;
    if (maxCount <= 50) return 10;
    if (maxCount <= 100) return 20;
    return 25;
  }

  // ✅ HELPER: Calculate X-axis interval based on data length
  double _calculateXInterval() {
    final dataLength = trendData.length;
    if (dataLength <= 7) return 1;
    if (dataLength <= 14) return 2;
    if (dataLength <= 30) return 5;
    return 7;
  }
  
  int _getRiskValue(RiskTrendData data, String riskField) {
    switch (riskField) {
      case 'highRisk':
        return data.highRisk;
      case 'mediumRisk':
        return data.mediumRisk;
      case 'lowRisk':
        return data.lowRisk;
      default:
        return 0;
    }
  }
  
  Widget _buildEmptyChart() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.show_chart,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No trend data available',
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
  
  Widget _buildTrendLegend() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem('High', const Color(0xFFDC2626)),
          const SizedBox(width: 16),
          _buildLegendItem('Medium', const Color(0xFFF97316)),
          const SizedBox(width: 16),
          _buildLegendItem('Low', const Color(0xFF059669)),
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
}
