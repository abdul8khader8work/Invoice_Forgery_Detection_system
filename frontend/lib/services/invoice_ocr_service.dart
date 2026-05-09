import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

/// Invoice data model matching the API response
class ExtractedInvoiceData {
  final String? vendorName;
  final String? invoiceDate;
  final String? totalAmount;
  final String? taxAmount;
  final String? invoiceNumber;
  final String? subtotal;
  final String? currency;
  final double extractionConfidence;
  final int fieldsFound;

  ExtractedInvoiceData({
    this.vendorName,
    this.invoiceDate,
    this.totalAmount,
    this.taxAmount,
    this.invoiceNumber,
    this.subtotal,
    this.currency,
    required this.extractionConfidence,
    required this.fieldsFound,
  });

  factory ExtractedInvoiceData.fromJson(Map<String, dynamic> json) {
    final invoiceData = json['invoice_data'] ?? {};
    return ExtractedInvoiceData(
      vendorName: invoiceData['vendor_name'],
      invoiceDate: invoiceData['invoice_date'],
      totalAmount: invoiceData['total_amount'],
      taxAmount: invoiceData['tax_amount'],
      invoiceNumber: invoiceData['invoice_number'],
      subtotal: invoiceData['subtotal'],
      currency: invoiceData['currency'],
      extractionConfidence: (invoiceData['extraction_confidence'] ?? 0.0).toDouble(),
      fieldsFound: invoiceData['fields_found'] ?? 0,
    );
  }

  bool get isComplete => 
    vendorName != null && 
    invoiceDate != null && 
    totalAmount != null &&
    invoiceNumber != null;

  Map<String, dynamic> toMap() {
    return {
      'vendor_name': vendorName,
      'invoice_date': invoiceDate,
      'total_amount': totalAmount,
      'tax_amount': taxAmount,
      'invoice_number': invoiceNumber,
      'subtotal': subtotal,
      'currency': currency,
    };
  }
}

/// OCR Service that automatically sends images to PaddleOCR API
class InvoiceOCRService {
  // Your FastAPI backend URL
  static const String _baseUrl = 'http://127.0.0.1:8000';
  static const String _extractEndpoint = '$_baseUrl/extract';
  static const String _healthEndpoint = '$_baseUrl/health';

  /// Check if OCR service is healthy
  static Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse(_healthEndpoint))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Extract invoice data from image file
  /// 
  /// [filePath] - Path to the invoice image (from image_picker)
  /// Returns [ExtractedInvoiceData] with all extracted fields
  /// 
  /// Usage in your Scan button:
  /// ```dart
  /// final result = await InvoiceOCRService.extractInvoice(imagePath);
  /// if (result != null) {
  ///   _vendorController.text = result.vendorName ?? '';
  ///   _totalController.text = result.totalAmount ?? '';
  ///   // ... auto-fill all fields
  /// }
  /// ```
  static Future<ExtractedInvoiceData?> extractInvoice(String filePath) async {
    try {
      print('Starting invoice extraction...');
      print('File: $filePath');

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final fileSize = await file.length();
      print('File size: $fileSize bytes');

      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_extractEndpoint));

      // Detect MIME type
      final mimeType = lookupMimeType(filePath) ?? 'image/jpeg';
      final mimeParts = mimeType.split('/');

      // Add file to request
      request.files.add(
        http.MultipartFile(
          'file',
          file.openRead(),
          fileSize,
          filename: filePath.split('/').last,
          contentType: MediaType(mimeParts[0], mimeParts[1]),
        ),
      );

      print('Sending request to $_extractEndpoint...');

      // Send request
      final streamedResponse = await request.send()
          .timeout(const Duration(seconds: 60)); // OCR can take time

      final response = await http.Response.fromStream(streamedResponse);

      print('Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        
        if (jsonData['success'] == true) {
          print('Extraction successful!');
          print('Processing time: ${jsonData['processing_time_ms']}ms');
          
          final data = ExtractedInvoiceData.fromJson(jsonData);
          print('Fields found: ${data.fieldsFound}');
          print('Confidence: ${data.extractionConfidence}');
          
          return data;
        } else {
          print('Extraction failed: ${jsonData['message']}');
          throw Exception(jsonData['message'] ?? 'Extraction failed');
        }
      } else if (response.statusCode == 400) {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Invalid image file');
      } else if (response.statusCode == 500) {
        throw Exception('OCR server error. Please try again.');
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('Extraction error: $e');
      rethrow;
    }
  }

  /// Quick extraction for testing (returns raw response)
  static Future<Map<String, dynamic>?> extractRaw(String filePath) async {
    try {
      final file = File(filePath);
      final request = http.MultipartRequest(
        'POST', 
        Uri.parse('$_baseUrl/ocr-raw')
      );

      final mimeType = lookupMimeType(filePath) ?? 'image/jpeg';
      final mimeParts = mimeType.split('/');

      request.files.add(
        http.MultipartFile(
          'file',
          file.openRead(),
          await file.length(),
          filename: filePath.split('/').last,
          contentType: MediaType(mimeParts[0], mimeParts[1]),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Raw extraction error: $e');
      return null;
    }
  }
}
