import 'package:flutter/material.dart';
import 'dart:typed_data';

import '../models/scan_result.dart';
import '../services/api_service.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final ApiService _apiService = ApiService();
  final Map<String, TextEditingController> _controllers = {};
  bool _isSubmitting = false;
  bool _didInit = false;
  ScanResult? _result;

  @override
  void initState() {
    super.initState();
    // Don't access ModalRoute here - move to didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _result = ModalRoute.of(context)!.settings.arguments as ScanResult;
      
      // Initialize controllers for verification fields
      for (final field in _result!.verificationFields) {
        _controllers[field] = TextEditingController();
        
        // Pre-fill with extracted data if available
        final extractedValue = _getExtractedValue(_result!.extractedData, field);
        if (extractedValue != null) {
          _controllers[field]!.text = extractedValue.toString();
        }
      }
      _didInit = true;
    }
  }

  dynamic _getExtractedValue(Map<String, dynamic> extractedData, String field) {
    final fieldMapping = {
      'vendor_name': 'vendorName',
      'invoice_number': 'invoiceNumber',
      'invoice_date': 'invoiceDate',
      'subtotal': 'subtotal',
      'tax': 'tax',
      'total': 'total',
    };
    
    final mappedField = fieldMapping[field] ?? field;
    return extractedData[mappedField];
  }

  Future<void> _submitVerification() async {
    if (_result == null) return;
    
    setState(() {
      _isSubmitting = true;
    });

    try {
      // Prepare verified data
      final verifiedData = <String, dynamic>{};
      for (final field in _result!.verificationFields) {
        final controller = _controllers[field];
        if (controller != null && controller.text.isNotEmpty) {
          // Convert to appropriate type
          final value = _convertValue(field, controller.text);
          verifiedData[field] = value;
        }
      }

      // Submit verification
      final response = await _apiService.verifyInvoice(
        _result!.fileId,
        verifiedData,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Verification Complete'),
            content: const Text('Invoice has been verified and updated.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back to results
                  Navigator.of(context).pop(); // Go back to home
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Verification Error'),
            content: Text('Failed to submit verification: ${e.toString()}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  dynamic _convertValue(String field, String value) {
    // Convert string values to appropriate types
    switch (field) {
      case 'subtotal':
      case 'tax':
      case 'total':
        return double.tryParse(value.replaceAll(RegExp(r'[,$]'), ''));
      case 'invoice_date':
        return value; // Keep as string, backend will parse
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Human Verification'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Uploaded Invoice Image Preview
            if (_result?.fileBytes != null)
              Container(
                height: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _result!.fileBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image, size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text('Unable to display image', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (_result?.fileBytes != null) const SizedBox(height: 24),

            // Verification Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade600),
                      const SizedBox(width: 8),
                      const Text(
                        'Verification Required',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please verify the following fields that require human attention due to low OCR confidence or high risk detection.',
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Verification Fields
            const Text(
              'Fields Requiring Verification',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            ..._result!.verificationFields.map((field) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildVerificationField(field, _result!),
            )),

            const SizedBox(height: 24),

            // Submit Button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitVerification,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Submit Verification'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationField(String field, ScanResult result) {
    final controller = _controllers[field]!;
    final extractedValue = _getExtractedValue(result.extractedData, field);
    final confidence = result.ocrConfidence[field] ?? 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _getFieldDisplayName(field),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getConfidenceColor(confidence),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${(confidence * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Extracted value (for reference)
            if (extractedValue != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Extracted: ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        extractedValue.toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // Verification input
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Verified ${_getFieldDisplayName(field)}',
                hintText: 'Enter correct value',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              keyboardType: _getKeyboardType(field),
            ),
          ],
        ),
      ),
    );
  }

  String _getFieldDisplayName(String field) {
    final displayNames = {
      'vendor_name': 'Vendor Name',
      'invoice_number': 'Invoice Number',
      'invoice_date': 'Invoice Date',
      'subtotal': 'Subtotal',
      'tax': 'Tax',
      'total': 'Total',
    };
    return displayNames[field] ?? field;
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }

  TextInputType _getKeyboardType(String field) {
    switch (field) {
      case 'subtotal':
      case 'tax':
      case 'total':
        return const TextInputType.numberWithOptions(decimal: true);
      case 'invoice_date':
        return TextInputType.datetime;
      default:
        return TextInputType.text;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
