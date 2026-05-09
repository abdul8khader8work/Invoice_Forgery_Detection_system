import 'dart:io';
import 'package:dio/dio.dart';

class PlatformFileUploadServiceMinimal {
  static MultipartFile toMultipartFile(dynamic file, String fieldName) {
    // Minimal implementation that only handles basic cases
    if (file is String) {
      return MultipartFile.fromFileSync(
        file,
        filename: file.split('\\').last,
      );
    } else {
      throw Exception('Desktop file upload requires file path string');
    }
  }
}
