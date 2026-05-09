import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoice_forgery_detection/core/api/api_client.dart';
import 'package:invoice_forgery_detection/core/providers/api_providers.dart';

/// Status polling state
class ScanPollingState {
  final bool isPolling;
  final String? taskId;
  final Map<String, dynamic>? status;
  final String? error;

  const ScanPollingState({
    this.isPolling = false,
    this.taskId,
    this.status,
    this.error,
  });

  ScanPollingState copyWith({
    bool? isPolling,
    String? taskId,
    Map<String, dynamic>? status,
    String? error,
  }) {
    return ScanPollingState(
      isPolling: isPolling ?? this.isPolling,
      taskId: taskId ?? this.taskId,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}

/// Status polling notifier for async scan operations
class ScanPollingNotifier extends StateNotifier<ScanPollingState> {
  final InvoiceApiClient _apiClient;
  Timer? _pollingTimer;

  ScanPollingNotifier(this._apiClient) : super(const ScanPollingState());

  /// Start polling for scan status
  Future<void> startPolling(String taskId) async {
    state = state.copyWith(
      isPolling: true,
      taskId: taskId,
      error: null,
    );

    // Poll every 2 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkStatus(taskId);
    });
  }

  /// Check scan status
  Future<void> _checkStatus(String taskId) async {
    try {
      // TODO: Implement status check endpoint when backend supports async scanning
      // For now, this is a placeholder for future async implementation
      // final status = await _apiClient.getScanStatus(taskId);
      
      // Stop polling when complete
      // if (status['status'] == 'completed') {
      //   _stopPolling();
      //   state = state.copyWith(
      //     isPolling: false,
      //     status: status,
      //   );
      // }
    } catch (e) {
      _stopPolling();
      state = state.copyWith(
        isPolling: false,
        error: e.toString(),
      );
    }
  }

  /// Stop polling
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Reset state
  void reset() {
    _stopPolling();
    state = const ScanPollingState();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

/// Provider for scan polling state
final scanPollingProvider =
    StateNotifierProvider<ScanPollingNotifier, ScanPollingState>((ref) {
  final apiClient = ref.watch(invoiceApiClientProvider);
  return ScanPollingNotifier(apiClient);
});

/// Stream provider for real-time status updates (future implementation)
final scanStatusStreamProvider = StreamProvider<Map<String, dynamic>>((ref) {
  // TODO: Implement WebSocket or SSE stream for real-time updates
  return const Stream.empty();
});
