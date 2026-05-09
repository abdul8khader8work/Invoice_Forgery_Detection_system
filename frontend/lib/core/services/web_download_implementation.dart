import 'dart:html' as html;
import 'dart:typed_data';

class WebDownloadImplementation {
  static Future<void> downloadFile({
    required String filename,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final blob = html.Blob([bytes], mimeType ?? 'application/octet-stream');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static Future<void> copyToClipboard(String text) async {
    await html.window.navigator.clipboard?.writeText(text);
  }
}
