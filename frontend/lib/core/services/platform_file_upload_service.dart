import 'dart:io' as io show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'platform_file_upload_service_io_simple.dart' if (dart.library.io) 'platform_file_upload_service_io_simple.dart';
import 'platform_file_upload_service_web.dart' if (dart.library.html) 'platform_file_upload_service_web.dart';
import '../config/app_config.dart';

// Upload result class
class UploadResult {
  final bool success;
  final String? fileId;
  final String? error;

  UploadResult({required this.success, this.fileId, this.error});
}

// Unified interface for platform file upload
class PlatformFileUploadService {
  static Future<dynamic> toMultipartFile(dynamic file, String fieldName) async {
    if (kIsWeb) {
      return await PlatformFileUploadServiceWeb.toMultipartFile(file, fieldName);
    } else {
      return PlatformFileUploadServiceIOSimple.toMultipartFile(file, fieldName);
    }
  }

  /// Upload file and return result
  Future<UploadResult> uploadFile(Uint8List bytes, String fileName) async {
    try {
      final dio = Dio();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
      });

      final response = await dio.post(
        '${AppConfig.apiBaseUrl}/scan',
        data: formData,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return UploadResult(
          success: true,
          fileId: response.data['file_id'] ?? response.data['invoice_id'],
        );
      } else {
        return UploadResult(
          success: false,
          error: 'Upload failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      return UploadResult(
        success: false,
        error: 'Upload error: $e',
      );
    }
  }
}
