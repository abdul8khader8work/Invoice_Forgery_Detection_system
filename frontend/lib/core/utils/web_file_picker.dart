import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';

/// Platform-aware file picker helper
/// Handles web (dart:html) and mobile/desktop (file_picker) file selection
class WebFilePicker {
  /// Pick a file with specified allowed extensions
  /// Returns PlatformFile on mobile/desktop, html.File on web
  static Future<dynamic> pickFile({required List<String> allowedExtensions}) async {
    if (kIsWeb) {
      // Web: use html file input
      final input = html.FileUploadInputElement();
      input.accept = allowedExtensions.map((e) => '.$e').join(',');
      input.click();
      
      await input.onChange.first;
      
      if (input.files?.isNotEmpty ?? false) {
        return input.files!.first; // Returns html.File
      }
      return null;
    } else {
      // Mobile/Desktop: use file_picker package
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        return result.files.single; // Returns PlatformFile
      }
      return null;
    }
  }

  /// Pick multiple files
  static Future<List<dynamic>> pickFiles({required List<String> allowedExtensions}) async {
    if (kIsWeb) {
      final input = html.FileUploadInputElement();
      input.accept = allowedExtensions.map((e) => '.$e').join(',');
      input.multiple = true;
      input.click();
      
      await input.onChange.first;
      
      if (input.files?.isNotEmpty ?? false) {
        return input.files!.toList();
      }
      return [];
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: true,
      );
      
      if (result != null && result.files.isNotEmpty) {
        return result.files.toList();
      }
      return [];
    }
  }
}
