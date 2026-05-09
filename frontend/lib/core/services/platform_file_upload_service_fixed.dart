import 'dart:io';
import 'package:dio/dio.dart';

class PlatformFileUploadServiceFixed {
  static MultipartFile toMultipartFile(dynamic file, String fieldName) {
    // Simple implementation that handles both File and String
    String filePath;
    
    if (file is String) {
      filePath = file;
    } else if (file is File) {
      filePath = file.path;
    } else {
      throw Exception('Unsupported file type: ${file.runtimeType}');
    }
    
    final fileObj = File(filePath);
    return MultipartFile.fromFileSync(
      filePath,
      filename: fileObj.path.split('\\').last,
    );
  }
}
