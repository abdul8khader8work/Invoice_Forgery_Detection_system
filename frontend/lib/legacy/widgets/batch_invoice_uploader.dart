import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import '../widgets/risk_indicator.dart';
import '../widgets/extraction_results.dart';
import '../widgets/validation_details.dart';
import '../widgets/ml_analysis.dart';

enum UploadStatus { pending, processing, completed, failed, manualReview }

class InvoiceUploadItem {
  final String id;
  final List<int>? fileBytes;  // For web platform
  final String? filePath;      // For desktop/mobile (null on web)
  final String filename;
  final int fileSize;
  UploadStatus status;
  double progress;
  String? errorMessage;
  Map<String, dynamic>? result;
  double? processingTime;
  double? memoryUsage;

  InvoiceUploadItem({
    required this.id,
    this.fileBytes,
    this.filePath,
    required this.filename,
    required this.fileSize,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
  });

  void updateStatus(UploadStatus newStatus, {String? error, Map<String, dynamic>? result}) {
    status = newStatus;
    errorMessage = error;
    this.result = result;
  }
}

class BatchInvoiceUploader extends StatefulWidget {
  const BatchInvoiceUploader({Key? key}) : super(key: key);

  @override
  _BatchInvoiceUploaderState createState() => _BatchInvoiceUploaderState();
}

class _BatchInvoiceUploaderState extends State<BatchInvoiceUploader> {
  final List<InvoiceUploadItem> _uploadQueue = [];
  bool _isDragOver = false;
  bool _isUploading = false;
  int _completedCount = 0;
  int _failedCount = 0;

  // API configuration
  static const String _baseUrl = 'http://127.0.0.1:8000'; // Main backend with accurate OCR
  static const String _batchEndpoint = '$_baseUrl/scan-batch';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Invoice OCR'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Drag & Drop Zone
          Container(
            height: 200,
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(
                color: _isDragOver ? Colors.blue : Colors.grey,
                width: _isDragOver ? 3 : 2,
              ),
              borderRadius: BorderRadius.circular(10),
              color: _isDragOver ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
            ),
            child: InkWell(
              onTap: _pickFiles,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isDragOver ? Icons.cloud_upload : Icons.add_photo_alternate,
                    size: 50,
                    color: _isDragOver ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isDragOver
                        ? 'Drop invoices here'
                        : 'Click to select or drag & drop invoices\n(Max 5 files)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isDragOver ? Colors.blue : Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Supported: JPG, PNG, PDF (max 10MB each)',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // Upload Queue
          Expanded(
            child: _uploadQueue.isEmpty
                ? const Center(
                    child: Text(
                      'No files selected',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: _uploadQueue.length,
                    itemBuilder: (context, index) {
                      return _buildUploadItem(_uploadQueue[index]);
                    },
                  ),
          ),

          // Control Buttons
          if (_uploadQueue.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _startBatchProcessing,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: Text(
                        _isUploading
                            ? 'Processing... ($_completedCount/${_uploadQueue.length})'
                            : 'Process ${_uploadQueue.length} Invoice${_uploadQueue.length > 1 ? 's' : ''}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: _clearQueue,
                    child: const Text('Clear All'),
                  ),
                ],
              ),
            ),

          // Status Summary
          if (_completedCount > 0 || _failedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: Colors.grey[100],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text('Completed: $_completedCount', style: const TextStyle(color: Colors.green)),
                  Text('Failed: $_failedCount', style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUploadItem(InvoiceUploadItem item) {
    Color statusColor;
    IconData statusIcon;

    switch (item.status) {
      case UploadStatus.pending:
        statusColor = Colors.grey;
        statusIcon = Icons.pending;
        break;
      case UploadStatus.processing:
        statusColor = Colors.blue;
        statusIcon = Icons.hourglass_empty;
        break;
      case UploadStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case UploadStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case UploadStatus.manualReview:
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(item.filename),
        subtitle: Text(_formatFileSize(item.fileSize)),
        trailing: item.status == UploadStatus.processing
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              )
            : item.result != null
                ? const Icon(Icons.chevron_right)
                : null,
        onTap: item.result != null ? () => _showDetailedResult(item) : null,
      ),
    );
  }

