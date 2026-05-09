import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../models/scan_result.dart';
import '../widgets/risk_indicator.dart';
import '../widgets/extraction_results.dart';
import '../widgets/validation_details.dart';
import '../widgets/ml_analysis.dart';
import '../utils/file_downloader.dart';
import 'invoice_chat_screen.dart';

class ScanResultScreen extends StatelessWidget {
  const ScanResultScreen({super.key});

  void _exportReport(BuildContext context, ScanResult result) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Export as PDF'),
              onTap: () {
                Navigator.pop(context);
                _downloadReport(context, result, 'PDF');
              },
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Colors.blue),
              title: const Text('Export as JSON'),
              onTap: () {
                Navigator.pop(context);
                _downloadReport(context, result, 'JSON');
              },
            ),
            if (result.fileBytes != null)
              ListTile(
                leading: const Icon(Icons.download, color: Colors.green),
                title: const Text('Download Original Invoice'),
                onTap: () {
                  Navigator.pop(context);
                  _downloadInvoice(context, result);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _downloadReport(BuildContext context, ScanResult result, String format) {
    try {
      if (format == 'JSON') {
        final reportData = {
          'file_id': result.fileId,
          'filename': result.filename,
          'extracted_data': result.extractedData,
          'deterministic_validation': result.deterministicValidation,
          'ml_analysis': result.mlAnalysis,
          'risk_score': result.riskScore,
          'risk_level': result.riskLevel,
          'reasoning': result.reasoning,
          'needs_verification': result.needsVerification,
          'verification_fields': result.verificationFields,
          'processing_time': result.processingTime,
          'timestamp': result.timestamp,
        };
        FileDownloader.downloadJson(reportData, '${result.filename}_report.json');
      } else if (format == 'PDF') {
        final pdfContent = '''
INVOICE ANALYSIS REPORT
=======================

File: ${result.filename}
Date: ${result.timestamp}
Risk Score: ${result.riskScore.toStringAsFixed(2)}%
Risk Level: ${result.riskLevel.toUpperCase()}

EXTRACTED DATA:
${result.extractedData.entries.map((e) => '${e.key}: ${e.value}').join('\n')}

VALIDATION RESULTS:
${result.deterministicValidation.entries.map((e) => '${e.key}: ${e.value}').join('\n')}

REASONING:
${result.reasoning.join('\n')}

ML ANALYSIS:
${result.mlAnalysis.entries.map((e) => '${e.key}: ${e.value}').join('\n')}
''';
        FileDownloader.downloadText(pdfContent, '${result.filename}_report.txt');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report downloaded as $format'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _downloadInvoice(BuildContext context, ScanResult result) {
    try {
      if (result.fileBytes != null) {
        final ext = result.filename.split('.').last.toLowerCase();
        String mimeType = 'application/octet-stream';
        if (['jpg', 'jpeg'].contains(ext)) mimeType = 'image/jpeg';
        else if (ext == 'png') mimeType = 'image/png';
        else if (ext == 'pdf') mimeType = 'application/pdf';

        FileDownloader.downloadBytes(result.fileBytes!, result.filename, mimeType);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Original invoice downloaded'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Original file not available for download'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ScanResult result = ModalRoute.of(context)!.settings.arguments as ScanResult;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => InvoiceChatScreen(
                    extractedData: result.extractedData,
                  ),
                ),
              );
            },
            tooltip: 'Chat with Invoice Data',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              _exportReport(context, result);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Original Invoice Preview
            if (result.fileBytes != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Original Invoice',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 300,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            result.fileBytes!,
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
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => _downloadInvoice(context, result),
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Download'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (result.fileBytes != null) const SizedBox(height: 16),

            // Risk Score Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'Risk Assessment',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    RiskIndicator(
                      riskScore: result.riskScore,
                      riskLevel: result.riskLevel,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Risk Score: ${result.riskScore.toStringAsFixed(1)}/100',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Verification Needed Alert
            if (result.needsVerification)
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
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/verification',
                          arguments: result,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Verify'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Side-by-Side Comparison
            const Text(
              'Side-by-Side Analysis',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

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
                      extractedData: result.extractedData,
                      confidenceScores: result.ocrConfidence,
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
                      validationResults: result.deterministicValidation,
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
                      mlResults: result.mlAnalysis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Reasoning Panel
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reasoning Panel',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (result.reasoning.isEmpty)
                      const Text('No issues detected')
                    else
                      ...result.reasoning.map((reason) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(reason),
                            ),
                          ],
                        ),
                      )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('New Scan'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _exportReport(context, result),
                    child: const Text('Export Report'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
