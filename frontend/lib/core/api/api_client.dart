import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:invoice_forgery_detection/core/api/models/scan_request.dart';
import 'package:invoice_forgery_detection/core/api/models/scan_response.dart';
import 'package:invoice_forgery_detection/core/api/models/batch_scan_request.dart';
import 'package:invoice_forgery_detection/core/api/models/batch_scan_response.dart';
import 'package:invoice_forgery_detection/core/config/app_config.dart';
import 'dart:io';

/// Typed API client for Invoice Forgery Detection API
/// Uses Dio with retry logic and interceptors
class InvoiceApiClient {
  final Dio _dio;
  final String baseUrl;

  InvoiceApiClient({
    String? baseUrl,
    Dio? dio,
  }) : _dio = dio ?? Dio(), 
       baseUrl = baseUrl ?? AppConfig.backendUrl {
    _setupDio();
  }

  /// Public getter for Dio instance for direct HTTP requests
  Dio get dio => _dio;

  void _setupDio() {
    _dio.options.baseUrl = baseUrl;
    print('🔗 ApiClient initializing with baseUrl: $baseUrl');
    _dio.options.connectTimeout = const Duration(seconds: 30);
    // ✅ Web gets longer timeouts for LLM processing
    _dio.options.receiveTimeout = kIsWeb 
        ? const Duration(minutes: 8)  // 8 minutes for web
        : const Duration(minutes: 5);  // 5 minutes for desktop/mobile
    _dio.options.sendTimeout = kIsWeb
        ? const Duration(minutes: 5)   // 5 minutes for web uploads
        : const Duration(minutes: 5);  // 5 minutes for desktop/mobile uploads

    // Add retry interceptor
    _dio.interceptors.add(RetryInterceptor(
      dio: _dio,
      retries: 3,
      retryDelays: const [
        Duration(seconds: 1),  // First retry after 1s
        Duration(seconds: 2),  // Second retry after 2s
        Duration(seconds: 4),  // Third retry after 4s (exponential backoff)
      ],
    ));

    // Add logging interceptor (debug only)
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
    ));
  }

  /// Health check
  Future<Map<String, dynamic>> healthCheck() async {
    try {
      final response = await _dio.get('/health');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Scan single invoice
  Future<ScanResponse> scanInvoice(ScanRequest request) async {
    // Create a separate Dio instance without retry for FormData requests
    // FormData cannot be reused in retries
    final scanDio = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: _dio.options.connectTimeout,
      receiveTimeout: _dio.options.receiveTimeout,
      sendTimeout: _dio.options.sendTimeout,
    ));

    // Add logging interceptor only
    scanDio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
    ));

    try {
      final formData = FormData();
      formData.files.add(MapEntry(
        'file',
        request.file,
      ));

      final response = await scanDio.post('/scan', data: formData);
      return ScanResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// ✅ NEW: PDF-aware upload method with smart timeout
  Future<ScanResponse> scanInvoiceWithFile(File file, {String endpoint = '/scan'}) async {
    // Detect file type
    final isPdf = file.path.toLowerCase().endsWith('.pdf');
    
    // Create custom options for PDFs
    final options = Options(
      responseType: ResponseType.json,
      // ✅ PDFs get 5 minutes, images get 2 minutes
      receiveTimeout: isPdf ? const Duration(minutes: 5) : const Duration(minutes: 2),
      sendTimeout: isPdf ? const Duration(minutes: 5) : const Duration(minutes: 2),
    );

    // Create a separate Dio instance for FormData requests
    final scanDio = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: _dio.options.connectTimeout,
      receiveTimeout: options.receiveTimeout!,
      sendTimeout: options.sendTimeout!,
    ));

    // Add logging interceptor only
    scanDio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
    ));

    try {
      final formData = FormData();
      formData.files.add(MapEntry(
        'file',
        await MultipartFile.fromFile(file.path),
      ));

      final response = await scanDio.post(endpoint, data: formData);
      return ScanResponse.fromJson(response.data);
    } on DioException catch (e) {
      // ✅ Enhanced error handling for PDFs
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout) {
        if (isPdf) {
          throw Exception(
            'PDF processing is taking longer than expected.\n\n'
            'This can happen with:\n'
            '- Large PDF files (>5MB)\n'
            '- Complex/scanned PDFs\n'
            '- Server under heavy load\n\n'
            'Please try again, or convert PDF to JPG/PNG for faster processing.'
          );
        }
        throw Exception('Request timed out. Please check your connection and try again.');
      }
      throw _handleError(e);
    }
  }

  /// Get scan status
  Future<Map<String, dynamic>> getScanStatus(String scanId) async {
    try {
      final response = await _dio.get('/scan/status/$scanId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Download invoice report
  Future<Map<String, dynamic>> downloadInvoiceReport(String fileId) async {
    try {
      final response = await _dio.get('/invoices/$fileId/report');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Approve invoice
  Future<Map<String, dynamic>> approveInvoice(String fileId) async {
    try {
      final response = await _dio.put('/invoices/$fileId/approve');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Edit invoice data
  Future<Map<String, dynamic>> editInvoiceData(String fileId, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/invoices/$fileId/edit', data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get invoices list
  Future<Map<String, dynamic>> getInvoices({
    int skip = 0,
    int limit = 10,
    String? riskLevel,
    String? vendor,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'skip': skip,
        'limit': limit,
      };
      if (riskLevel != null) queryParams['risk_level'] = riskLevel;
      if (vendor != null) queryParams['vendor'] = vendor;
      if (startDate != null) queryParams['start_date'] = startDate;
      if (endDate != null) queryParams['end_date'] = endDate;

      final response = await _dio.get('/invoices', queryParameters: queryParams);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Generic GET request for custom endpoints
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParameters);
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get invoice by ID
  Future<Map<String, dynamic>> getInvoice(String invoiceId) async {
    try {
      final response = await _dio.get('/invoices/$invoiceId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Verify invoice
  Future<Map<String, dynamic>> verifyInvoice(
    String invoiceId, {
    required bool verified,
    String? notes,
  }) async {
    try {
      final response = await _dio.post(
        '/verify/$invoiceId',
        data: {
          'verified': verified,
          if (notes != null) 'notes': notes,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get invoice audit history
  Future<Map<String, dynamic>> getInvoiceAuditHistory(String invoiceId) async {
    try {
      final response = await _dio.get('/api/invoices/$invoiceId/audit');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Generate audit report
  Future<Map<String, dynamic>> generateAuditReport({
    required List<String> invoiceIds,
    required String formatType,
  }) async {
    try {
      final response = await _dio.post(
        '/api/reports/generate',
        data: {
          'invoice_ids': invoiceIds,
          'format_type': formatType,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Exception _handleError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('Connection timeout. Please check your internet connection.');
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        if (statusCode == 400) {
          return Exception('Bad request: ${error.response?.data['detail'] ?? 'Invalid input'}');
        } else if (statusCode == 401) {
          return Exception('Unauthorized access');
        } else if (statusCode == 404) {
          return Exception('Resource not found');
        } else if (statusCode == 500) {
          return Exception('Server error. Please try again later.');
        } else {
          return Exception('HTTP error $statusCode: ${error.message}');
        }
      case DioExceptionType.cancel:
        return Exception('Request was cancelled');
      case DioExceptionType.unknown:
        return Exception('Network error: ${error.message}');
      default:
        return Exception('Unexpected error: ${error.message}');
    }
  }
}

/// Retry interceptor for Dio
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final List<Duration> retryDelays;

  RetryInterceptor({
    required this.dio,
    required this.retries,
    required this.retryDelays,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final extra = err.requestOptions.extra;
    final currentRetry = extra['retry_count'] ?? 0;

    if (currentRetry < retries && _shouldRetry(err)) {
      final delay = retryDelays[currentRetry];
      
      Future.delayed(delay, () {
        final options = err.requestOptions;
        options.extra['retry_count'] = currentRetry + 1;
        
        // Retry the request
        dio.fetch(options).then(
          handler.resolve,
          onError: (e) => handler.next(e as DioException),
        );
      });
      return;
    }

    handler.next(err);
  }

  bool _shouldRetry(DioException error) {
    // Retry on timeout, connection errors, and 5xx errors
    return error.type == DioExceptionType.connectionTimeout ||
           error.type == DioExceptionType.sendTimeout ||
           error.type == DioExceptionType.receiveTimeout ||
           (error.type == DioExceptionType.badResponse &&
            error.response?.statusCode != null &&
            error.response!.statusCode! >= 500);
  }
}
