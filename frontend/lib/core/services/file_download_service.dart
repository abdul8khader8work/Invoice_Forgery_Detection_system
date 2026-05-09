import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class FileDownloadService {
  static Future<void> downloadFile({
    required String filename,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    if (kIsWeb) {
      // For web, we'll need to implement this differently
      // For now, show a message
      throw Exception('Web download temporarily disabled for cross-platform compatibility');
    } else {
      // For desktop, show message that download is not implemented yet
      throw Exception(
        'Desktop file saving not implemented yet. File: $filename, Size: ${bytes.length} bytes',
      );
    }
  }

  static Future<void> downloadJsonFile({
    required String filename,
    required Map<String, dynamic> jsonData,
  }) async {
    final jsonString = jsonEncode(jsonData);
    final bytes = utf8.encode(jsonString);
    await downloadFile(
      filename: filename,
      bytes: Uint8List.fromList(bytes),
      mimeType: 'application/json',
    );
  }

  static Future<void> copyToClipboard(String text) async {
    // For now, we'll skip clipboard functionality to maintain cross-platform compatibility
    // TODO: Implement platform-specific clipboard functionality
  }

  static void showDownloadNotAvailableMessage(
    BuildContext context,
    String filename,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('File download for desktop coming soon. File: $filename'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Dismiss',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}