  Widget _buildResultField(String label, dynamic value) {
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

  void _showDetailedResult(InvoiceUploadItem item) {
    if (item.result == null) return;

    final result = item.result!;
    final extractedData = result['extracted_data'] as Map<String, dynamic>? ?? {};
    final deterministicValidation = result['deterministic_validation'] as Map<String, dynamic>? ?? {};
    final mlAnalysis = result['ml_analysis'] as Map<String, dynamic>? ?? {};
    final riskScore = (result['risk_score'] as num?)?.toDouble() ?? 0.0;
    final riskLevel = result['risk_level'] as String? ?? 'low';
    final needsVerification = result['needs_verification'] as bool? ?? false;
    final reasoning = result['reasoning'] as List<dynamic>? ?? [];
    final xaiReport = result['xai_report'] as Map<String, dynamic>? ?? {};

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 800),
          child: Scaffold(
            appBar: AppBar(
              title: Text(item.filename),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Risk Assessment Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text(
                            'Risk Assessment',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          RiskIndicator(
                            riskScore: riskScore,
                            riskLevel: riskLevel,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Risk Score: ${riskScore.toStringAsFixed(1)}/100',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'Risk Level: ${riskLevel.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 14,
                              color: riskLevel == 'high' ? Colors.red : 
                                     riskLevel == 'medium' ? Colors.orange : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Verification Needed Alert
                  if (needsVerification)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange.shade600),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Human Verification Required',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Low confidence or high risk detected',
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (needsVerification) const SizedBox(height: 16),

                  // Extracted Data
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Extracted Data',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ExtractionResults(
                            extractedData: extractedData,
                            confidenceScores: extractedData['confidence_scores'] as Map<String, double>? ?? {},
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Validation Results
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Validation Results',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ValidationDetails(
                            validationResults: deterministicValidation,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ML Analysis
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ML Analysis',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          MLAnalysis(
                            mlResults: mlAnalysis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // XAI Report
                  if (xaiReport.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'XAI Report',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (xaiReport['executive_summary'] != null)
                              Text(
                                xaiReport['executive_summary'],
                                style: const TextStyle(fontSize: 14),
                              ),
                            if (xaiReport['audit_entry'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Final Verdict: ${xaiReport['audit_entry']['final_verdict']}'),
                                    Text('Confidence Score: ${xaiReport['audit_entry']['confidence_score']}%'),
                                    if (xaiReport['audit_entry']['top_risk_factors'] != null)
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 8),
                                          const Text('Top Risk Factors:', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ...List<String>.from(xaiReport['audit_entry']['top_risk_factors'])
                                              .map((factor) => Padding(
                                                    padding: const EdgeInsets.only(left: 8, top: 4),
                                                    child: Text('• $factor', style: const TextStyle(fontSize: 13)),
                                                  )),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Reasoning
                  if (reasoning.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Reasoning',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...reasoning.map((reason) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                                      Expanded(child: Text(reason.toString())),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showResultDialog(InvoiceUploadItem item) {
    if (item.result == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Results for ${item.filename}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.result!['manual_review_required'] == true)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange.withOpacity(0.2),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Requires Manual Review'),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              ..._buildResultFields(item.result!['extracted_data']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResultFields(Map<String, dynamic> data) {
    final fields = [
      {'key': 'vendor_name', 'label': 'Vendor'},
      {'key': 'invoice_number', 'label': 'Invoice Number'},
      {'key': 'invoice_date', 'label': 'Date'},
      {'key': 'total_amount', 'label': 'Total Amount'},
      {'key': 'tax_amount', 'label': 'Tax Amount'},
    ];

    return fields.map((field) {
      final value = data[field['key']];
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                '${field['label']}:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Text(value?.toString() ?? 'Not found'),
            ),
          ],
        ),
      );
    }).toList();
  }

  void _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      allowMultiple: true,
      withData: true, // Required for web - provides bytes
    );

    if (result != null) {
      _addFilesToQueue(result.files);
    }
  }

  void _addFilesToQueue(List<PlatformFile> files) {
    for (final platformFile in files) {
      if (_uploadQueue.length >= MAX_BATCH_SIZE) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum 5 files allowed per batch')),
        );
        break;
      }

      // Web platform: path is null, use bytes only
      // Desktop: path is available, can use either
      final uploadItem = InvoiceUploadItem(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_${_uploadQueue.length}',
        fileBytes: platformFile.bytes,  // Always available
        filePath: null,  // Don't use path - web throws exception
        filename: platformFile.name,
        fileSize: platformFile.size,
      );

      print('Added file: ${platformFile.name}, size: ${platformFile.size}, bytes: ${platformFile.bytes?.length ?? 0}');

      setState(() {
        _uploadQueue.add(uploadItem);
      });
    }
  }

