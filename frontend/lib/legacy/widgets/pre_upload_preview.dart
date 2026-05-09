import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf_render/pdf_render.dart';
import '../services/smart_file_picker_service.dart';

class PreUploadPreview extends StatelessWidget {
  final FileValidationResult fileResult;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool isUploading;

  const PreUploadPreview({
    Key? key,
    required this.fileResult,
    required this.onCancel,
    required this.onConfirm,
    this.isUploading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            const Text(
              'Invoice Preview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // File icon/thumbnail
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: _buildPreview(),
            ),
            const SizedBox(height: 16),

            // File info
            Text(
              fileResult.fileName ?? 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Size: ${SmartFilePickerService.formatFileSize(fileResult.fileSize)}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Type: ${fileResult.fileExtension?.toUpperCase() ?? 'Unknown'}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Validation status
            if (fileResult.isValid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[600], size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Ready for upload',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Action buttons
            if (isUploading)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Uploading to server...',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: fileResult.isValid ? onConfirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Upload'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final extension = fileResult.fileExtension?.toLowerCase();
    
    if (SmartFilePickerService.isImage(extension)) {
      // Show image preview
      if (fileResult.fileBytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            fileResult.fileBytes!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackIcon();
            },
          ),
        );
      }
    } else if (SmartFilePickerService.isPdf(extension)) {
      // Show PDF icon with page indicator
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.picture_as_pdf,
            size: 64,
            color: Colors.red[400],
          ),
          const SizedBox(height: 8),
          Text(
            'PDF Document',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      );
    }
    
    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    return Icon(
      SmartFilePickerService.getFileIcon(fileResult.fileExtension),
      size: 64,
      color: Colors.grey[400],
    );
  }
}
