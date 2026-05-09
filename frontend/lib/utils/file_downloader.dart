import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;

class FileDownloader {
  /// Download content as a file
  static void download({
    required String content,
    required String filename,
    required String mimeType,
  }) {
    if (kIsWeb) {
      final bytes = Uint8List.fromList(utf8.encode(content));
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = filename;
      
      html.document.body!.children.add(anchor);
      anchor.click();
      
      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    }
  }
  
  /// Download JSON data
  static void downloadJson(Map<String, dynamic> data, String filename) {
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    download(
      content: jsonString,
      filename: filename,
      mimeType: 'application/json',
    );
  }
  
  /// Download text/PDF content
  static void downloadText(String content, String filename, {bool isPdf = false}) {
    download(
      content: content,
      filename: filename,
      mimeType: isPdf ? 'application/pdf' : 'text/plain',
    );
  }
  
  /// Download bytes (for images, PDFs, etc.)
  static void downloadBytes(Uint8List bytes, String filename, String mimeType) {
    if (kIsWeb) {
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = filename;
      
      html.document.body!.children.add(anchor);
      anchor.click();
      
      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    }
  }
}
