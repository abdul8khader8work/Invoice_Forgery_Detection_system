import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class FileValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? fileName;
  final Uint8List? fileBytes;
  final String? fileExtension;
  final int? fileSize;

  FileValidationResult({
    required this.isValid,
    this.errorMessage,
    this.fileName,
    this.fileBytes,
    this.fileExtension,
    this.fileSize,
  });
}

class SmartFilePickerService {
  // Allowed file extensions
  static const List<String> allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];
  
  // Maximum file size: 10MB
  static const int maxFileSizeBytes = 10 * 1024 * 1024;

  /// Pick and validate file
  static Future<FileValidationResult> pickAndValidateFile() async {
    try {
      // Pick file with restricted extensions
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: true, // Important: get file bytes for web
      );

      if (result == null || result.files.isEmpty) {
        return FileValidationResult(
          isValid: false,
          errorMessage: 'No file selected',
        );
      }

      final platformFile = result.files.first;
      
      // Get file extension
      final extension = platformFile.extension?.toLowerCase() ?? '';
      
      // Validate extension
      if (!allowedExtensions.contains(extension)) {
        return FileValidationResult(
          isValid: false,
          errorMessage: 'Invalid file format. Allowed: PDF, JPG, JPEG, PNG',
        );
      }

      // Get file size
      final fileSize = platformFile.bytes?.length ?? 0;
      
      // Validate file size (10MB limit)
      if (fileSize > maxFileSizeBytes) {
        return FileValidationResult(
          isValid: false,
          errorMessage: 'File too large. Maximum size: 10MB',
        );
      }

      // Validate file not empty
      if (fileSize == 0) {
        return FileValidationResult(
          isValid: false,
          errorMessage: 'File is empty',
        );
      }

      // Get file bytes
      final fileBytes = platformFile.bytes;
      if (fileBytes == null || fileBytes.isEmpty) {
        return FileValidationResult(
          isValid: false,
          errorMessage: 'Could not read file data',
        );
      }

      return FileValidationResult(
        isValid: true,
        fileName: platformFile.name,
        fileBytes: fileBytes,
        fileExtension: extension,
        fileSize: fileSize,
      );

    } catch (e) {
      return FileValidationResult(
        isValid: false,
        errorMessage: 'Error picking file: $e',
      );
    }
  }

  /// Get file type icon
  static IconData getFileIcon(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Format file size
  static String formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Check if file is image
  static bool isImage(String? extension) {
    return ['jpg', 'jpeg', 'png'].contains(extension?.toLowerCase());
  }

  /// Check if file is PDF
  static bool isPdf(String? extension) {
    return extension?.toLowerCase() == 'pdf';
  }
}
