import 'package:flutter/material.dart';

class ValidationDetails extends StatelessWidget {
  final Map<String, dynamic> validationResults;

  const ValidationDetails({
    super.key,
    required this.validationResults,
  });

  @override
  Widget build(BuildContext context) {
    final checks = validationResults['checks'] as Map<String, dynamic>? ?? {};
    
    return Column(
      children: checks.entries.map((entry) {
        final checkName = entry.key;
        final result = entry.value as Map<String, dynamic>? ?? {};
        final passed = result['passed'] as bool? ?? false;
        final reason = result['reason'] as String? ?? 'No reason provided';
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              passed ? Icons.check_circle : Icons.error,
              color: passed ? Colors.green : Colors.red,
            ),
            title: Text(
              _formatCheckName(checkName),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(reason),
          ),
        );
      }).toList(),
    );
  }

  String _formatCheckName(String checkName) {
    return checkName
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}
