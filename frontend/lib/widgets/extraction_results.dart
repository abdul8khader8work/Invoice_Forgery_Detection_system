import 'package:flutter/material.dart';

class ExtractionResults extends StatelessWidget {
  final Map<String, dynamic> extractedData;
  final Map<String, double> confidenceScores;

  const ExtractionResults({
    super.key,
    required this.extractedData,
    required this.confidenceScores,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildField('Vendor Name', extractedData['vendor_name']),
        _buildField('Invoice Number', extractedData['invoice_number']),
        _buildField('Invoice Date', extractedData['invoice_date']),
        _buildField('Subtotal', extractedData['subtotal']),
        _buildField('Tax', extractedData['tax']),
        _buildField('Total', extractedData['total']),
      ],
    );
  }

  Widget _buildField(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? 'Not detected',
              style: TextStyle(
                color: value != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
