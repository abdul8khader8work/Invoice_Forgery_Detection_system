import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/scan_result.dart';
import '../services/active_learning_service.dart';
import '../config.dart';

/// Enhanced Verification Screen with Active Learning Support
/// 
/// This screen allows users to:
/// 1. View extracted fields with confidence scores
/// 2. Manually correct field values
/// 3. Submit corrections back to the backend
/// 4. Teach the system to learn from corrections
///
/// CRITICAL: When user corrects a field, we capture the new bounding box
/// and send it to /templates/refine endpoint for spatial learning.

class ActiveLearningVerificationScreen extends StatefulWidget {
  final ScanResult result;
  final Uint8List? fileBytes;
  final String fileId;
  final int logId;
  final String styleTag;

  const ActiveLearningVerificationScreen({
    Key? key,
    required this.result,
    this.fileBytes,
    required this.fileId,
    required this.logId,
    required this.styleTag,
  }) : super(key: key);

  @override
  State<ActiveLearningVerificationScreen> createState() => 
      _ActiveLearningVerificationScreenState();
}

class _ActiveLearningVerificationScreenState 
    extends State<ActiveLearningVerificationScreen> {
  
  // Controllers for editable fields
  final Map<String, TextEditingController> _controllers = {};
  
  // Track which fields were modified
  final Set<String> _modifiedFields = {};
  
  // Track original values for comparison
  final Map<String, String> _originalValues = {};
  
  // Bounding box data for corrections
  // Key: field_name, Value: {original_bbox, corrected_bbox, anchor_bbox}
  final Map<String, Map<String, dynamic>> _correctionBboxes = {};
  
  bool _isSubmitting = false;
  bool _isLoading = true;
  
  // Raw OCR boxes from backend (for visualization)
  List<Map<String, dynamic>> _ocrBoxes = [];
  
  @override
  void initState() {
    super.initState();
    _initializeFields();
    _loadExtractionLog();
  }

  void _initializeFields() {
    // Initialize controllers with extracted data
    final extractedData = widget.result.extractedData;
    
    // Standard invoice fields
    final fields = [
      'vendor_name',
      'invoice_number', 
      'invoice_date',
      'due_date',
      'subtotal',
      'tax',
      'total',
    ];
    
    for (final field in fields) {
      final value = extractedData[field]?.toString() ?? '';
      _controllers[field] = TextEditingController(text: value);
      _originalValues[field] = value;
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _loadExtractionLog() async {
    try {
      final log = await ActiveLearningService.getExtractionLog(widget.fileId);
      
      setState(() {
        _ocrBoxes = (log['raw_ocr_output']?['boxes'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ?? [];
      });
    } catch (e) {
      debugPrint('Failed to load extraction log: $e');
    }
  }

  void _onFieldChanged(String fieldName, String newValue) {
    final originalValue = _originalValues[fieldName] ?? '';
    
    if (newValue != originalValue) {
      setState(() {
        _modifiedFields.add(fieldName);
      });
      
      // Capture correction bounding box data
      // In a full implementation, user would drag to select correct region
      // For now, we flag it as manually corrected
      _correctionBboxes[fieldName] = {
        'original_value': originalValue,
        'corrected_value': newValue,
        'corrected_at': DateTime.now().toIso8601String(),
      };
    } else {
      setState(() {
        _modifiedFields.remove(fieldName);
      });
      _correctionBboxes.remove(fieldName);
    }
  }

  Future<void> _submitCorrections() async {
    if (_modifiedFields.isEmpty) {
      // No corrections to submit
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Build correction list
      final corrections = <Map<String, dynamic>>[];
      
      for (final fieldName in _modifiedFields) {
        final controller = _controllers[fieldName];
        if (controller == null) continue;
        
        final correctedValue = controller.text;
        final originalValue = _originalValues[fieldName] ?? '';
        
        // Find original bounding box from OCR data
        final originalBbox = _findBboxForValue(originalValue);
        
        // For corrected bbox, we'd ideally have user-drawn selection
        // For now, use the same bbox (system learns from value correction)
        final correctedBbox = originalBbox;
        
        // Find anchor bbox (the label that identifies this field)
        final anchorBbox = _findAnchorBbox(fieldName);
        
        corrections.add({
          'field_name': fieldName,
          'original_value': originalValue,
          'corrected_value': correctedValue,
          'original_bbox': originalBbox ?? _defaultBbox(),
          'corrected_bbox': correctedBbox ?? _defaultBbox(),
          'anchor_bbox': anchorBbox ?? _defaultBbox(),
        });
      }

      // Submit to backend
      final response = await ActiveLearningService.refineTemplate(
        fileId: widget.fileId,
        logId: widget.logId,
        styleTag: widget.styleTag,
        corrections: corrections,
        correctedBy: 'user',
      );

      if (mounted) {
        _showSuccessDialog(response);
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Failed to submit corrections', e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Map<String, dynamic>? _findBboxForValue(String value) {
    if (value.isEmpty || _ocrBoxes.isEmpty) return null;
    
    // Find OCR box containing this value
    for (final box in _ocrBoxes) {
      final text = box['text']?.toString() ?? '';
      if (text.contains(value) || value.contains(text)) {
        return {
          'x': box['x'] ?? 0.0,
          'y': box['y'] ?? 0.0,
          'width': box['width'] ?? box['w'] ?? 100.0,
          'height': box['height'] ?? box['h'] ?? 20.0,
        };
      }
    }
    return null;
  }

  Map<String, dynamic>? _findAnchorBbox(String fieldName) {
    // Map field names to their anchor label patterns
    final anchorPatterns = {
      'vendor_name': ['From', 'Vendor', 'Billed By', 'Seller'],
      'invoice_number': ['Invoice #', 'Invoice Number', 'Invoice No', 'Ref'],
      'invoice_date': ['Date', 'Invoice Date', 'Issued'],
      'due_date': ['Due Date', 'Payment Due'],
      'subtotal': ['Subtotal', 'Net Amount'],
      'tax': ['Tax', 'VAT', 'GST'],
      'total': ['Total', 'Grand Total', 'Amount Due', 'Balance'],
    };
    
    final patterns = anchorPatterns[fieldName] ?? [fieldName];
    
    // Find OCR box matching anchor pattern
    for (final box in _ocrBoxes) {
      final text = box['text']?.toString().toLowerCase() ?? '';
      for (final pattern in patterns) {
        if (text.contains(pattern.toLowerCase())) {
          return {
            'x': box['x'] ?? 0.0,
            'y': box['y'] ?? 0.0,
            'width': box['width'] ?? box['w'] ?? 100.0,
            'height': box['height'] ?? box['h'] ?? 20.0,
          };
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _defaultBbox() {
    return {'x': 0.0, 'y': 0.0, 'width': 100.0, 'height': 20.0};
  }

  void _showSuccessDialog(Map<String, dynamic> response) {
    final fieldsUpdated = response['fields_updated'] as List<dynamic>? ?? [];
    final newConfidence = response['new_confidence_score'] as double? ?? 0.0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.psychology, color: Colors.blue),
            SizedBox(width: 8),
            Text('Learning Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your corrections have been saved and the system has learned from them.',
            ),
            SizedBox(height: 16),
            Text(
              'Fields Updated:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...fieldsUpdated.map((f) => Text('• $f')),
            SizedBox(height: 16),
            Text(
              'Template Confidence: ${(newConfidence * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: newConfidence > 0.7 ? Colors.green : Colors.orange,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Future invoices from this vendor will be extracted more accurately.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Return to results
              Navigator.of(context).pop(); // Return to home
            },
            child: Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Verify & Improve Extraction'),
        subtitle: Text(
          'Your corrections teach the system',
          style: TextStyle(fontSize: 12),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Learning Banner
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.purple.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_fix_high, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Learning Mode',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Correct any fields below. The system learns from your corrections '
                          'to improve extraction for similar invoices.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            // Modified Fields Indicator
            if (_modifiedFields.isNotEmpty)
              Container(
                margin: EdgeInsets.only(bottom: 16),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '${_modifiedFields.length} field(s) modified',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Verification Fields
            Text(
              'Verify Extracted Fields',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            
            _buildFieldCard('vendor_name', 'Vendor Name', Icons.business),
            _buildFieldCard('invoice_number', 'Invoice Number', Icons.receipt),
            _buildFieldCard('invoice_date', 'Invoice Date', Icons.calendar_today),
            _buildFieldCard('due_date', 'Due Date', Icons.event),
            _buildFieldCard('subtotal', 'Subtotal', Icons.attach_money),
            _buildFieldCard('tax', 'Tax/VAT', Icons.account_balance),
            _buildFieldCard('total', 'Grand Total', Icons.account_balance_wallet),
            
            SizedBox(height: 32),
            
            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitCorrections,
                icon: _isSubmitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(Icons.psychology),
                label: Text(
                  _isSubmitting
                      ? 'Teaching System...'
                      : _modifiedFields.isEmpty
                          ? 'No Corrections Needed'
                          : 'Submit Corrections & Learn',
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _modifiedFields.isEmpty ? Colors.grey : Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Skip Button
            if (_modifiedFields.isNotEmpty)
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Skip Corrections'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard(String fieldName, String label, IconData icon) {
    final controller = _controllers[fieldName];
    if (controller == null) return SizedBox.shrink();
    
    final isModified = _modifiedFields.contains(fieldName);
    final confidence = widget.result.confidenceScores[fieldName] ?? 0.0;
    
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: isModified ? 4 : 1,
      color: isModified ? Colors.blue.shade50 : null,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey[800],
                  ),
                ),
                Spacer(),
                // Confidence Badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getConfidenceColor(confidence).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getConfidenceColor(confidence).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    '${(confidence * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getConfidenceColor(confidence),
                    ),
                  ),
                ),
                // Modified Indicator
                if (isModified)
                  Container(
                    margin: EdgeInsets.only(left: 8),
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'MODIFIED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 12),
            TextField(
              controller: controller,
              onChanged: (value) => _onFieldChanged(fieldName, value),
              decoration: InputDecoration(
                hintText: 'Enter $label',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isModified ? Colors.blue : Colors.grey.shade300,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isModified ? Colors.blue : Colors.blue,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isModified ? Colors.white : Colors.grey.shade50,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              keyboardType: fieldName.contains('total') || 
                            fieldName.contains('subtotal') || 
                            fieldName.contains('tax')
                  ? TextInputType.numberWithOptions(decimal: true)
                  : fieldName.contains('date')
                      ? TextInputType.datetime
                      : TextInputType.text,
            ),
            if (isModified)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'This correction will be used to improve future extractions',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