  void _startBatchProcessing() async {
    setState(() {
      _isUploading = true;
      _completedCount = 0;
      _failedCount = 0;
    });

    if (_uploadQueue.isEmpty) return;

    try {
      print('Starting batch upload of ${_uploadQueue.length} files...');
      
      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_batchEndpoint));

      // Add all files using bytes (works on both web and desktop)
      for (final item in _uploadQueue) {
        if (item.fileBytes == null) {
          print('Warning: ${item.filename} has no bytes, skipping...');
          continue;
        }
        
        final mimeType = lookupMimeType(item.filename) ?? 'image/jpeg';
        final mimeParts = mimeType.split('/');

        print('Adding ${item.filename} (${item.fileBytes!.length} bytes)');
        
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            item.fileBytes!,
            filename: item.filename,
            contentType: MediaType(mimeParts[0], mimeParts[1]),
          ),
        );
      }

      print('Sending request to $_batchEndpoint...');
      
      // Send request
      final streamedResponse = await request.send().timeout(const Duration(seconds: 300));
      print('Response received, status: ${streamedResponse.statusCode}');
      
      final response = await http.Response.fromStream(streamedResponse);
      print('Response body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        _handleBatchResponse(jsonResponse);
      } else {
        _handleBatchError('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _handleBatchError('Network error: $e');
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  void _handleBatchResponse(Map<String, dynamic> response) {
    print('Handling batch response: $response');
    
    if (response['success'] != true) {
      _handleBatchError(response['message'] ?? 'Processing failed');
      return;
    }

    final results = response['results'] as List<dynamic>;
    final errors = response['errors'] as List<dynamic>? ?? [];
    
    print('Results count: ${results.length}');
    print('Errors count: ${errors.length}');

    setState(() {
      // Process successful results
      for (int i = 0; i < results.length; i++) {
        final invoiceData = results[i] as Map<String, dynamic>;
        print('Processing result $i: ${invoiceData['filename']}');
        
        if (i < _uploadQueue.length) {
          final item = _uploadQueue[i];
          
          final needsVerification = invoiceData['needs_verification'] ?? false;
          print('Needs verification: $needsVerification');
          
          item.updateStatus(
            needsVerification ? UploadStatus.manualReview : UploadStatus.completed,
            result: invoiceData,
          );

          item.processingTime = invoiceData['processing_time'];
          
          // All successful results (even those needing review) count as completed
          _completedCount++;
        } else {
          print('Error: Index $i out of bounds for upload queue (length: ${_uploadQueue.length})');
        }
      }
      
      // Process errors from backend
      for (final error in errors) {
        final errorMap = error as Map<String, dynamic>;
        final filename = errorMap['filename'] as String?;
        final errorMessage = errorMap['error'] as String?;
        
        print('Processing error for: $filename - $errorMessage');
        
        // Find the item in the queue that matches the filename
        final matchingItem = _uploadQueue.firstWhere(
          (item) => item.filename == filename,
          orElse: () => _uploadQueue[results.length], // Fallback to next in line
        );
        
        matchingItem.updateStatus(UploadStatus.failed, error: errorMessage);
        _failedCount++;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Batch processing completed: $_completedCount successful, $_failedCount need review'),
        backgroundColor: _failedCount > 0 ? Colors.orange : Colors.green,
      ),
    );
  }

  void _handleBatchError(String error) {
    setState(() {
      for (final item in _uploadQueue) {
        if (item.status != UploadStatus.completed) {
          item.updateStatus(UploadStatus.failed, error: error);
          _failedCount++;
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Batch processing failed: $error')),
    );
  }

  void _clearQueue() {
    setState(() {
      _uploadQueue.clear();
      _completedCount = 0;
      _failedCount = 0;
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static const int MAX_BATCH_SIZE = 5;
}
