import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoice_forgery_detection/core/api/api_client.dart';
import '../config/app_config.dart';

/// Provider for the API client base URL
final apiBaseUrlProvider = Provider<String>((ref) {
  // Platform-specific backend URLs
  if (kIsWeb) {
    // Web - use localhost
    return 'http://localhost:8000';
  } else if (Platform.isAndroid) {
    // Android device - use computer IP
    return AppConfig.apiBaseUrl;
  } else if (Platform.isWindows) {
    // Windows desktop - use localhost
    return 'http://localhost:8000';
  } else {
    // Default
    return 'http://localhost:8000';
  }
});

/// Provider for the Invoice API client
final invoiceApiClientProvider = Provider<InvoiceApiClient>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  return InvoiceApiClient(baseUrl: baseUrl);
});
