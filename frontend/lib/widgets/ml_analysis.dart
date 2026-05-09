import 'package:flutter/material.dart';

class MLAnalysis extends StatelessWidget {
  final Map<String, dynamic> mlResults;

  const MLAnalysis({
    super.key,
    required this.mlResults,
  });

  @override
  Widget build(BuildContext context) {
    final isAnomaly = mlResults['is_anomaly'] as bool? ?? false;
    final anomalyScore = mlResults['anomaly_score'] as double? ?? 0.0;
    final anomalyReason = mlResults['anomaly_reason'] as String? ?? 'No analysis available';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isAnomaly ? Icons.warning : Icons.check_circle,
              color: isAnomaly ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(
              isAnomaly ? 'Anomaly Detected' : 'Normal Pattern',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isAnomaly ? Colors.red : Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Anomaly Score: ${(anomalyScore * 100).toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          'Analysis: $anomalyReason',
          style: TextStyle(
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
