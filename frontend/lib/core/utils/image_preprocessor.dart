import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Image preprocessing utility for performance optimization
/// Resizes images to max 1920px and compresses to JPEG 85%
class ImagePreprocessor {
  static const int maxImageSize = 1920;
  static const int jpegQuality = 85;

  /// Preprocess image file before upload
  /// Returns the processed file path
  static Future<File> preprocessImage(File imageFile) async {
    try {
      // Read image
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        // If image can't be decoded, return original
        return imageFile;
      }

      // Resize if needed
      img.Image processedImage = image;
      if (image.width > maxImageSize || image.height > maxImageSize) {
        processedImage = img.copyResize(
          image,
          width: maxImageSize,
          height: maxImageSize,
          maintainAspect: true,
        );
      }

      // Compress to JPEG
      final compressedBytes = img.encodeJpg(processedImage, quality: jpegQuality);

      // Create temp file with processed image
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/processed_$timestamp.jpg');
      await tempFile.writeAsBytes(compressedBytes);

      return tempFile;
    } catch (e) {
      // On error, return original file
      print('Image preprocessing failed: $e');
      return imageFile;
    }
  }

  /// Get file size in human-readable format
  static String getFileSize(File file) {
    final bytes = file.lengthSync();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
