import 'dart:typed_data';
import 'package:flutter/material.dart';

class DesktopFileDownloadService {
  static Future<void> downloadFile({
    required String filename,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    // For desktop, we'll need to implement file saving
    // For now, we show a message that it's not implemented
    throw Exception(
      'Desktop file saving not implemented yet. File: $filename, Size: ${bytes.length} bytes',
    );
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
