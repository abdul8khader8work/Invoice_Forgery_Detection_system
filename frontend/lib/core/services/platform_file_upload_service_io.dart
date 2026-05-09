import 'dart:io';
import 'package:dio/dio.dart';

class PlatformFileUploadServiceIO {
  static MultipartFile toMultipartFile(dynamic file, String fieldName) {
    if (file is String) {
      final fileObj = File(file);
      return MultipartFile.fromFileSync(
        file,
        filename: fileObj.path.split('\\').last,
      );
    } else if (file is File) {
      return MultipartFile.fromFileSync(
        file.path,
        filename: file.path.split('\\').last,
      );
    } else {
      throw Exception('Unsupported file type: ${file.runtimeType}');
    }
  }
}
