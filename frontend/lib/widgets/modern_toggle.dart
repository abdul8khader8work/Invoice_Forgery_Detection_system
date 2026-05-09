import 'package:flutter/material.dart';

class ModernToggle extends StatelessWidget {
  final String label;
  final String description;
  final bool checked;
  final Function(bool) onChanged;
  
  const ModernToggle({
    required this.label,
    required this.description,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 16),
        Switch(
          value: checked,
          onChanged: onChanged,
          activeColor: Colors.red[600],
          activeTrackColor: Colors.red[200],
          inactiveThumbColor: Colors.grey[400],
          inactiveTrackColor: Colors.grey[700],
        ),
      ],
    );
  }
}
