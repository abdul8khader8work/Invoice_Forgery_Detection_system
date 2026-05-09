import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

class PlatformFileUploadServiceIOSimple {
  static MultipartFile toMultipartFile(dynamic file, String fieldName) {
    // Handle String path, File object, or PlatformFile from file_picker
    String? filePath;
    List<int>? fileBytes;
    String? fileName;
    
    if (file is String) {
      filePath = file;
      fileName = file.split(Platform.pathSeparator).last;
    } else if (file is File) {
      filePath = file.path;
      fileName = file.path.split(Platform.pathSeparator).last;
    } else if (file is PlatformFile) {
      // Handle PlatformFile from file_picker (desktop/web)
      fileName = file.name;
      if (file.path != null) {
        filePath = file.path;
      } else if (file.bytes != null) {
        fileBytes = file.bytes;
      } else {
        throw Exception('PlatformFile has neither path nor bytes: ${file.name}');
      }
    } else {
      throw Exception('Unsupported file type: ${file.runtimeType}');
    }
    
    // Use bytes if available (for web), otherwise use file path
    if (fileBytes != null) {
      return MultipartFile.fromBytes(
        fileBytes,
        filename: fileName ?? 'upload',
      );
    }
    
    // Use file path for desktop/mobile
    final fileObj = File(filePath!);
    if (!fileObj.existsSync()) {
      throw Exception('File not found: $filePath');
    }
    return MultipartFile.fromFileSync(
      filePath,
      filename: fileName ?? filePath.split(Platform.pathSeparator).last,
    );
  }
}
