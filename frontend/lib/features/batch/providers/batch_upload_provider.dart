import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/batch_upload_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:invoice_forgery_detection/core/providers/api_providers.dart';
import 'dart:io';

/// Batch upload service provider
final batchUploadServiceProvider = Provider<BatchUploadService>((ref) {
  final apiClient = ref.watch(invoiceApiClientProvider);
  return BatchUploadService(
    apiClient: apiClient,
    maxConcurrentUploads: 3,
    rateLimitDelayMs: 500,
  );
});

/// Batch upload state provider
final batchUploadStateProvider = StateNotifierProvider<BatchUploadNotifier, BatchUploadState>((ref) {
  final service = ref.watch(batchUploadServiceProvider);
  return BatchUploadNotifier(service);
});

/// Batch upload notifier
class BatchUploadNotifier extends StateNotifier<BatchUploadState> {
  final BatchUploadService _service;
  StreamSubscription<BatchUploadEvent>? _subscription;
  
  BatchUploadNotifier(this._service) : super(BatchUploadStateX.initial()) {
    _subscription = _service.events.listen((event) {
      _handleEvent(event);
    });
    state = _service.getState();
  }
  
  void _handleEvent(BatchUploadEvent event) {
    state = _service.getState();
    
    // Emit additional state changes if needed
    switch (event) {
      case TaskAddedEvent():
        break;
      case TaskProgressEvent():
        break;
      case TaskCompletedEvent():
        break;
      case TaskFailedEvent():
        break;
      case TaskCancelledEvent():
        break;
      case PausedEvent():
        break;
      case ResumedEvent():
        break;
      case CancelledEvent():
        break;
      case ClearedEvent():
        break;
    }
  }
  
  /// Add files to upload queue
  Future<void> addFiles() async {
    print('=== BatchUploadNotifier.addFiles() called ===');
    
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      allowMultiple: true,
      withData: true, // Include bytes for web compatibility
    );
    
    if (result != null && result.files.isNotEmpty) {
      print('FilePicker returned ${result.files.length} files');
      for (int i = 0; i < result.files.length; i++) {
        print('  File[$i]: ${result.files[i].name} (${result.files[i].size} bytes)');
      }
      _service.addPlatformFiles(result.files);
    } else {
      print('FilePicker returned no files or was cancelled');
    }
  }
  
  /// Pause all uploads
  void pause() {
    _service.pause();
  }
  
  /// Resume all uploads
  void resume() {
    _service.resume();
  }
  
  /// Cancel all uploads
  void cancel() {
    _service.cancel();
  }
  
  /// Retry failed uploads
  void retryFailed() {
    _service.retryFailed();
  }
  
  /// Clear completed uploads
  void clearCompleted() {
    _service.clearCompleted();
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    _service.dispose();
    super.dispose();
  }
}

/// Extension to add initial state
extension BatchUploadStateX on BatchUploadState {
  static BatchUploadState initial() {
    return BatchUploadState(
      queue: [],
      active: [],
      completed: [],
      isPaused: false,
      isCancelled: false,
      totalProgress: 0.0,
    );
  }
}

/// Selectors for optimized rebuilds
final uploadQueueProvider = Provider<List<UploadTask>>((ref) {
  return ref.watch(batchUploadStateProvider).queue;
});

final activeUploadsProvider = Provider<List<UploadTask>>((ref) {
  return ref.watch(batchUploadStateProvider).active;
});

final completedUploadsProvider = Provider<List<UploadTask>>((ref) {
  return ref.watch(batchUploadStateProvider).completed;
});

final totalProgressProvider = Provider<double>((ref) {
  return ref.watch(batchUploadStateProvider).totalProgress;
});

final isPausedProvider = Provider<bool>((ref) {
  return ref.watch(batchUploadStateProvider).isPaused;
});

final uploadStatsProvider = Provider<UploadStats>((ref) {
  final state = ref.watch(batchUploadStateProvider);
  return UploadStats(
    total: state.totalTasks,
    completed: state.completedTasks,
    failed: state.failedTasks,
    active: state.activeTasks,
    pending: state.pendingTasks,
  );
});

/// Upload statistics
class UploadStats {
  final int total;
  final int completed;
  final int failed;
  final int active;
  final int pending;
  
  UploadStats({
    required this.total,
    required this.completed,
    required this.failed,
    required this.active,
    required this.pending,
  });
  
  double get progress => total > 0 ? completed / total : 0.0;
  bool get isComplete => total > 0 && completed + failed == total;
  bool get hasActive => active > 0;
}
