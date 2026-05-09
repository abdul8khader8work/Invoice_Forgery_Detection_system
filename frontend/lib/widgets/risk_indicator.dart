import 'package:flutter/material.dart';

class RiskIndicator extends StatelessWidget {
  final double riskScore;
  final String riskLevel;

  const RiskIndicator({
    super.key,
    required this.riskScore,
    required this.riskLevel,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getRiskColor(riskLevel);
    final icon = _getRiskIcon(riskLevel);
    final description = _getRiskDescription(riskLevel);

    return Column(
      children: [
        // Circular Progress Indicator
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background circle
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: riskScore / 100,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  strokeWidth: 12,
                ),
              ),
              // Center content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 32,
                    color: color,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${riskScore.toInt()}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Risk Level Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            riskLevel.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Risk Description
        Text(
          description,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Color _getRiskColor(String level) {
    switch (level.toLowerCase()) {
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

  IconData _getRiskIcon(String level) {
    switch (level.toLowerCase()) {
      case 'high':
        return Icons.dangerous;
      case 'medium':
        return Icons.warning;
      case 'low':
        return Icons.check_circle;
      default:
        return Icons.help;
    }
  }

  String _getRiskDescription(String level) {
    switch (level.toLowerCase()) {
      case 'high':
        return 'High risk detected. Immediate review required.';
      case 'medium':
        return 'Medium risk detected. Review recommended.';
      case 'low':
        return 'Low risk. Invoice appears legitimate.';
      default:
        return 'Risk assessment unavailable.';
    }
  }
}
