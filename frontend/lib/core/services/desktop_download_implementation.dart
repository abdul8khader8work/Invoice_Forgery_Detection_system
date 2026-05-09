import 'dart:typed_data';
import 'package:flutter/material.dart';

class DesktopDownloadImplementation {
  static Future<void> downloadFile({
    required String filename,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    // For desktop, show message that download is not implemented yet
    throw Exception(
      'Desktop file saving not implemented yet. File: $filename, Size: ${bytes.length} bytes',
    );
  }

  static Future<void> copyToClipboard(String text) async {
    // For desktop, clipboard implementation varies by platform
    // For now, we'll return without doing anything
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
