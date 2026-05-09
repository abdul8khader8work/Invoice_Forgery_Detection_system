import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../config.dart';

class SmartIngestionResult {
  final bool success;
  final String? errorMessage;
  final String? status;
  final String? filePath;
  final String? message;
  final Map<String, dynamic>? rawResponse;

  SmartIngestionResult({
    required this.success,
    this.errorMessage,
    this.status,
    this.filePath,
    this.message,
    this.rawResponse,
  });
}

class SmartIngestionService {
  late final Dio _dio;
  static const String _baseUrl = AppConfig.apiBaseUrl;
  static const Duration _timeout = Duration(seconds: 60);

  SmartIngestionService() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      sendTimeout: _timeout,
      headers: {
        'Accept': 'application/json',
      },
    ));

    // Add interceptors for logging
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
    ));
  }

  /// Upload file to Smart Ingestion endpoint
  Future<SmartIngestionResult> ingestFile(
    Uint8List fileBytes,
    String filename,
    Function(double progress)? onProgress,
  ) async {
    try {
      print('🚀 Starting Smart Ingestion upload...');
      print('📁 File: $filename (${fileBytes.length} bytes)');

      // Create multipart form data
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: filename,
        ),
      });

      // Upload with progress tracking
      final response = await _dio.post(
        '/ingest',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
        onSendProgress: (sent, total) {
          if (total > 0) {
            final progress = sent / total;
            print('📤 Upload progress: ${(progress * 100).toStringAsFixed(1)}%');
            onProgress?.call(progress);
          }
        },
      );

      print('✅ Upload complete!');
      print('📥 Response: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return SmartIngestionResult(
          success: true,
          status: data['status'],
          filePath: data['file_path'],
          message: data['message'],
          rawResponse: data,
        );
      } else {
        return SmartIngestionResult(
          success: false,
          errorMessage: 'Server returned ${response.statusCode}',
          rawResponse: response.data,
        );
      }
    } on DioException catch (e) {
      print('❌ Dio Error: ${e.type}');
      print('❌ Message: ${e.message}');
      
      String errorMessage = 'Upload failed';
      
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
          errorMessage = 'Connection timeout. Please check your network.';
          break;
        case DioExceptionType.sendTimeout:
          errorMessage = 'Upload timeout. File may be too large.';
          break;
        case DioExceptionType.receiveTimeout:
          errorMessage = 'Server response timeout.';
          break;
        case DioExceptionType.badResponse:
          if (e.response?.statusCode == 422) {
            errorMessage = e.response?.data?['detail'] ?? 
                          'Invoice boundaries not found. Please retake the photo on a darker background.';
          } else if (e.response?.statusCode == 400) {
            errorMessage = e.response?.data?['detail'] ?? 'Invalid file format or corrupted file.';
          } else {
            errorMessage = 'Server error: ${e.response?.statusCode}';
          }
          break;
        case DioExceptionType.connectionError:
          errorMessage = 'Cannot connect to server. Is the backend running?';
          break;
        default:
          errorMessage = 'Network error: ${e.message}';
      }
      
      return SmartIngestionResult(
        success: false,
        errorMessage: errorMessage,
        rawResponse: e.response?.data,
      );
    } catch (e) {
      print('❌ Unexpected error: $e');
      return SmartIngestionResult(
        success: false,
        errorMessage: 'Unexpected error: $e',
      );
    }
  }

  /// Test backend connection
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
