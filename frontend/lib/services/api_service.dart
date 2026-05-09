import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/scan_result.dart';
import '../config.dart';

class ApiService {
  // FORCED: Using config file
  static const String _baseUrl = AppConfig.apiBaseUrl;
  static const Duration _timeout = AppConfig.apiTimeout;

  Future<ScanResult> scanInvoice(Uint8List fileBytes, String filename) async {
    try {
      print('API Request to: $_baseUrl/scan');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/scan'),
      );

      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename,
        ),
      );

      print('Sending request...');
      
      final response = await request.send().timeout(_timeout);
      
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        print('Raw response body: $responseBody');
        final Map<String, dynamic> jsonResponse = json.decode(responseBody);
        print('Parsed JSON keys: ${jsonResponse.keys}');
        print('Scan successful!');
        return ScanResult.fromJson(jsonResponse);
      } else {
        print('Scan failed with status: ${response.statusCode}');
        throw Exception('Failed to scan invoice: Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('API Error: $e');
      throw Exception('Failed to scan invoice: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Health check failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to check health: ${e.toString()}');
    }
  }

  Future<List<dynamic>> getInvoices({
    int skip = 0,
    int limit = 100,
    String? riskLevel,
  }) async {
    try {
      String url = '$_baseUrl/invoices?skip=$skip&limit=$limit';
      if (riskLevel != null) {
        url += '&risk_level=$riskLevel';
      }

      final response = await http.get(
        Uri.parse(url),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['invoices'] ?? [];
      } else {
        throw Exception('Failed to get invoices: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get invoices: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> deleteInvoice(String fileId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/invoices/$fileId'),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to delete invoice: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to delete invoice: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> verifyInvoice(
    String fileId,
    Map<String, dynamic> verifiedData,
  ) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/invoices/$fileId'),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to delete invoice: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to delete invoice: ${e.toString()}');
    }
  }
}
