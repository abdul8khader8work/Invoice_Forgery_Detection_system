import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class FileUtils {
  /// Convert PlatformFile (from FilePicker) to File
  static Future<File> platformFileToFile(PlatformFile platformFile) async {
    if (platformFile.path != null) {
      // File from local storage
      return File(platformFile.path!);
    }
    
    // File from cloud/camera - needs temporary storage
    if (platformFile.bytes == null) {
      throw Exception('No file data available');
    }
    
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${platformFile.name}');
    await tempFile.writeAsBytes(platformFile.bytes!);
    
    return tempFile;
  }
  
  /// Convert XFile (from ImagePicker) to File
  static Future<File> xFileToFile(XFile xFile) async {
    // XFile already has a path
    return File(xFile.path);
  }
  
  /// Convert multiple PlatformFiles to Files
  static Future<List<File>> platformFilesToFiles(List<PlatformFile> platformFiles) async {
    final files = <File>[];
    
    for (var platformFile in platformFiles) {
      try {
        final file = await platformFileToFile(platformFile);
        files.add(file);
      } catch (e) {
        print('❌ Error converting file ${platformFile.name}: $e');
        // Skip this file and continue
      }
    }
    
    return files;
  }
  
  /// Get file extension
  static String getFileExtension(String fileName) {
    return fileName.split('.').last.toLowerCase();
  }
  
  /// Check if file type is supported
  static bool isSupportedFile(String fileName) {
    final ext = getFileExtension(fileName);
    return ['pdf', 'jpg', 'jpeg', 'png'].contains(ext);
  }
  
  /// Format file size for display
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  /// Check if file is PDF
  static bool isPdfFile(String fileName) {
    return getFileExtension(fileName) == 'pdf';
  }
  
  /// Check if file is image
  static bool isImageFile(String fileName) {
    final ext = getFileExtension(fileName);
    return ['jpg', 'jpeg', 'png'].contains(ext);
  }
  
  /// Get file info as a map for display
  static Future<Map<String, dynamic>> getFileInfo(File file) async {
    final stat = await file.stat();
    return {
      'name': file.path.split('/').last,
      'path': file.path,
      'size': stat.size,
      'sizeFormatted': formatFileSize(stat.size),
      'type': getFileExtension(file.path),
      'isPdf': isPdfFile(file.path),
      'isImage': isImageFile(file.path),
      'lastModified': stat.modified,
    };
  }
}
