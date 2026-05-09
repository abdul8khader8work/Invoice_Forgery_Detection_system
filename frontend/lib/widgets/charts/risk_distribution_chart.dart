import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class RiskDistributionChart extends StatelessWidget {
  final Map<String, int> distribution;
  final double? radius;

  const RiskDistributionChart({
    super.key,
    required this.distribution,
    this.radius = 80,
  });

  @override
  Widget build(BuildContext context) {
    final total = distribution.values.fold(0, (sum, count) => sum + count);
    if (total == 0) {
      return const Center(
        child: Text(
          'No data available',
          style: TextStyle(color: AppColors.gray500),
        ),
      );
    }

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 60,
        sections: [
          if (distribution['low'] != null && distribution['low']! > 0)
            PieChartSectionData(
              value: distribution['low']!.toDouble(),
              color: AppColors.riskLow,
              title: '${((distribution['low']! / total) * 100).toStringAsFixed(1)}%',
              radius: radius,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          if (distribution['medium'] != null && distribution['medium']! > 0)
            PieChartSectionData(
              value: distribution['medium']!.toDouble(),
              color: AppColors.riskMedium,
              title: '${((distribution['medium']! / total) * 100).toStringAsFixed(1)}%',
              radius: radius,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          if (distribution['high'] != null && distribution['high']! > 0)
            PieChartSectionData(
              value: distribution['high']!.toDouble(),
              color: AppColors.riskHigh,
              title: '${((distribution['high']! / total) * 100).toStringAsFixed(1)}%',
              radius: radius,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          if (distribution['critical'] != null && distribution['critical']! > 0)
            PieChartSectionData(
              value: distribution['critical']!.toDouble(),
              color: AppColors.riskCritical,
              title: '${((distribution['critical']! / total) * 100).toStringAsFixed(1)}%',
              radius: radius,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
