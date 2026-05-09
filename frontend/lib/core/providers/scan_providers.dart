import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:invoice_forgery_detection/core/api/api_client.dart';
import 'package:invoice_forgery_detection/core/api/models/scan_response.dart';
import 'package:invoice_forgery_detection/core/api/models/scan_request.dart';
import 'package:invoice_forgery_detection/core/providers/api_providers.dart';
import 'package:invoice_forgery_detection/core/services/platform_file_upload_service.dart';
import 'dart:io';

/// Scan upload state
class ScanUploadState {
  final bool isUploading;
  final double progress;
  final ScanResponse? result;
  final String? error;
  final bool isGrokProcessing;
  final bool isGrokFallback;

  const ScanUploadState({
    this.isUploading = false,
    this.progress = 0.0,
    this.result,
    this.error,
    this.isGrokProcessing = false,
    this.isGrokFallback = false,
  });

  ScanUploadState copyWith({
    bool? isUploading,
    double? progress,
    ScanResponse? result,
    String? error,
    bool? isGrokProcessing,
    bool? isGrokFallback,
  }) {
    return ScanUploadState(
      isUploading: isUploading ?? this.isUploading,
      progress: progress ?? this.progress,
      result: result ?? this.result,
      error: error ?? this.error,
      isGrokProcessing: isGrokProcessing ?? this.isGrokProcessing,
      isGrokFallback: isGrokFallback ?? this.isGrokFallback,
    );
  }
}

/// Scan upload notifier for state management
class ScanUploadNotifier extends StateNotifier<ScanUploadState> {
  final InvoiceApiClient _apiClient;

  ScanUploadNotifier(this._apiClient) : super(const ScanUploadState());

  /// Upload and scan invoice
  Future<void> scanInvoice(dynamic file) async {
    state = state.copyWith(
      isUploading: true,
      progress: 0.0,
      error: null,
      result: null,
      isGrokProcessing: true,
      isGrokFallback: false,
    );

    try {
      // Simulate progress updates
      state = state.copyWith(progress: 0.2);

      // Convert file to MultipartFile using the existing service
      final multipartFile = await PlatformFileUploadService.toMultipartFile(file, 'file');

      state = state.copyWith(progress: 0.4);

      // Upload using the existing scanInvoice method
      final response = await _apiClient.scanInvoice(
        ScanRequest(file: multipartFile),
      );

      state = state.copyWith(progress: 0.8);

      if (response.success && response.extractedData != null) {
        state = state.copyWith(
          isUploading: false,
          progress: 1.0,
          result: response,
          isGrokProcessing: false,
          isGrokFallback: false,
        );
      } else {
        // Check if this is a Grok fallback scenario
        final isGrokFallback = response.error?.toLowerCase().contains('grok') ?? false;
        state = state.copyWith(
          isUploading: false,
          progress: 1.0,
          result: response,
          error: response.error,
          isGrokProcessing: false,
          isGrokFallback: isGrokFallback,
        );
      }
    } catch (e) {
      // Check if error is related to Grok API
      final isGrokError = e.toString().toLowerCase().contains('grok') ||
                          e.toString().toLowerCase().contains('llm');
      
      state = state.copyWith(
        isUploading: false,
        progress: 0.0,
        error: e.toString(),
        isGrokProcessing: false,
        isGrokFallback: isGrokError,
      );
    }
  }

  /// Reset state
  void reset() {
    state = const ScanUploadState();
  }
}

/// Provider for scan upload state
final scanUploadProvider =
    StateNotifierProvider.autoDispose<ScanUploadNotifier, ScanUploadState>((ref) {
  final apiClient = ref.watch(invoiceApiClientProvider);
  return ScanUploadNotifier(apiClient);
});

/// Provider for scan result (cached)
final scanResultProvider = Provider.autoDispose<ScanResponse?>((ref) {
  return ref.watch(scanUploadProvider).result;
});
