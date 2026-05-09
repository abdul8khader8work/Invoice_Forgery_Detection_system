import 'package:flutter/material.dart';
import 'dart:typed_data';

import '../services/smart_file_picker_service.dart';
import '../services/smart_ingestion_service.dart';
import '../widgets/pre_upload_preview.dart';

class SmartIngestionScreen extends StatefulWidget {
  const SmartIngestionScreen({Key? key}) : super(key: key);

  @override
  State<SmartIngestionScreen> createState() => _SmartIngestionScreenState();
}

class _SmartIngestionScreenState extends State<SmartIngestionScreen> {
  final SmartIngestionService _ingestionService = SmartIngestionService();
  
  bool _isPicking = false;
  bool _isUploading = false;
  FileValidationResult? _selectedFile;
  double _uploadProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Invoice Ingestion'),
        centerTitle: true,
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            const Icon(
              Icons.document_scanner,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            const Text(
              'Smart Document Upload',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload invoices for automatic cleanup and OCR preparation',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),

            // Upload Options
            Row(
              children: [
                Expanded(
                  child: _buildUploadCard(
                    icon: Icons.folder_open,
                    title: 'File',
                    description: 'PDF, JPG, PNG',
                    onTap: _isPicking ? null : _pickFile,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // File Requirements
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Requirements:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildRequirement('✓', 'Formats: PDF, JPG, JPEG, PNG'),
                  _buildRequirement('✓', 'Max size: 10MB'),
                  _buildRequirement('✓', 'Auto-crop and deskewing'),
                  _buildRequirement('✓', 'Noise removal included'),
                ],
              ),
            ),

            const Spacer(),

            // Status
            if (_isPicking)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Opening file picker...'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequirement(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Text(
            icon,
            style: TextStyle(
              color: Colors.green[600],
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _isPicking = true;
    });

    try {
      final result = await SmartFilePickerService.pickAndValidateFile();

      if (!result.isValid) {
        _showError(result.errorMessage ?? 'File validation failed');
        return;
      }

      setState(() {
        _selectedFile = result;
      });

      // Show preview dialog
      if (mounted) {
        _showPreviewDialog(result);
      }

    } catch (e) {
      _showError('Error picking file: $e');
    } finally {
      setState(() {
        _isPicking = false;
      });
    }
  }

  void _showPreviewDialog(FileValidationResult file) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PreUploadPreview(
        fileResult: file,
        onCancel: () {
          Navigator.of(context).pop();
          setState(() {
            _selectedFile = null;
          });
        },
        onConfirm: () {
          Navigator.of(context).pop();
          _uploadFile(file);
        },
        isUploading: false,
      ),
    );
  }

  Future<void> _uploadFile(FileValidationResult file) async {
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final result = await _ingestionService.ingestFile(
        file.fileBytes!,
        file.fileName!,
        (progress) {
          setState(() {
            _uploadProgress = progress;
          });
        },
      );

      if (result.success) {
        _showSuccess(
          'Ingestion Complete',
          result.message ?? 'Document processed successfully',
        );
        
        // Navigate to next screen with processed file info
        // TODO: Navigate to OCR processing or results screen
        
      } else {
        _showError(result.errorMessage ?? 'Ingestion failed');
      }

    } catch (e) {
      _showError('Upload error: $e');
    } finally {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
      });
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSuccess(String title, String message) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[600]),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
