import 'dart:convert';
import 'package:http/http.dart' as http;
import 'core/config/app_config.dart';

class ActiveLearningService {
  static const String _baseUrl = AppConfig.apiBaseUrl;
  static const Duration _timeout = Duration(seconds: 30);

  /// Submit field corrections to refine the template
  /// This is the core feedback loop - user corrections teach the system
  static Future<Map<String, dynamic>> refineTemplate({
    required String fileId,
    required int logId,
    required String styleTag,
    required List<Map<String, dynamic>> corrections,
    String correctedBy = 'user',
  }) async {
    final url = Uri.parse('$_baseUrl/active-learning/templates/refine');
    
    final body = {
      'file_id': fileId,
      'log_id': logId,
      'style_tag': styleTag,
      'corrected_by': correctedBy,
      'corrections': corrections.map((c) => {
        'field_name': c['field_name'],
        'original_value': c['original_value'],
        'corrected_value': c['corrected_value'],
        'original_bbox': c['original_bbox'],
        'corrected_bbox': c['corrected_bbox'],
        'anchor_bbox': c['anchor_bbox'],
      }).toList(),
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to refine template: ${response.statusCode} - ${response.body}');
    }
  }

  /// Process invoice using active learning pipeline
  static Future<Map<String, dynamic>> processInvoice({
    required List<int> fileBytes,
    required String filename,
    String? styleHint,
    bool forceNewTemplate = false,
  }) async {
    final url = Uri.parse('$_baseUrl/active-learning/process-invoice');
    
    final request = http.MultipartRequest('POST', url);
    
    // Add file
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
      ),
    );
    
    // Add optional parameters
    if (styleHint != null) {
      request.fields['style_hint'] = styleHint;
    }
    if (forceNewTemplate) {
      request.fields['force_new_template'] = 'true';
    }
    
    final streamedResponse = await request.send().timeout(Duration(seconds: 120));
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to process invoice: ${response.statusCode} - ${response.body}');
    }
  }

  /// Get extraction log for displaying correction UI
  static Future<Map<String, dynamic>> getExtractionLog(String fileId) async {
    final url = Uri.parse('$_baseUrl/active-learning/extraction-logs/$fileId');
    
    final response = await http.get(url).timeout(_timeout);
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get extraction log: ${response.statusCode}');
    }
  }

  /// List all learned templates
  static Future<List<Map<String, dynamic>>> listTemplates({
    double minConfidence = 0.0,
    int limit = 100,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/active-learning/templates?min_confidence=$minConfidence&limit=$limit'
    );
    
    final response = await http.get(url).timeout(_timeout);
    
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to list templates: ${response.statusCode}');
    }
  }
}
