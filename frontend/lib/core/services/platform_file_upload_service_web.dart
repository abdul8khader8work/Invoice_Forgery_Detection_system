import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

class PlatformFileUploadServiceWeb {
  static Future<MultipartFile> toMultipartFile(dynamic file, String fieldName) async {
    // Handle different file types from web file picker
    if (file is PlatformFile) {
      if (file.bytes != null) {
        // Detect content type from actual file bytes, not just extension
        final contentType = _detectContentTypeFromBytes(file.bytes!);
        final extension = _getExtensionFromContentType(contentType);
        final filename = _ensureCorrectExtension(file.name, extension);
        
        return MultipartFile.fromBytes(
          file.bytes!,
          filename: filename,
          contentType: DioMediaType.parse(contentType),
        );
      }
      throw Exception('File bytes are null');
    } else if (file is Uint8List) {
      // Handle raw bytes passed from file picker
      final contentType = _detectContentTypeFromBytes(file);
      final extension = _getExtensionFromContentType(contentType);
      final filename = 'upload.$extension';
      
      return MultipartFile.fromBytes(
        file,
        filename: filename,
        contentType: DioMediaType.parse(contentType),
      );
    } else if (file is String) {
      // Handle file path (shouldn't happen on web, but just in case)
      throw Exception('File paths not supported on web platform');
    }
    
    // Debug: log what we received
    print('Unsupported file type for web upload: ${file.runtimeType}');
    throw Exception('Unsupported file type for web upload: ${file.runtimeType}');
  }
  
  /// Detect content type from file bytes using magic numbers
  static String _detectContentTypeFromBytes(Uint8List bytes) {
    if (bytes.length < 4) return 'application/octet-stream';
    
    // Check for PDF signature: %PDF (25 50 44 46)
    if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
      return 'application/pdf';
    }
    
    // Check for JPEG signature: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    
    // Check for PNG signature: 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
        bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) {
      return 'image/png';
    }
    
    // Default to octet-stream if unknown
    return 'application/octet-stream';
  }
  
  /// Get file extension from content type
  static String _getExtensionFromContentType(String contentType) {
    switch (contentType) {
      case 'application/pdf':
        return 'pdf';
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      default:
        return 'bin';
    }
  }
  
  /// Ensure filename has correct extension based on detected content type
  static String _ensureCorrectExtension(String filename, String correctExtension) {
    final parts = filename.split('.');
    if (parts.length > 1) {
      parts[parts.length - 1] = correctExtension;
      return parts.join('.');
    }
    return '$filename.$correctExtension';
  }
  
  static String _getContentType(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }
}
