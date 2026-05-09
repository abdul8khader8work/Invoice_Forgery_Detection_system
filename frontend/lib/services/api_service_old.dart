import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/scan_result.dart';

class ApiService {
  static const String _baseUrl = 'http://127.0.0.1:8000';
  static const Duration _timeout = Duration(seconds: 30);

  Future<ScanResult> scanInvoice(Uint8List fileBytes, String filename) async {
    try {
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

      // Send request
      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        return ScanResult.fromJson(jsonResponse);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to scan invoice: $e');
    }
  }

  Future<Map<String, dynamic>> verifyInvoice(String fileId, Map<String, dynamic> verifiedData) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/verify/$fileId'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(verifiedData),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to verify invoice: $e');
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
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to check health: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getInvoices({
    int skip = 0,
    int limit = 100,
    String? riskLevel,
  }) async {
    try {
      final queryParams = <String, String>{
        'skip': skip.toString(),
        'limit': limit.toString(),
      };
      
      if (riskLevel != null) {
        queryParams['risk_level'] = riskLevel;
      }

      final uri = Uri.parse('$_baseUrl/invoices').replace(
        queryParameters: queryParams,
      );

      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        return List<Map<String, dynamic>>.from(jsonResponse['invoices'] ?? []);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get invoices: $e');
    }
  }

  bool isBackendAvailable() {
    // Simple check - in production, you might want to ping the server
    return true;
  }
}
