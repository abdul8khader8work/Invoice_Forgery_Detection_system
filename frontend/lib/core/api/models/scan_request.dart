import 'package:dio/dio.dart';

/// Scan request model for single invoice
class ScanRequest {
  final dynamic file; // Can be String (path) or MultipartFile

  ScanRequest({required this.file});

  Map<String, dynamic> toJson() {
    return {
      'file': file,
    };
  }
}
