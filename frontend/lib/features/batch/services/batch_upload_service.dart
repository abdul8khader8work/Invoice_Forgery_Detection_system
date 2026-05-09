import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:invoice_forgery_detection/core/api/api_client.dart';
import 'package:invoice_forgery_detection/core/api/models/scan_request.dart';
import 'package:invoice_forgery_detection/core/api/models/scan_response.dart';
import 'package:invoice_forgery_detection/core/services/platform_file_upload_service.dart';
import 'package:invoice_forgery_detection/features/batch/models/batch_upload_result.dart';
import 'package:path/path.dart' as path;

/// Batch upload service with rate limiting and parallel upload support
class BatchUploadService {
  final InvoiceApiClient apiClient;
  final int maxConcurrentUploads;
  final int rateLimitDelayMs;
  
  final _uploadQueue = <UploadTask>[];
  final _activeUploads = <UploadTask>[];
  final _completedUploads = <UploadTask>[];
  
  Timer? _rateLimiterTimer;
  bool _isPaused = false;
  bool _isCancelled = false;
  
  StreamController<BatchUploadEvent>? _eventController;
  
  BatchUploadService({
    required this.apiClient,
    this.maxConcurrentUploads = 3,
    this.rateLimitDelayMs = 500,
  });
  
  Stream<BatchUploadEvent> get events {
    _eventController ??= StreamController<BatchUploadEvent>.broadcast();
    return _eventController!.stream;
  }

  void _log(String message) {
    if (kDebugMode) {
      print('[BatchUpload] $message');
    }
  }
  
  // ✅ HELPER: Check if file already exists in any queue (by name + size)
  bool _isFileAlreadyInQueue(String fileName, int fileSize) {
    return _uploadQueue.any((t) => t.fileName == fileName && _getFileSize(t) == fileSize) ||
           _activeUploads.any((t) => t.fileName == fileName && _getFileSize(t) == fileSize) ||
           _completedUploads.any((t) => t.fileName == fileName && _getFileSize(t) == fileSize);
  }

  // ✅ HELPER: Get file size from task
  int _getFileSize(UploadTask task) {
    return task.platformFile?.size ?? task.file?.lengthSync() ?? 0;
  }

  /// Add files to upload queue (desktop/mobile)
  void addFiles(List<File> files) {
    for (final file in files) {
      final fileName = file.path.split('/').last;
      final fileSize = file.lengthSync();
      
      // ✅ PREVENT DUPLICATES: Check if file already exists (by name + size)
      if (_isFileAlreadyInQueue(fileName, fileSize)) {
        _log('⚠️ Skipping duplicate file: $fileName (${fileSize} bytes)');
        continue;
      }
      
      final task = UploadTask(
        id: DateTime.now().millisecondsSinceEpoch.toString() + _uploadQueue.length.toString(),
        file: file,
        status: UploadStatus.pending,
        progress: 0.0,
      );
      _uploadQueue.add(task);
      _emitEvent(BatchUploadEvent.taskAdded(task));
      _log('✅ Added to queue: $fileName');
    }
    _processQueue();
  }

  /// Add PlatformFile objects to upload queue (web compatible)
  void addPlatformFiles(List<PlatformFile> platformFiles) {
    _log('=== addPlatformFiles called with ${platformFiles.length} files ===');
    
    for (int i = 0; i < platformFiles.length; i++) {
      final platformFile = platformFiles[i];
      final fileName = platformFile.name;
      final fileSize = platformFile.size;
      
      _log('Processing file [$i]: $fileName (${fileSize} bytes)');
      
      // ✅ PREVENT DUPLICATES: Use helper method (by name + size)
      if (_isFileAlreadyInQueue(fileName, fileSize)) {
        _log('⚠️ Skipping duplicate file: $fileName (${fileSize} bytes)');
        continue;
      }
      
      final task = UploadTask(
        id: DateTime.now().millisecondsSinceEpoch.toString() + _uploadQueue.length.toString(),
        platformFile: platformFile,
        status: UploadStatus.pending,
        progress: 0.0,
      );
      _uploadQueue.add(task);
      _emitEvent(BatchUploadEvent.taskAdded(task));
      _log('✅ Added to queue: $fileName');
    }
    _processQueue();
  }
  
  /// Process upload queue with rate limiting
  void _processQueue() {
    if (_isPaused || _isCancelled) return;
    
    while (_activeUploads.length < maxConcurrentUploads && _uploadQueue.isNotEmpty) {
      final task = _uploadQueue.removeAt(0);
      _activeUploads.add(task);
      _uploadTask(task);
    }
  }
  
  /// Upload single file
  Future<void> _uploadTask(UploadTask task) async {
    _log('Starting upload for: ${task.fileName}');
    
    if (_isCancelled) {
      task.status = UploadStatus.cancelled;
      _emitEvent(BatchUploadEvent.taskCancelled(task));
      _activeUploads.remove(task);
      _log('Upload cancelled for: ${task.fileName}');
      return;
    }
    
    if (_isPaused) {
      await Future.doWhile(() async {
        await Future.delayed(Duration(milliseconds: 100));
        return _isPaused;
      });
    }
    
    task.status = UploadStatus.uploading;
    _emitEvent(BatchUploadEvent.taskProgress(task));
    _log('Uploading: ${task.fileName}');
    
    try {
      // Convert file to MultipartFile using the existing service
      final multipartFile = await PlatformFileUploadService.toMultipartFile(
        task.platformFile ?? (task.file?.path ?? ''),
        'file',
      );
      
      _log('MultipartFile created for: ${task.fileName}');
      
      final response = await apiClient.scanInvoice(
        ScanRequest(file: multipartFile),
      );
      
      _log('Response received for: ${task.fileName}, success: ${response.success}');
      
      task.status = UploadStatus.processing;
      _emitEvent(BatchUploadEvent.taskProgress(task));
      
      if (response.success) {
        task.status = UploadStatus.completed;
        task.progress = 1.0;
        task.response = json.encode(response.toJson());

        // Parse the response data into BatchUploadResult
        try {
          final responseMap = response.toJson() as Map<String, dynamic>;
          
          final resultData = <String, dynamic>{
            'file_id': responseMap['file_id'] ?? '',
            'filename': responseMap['filename'] ?? '',
            'extracted_data': responseMap['extracted_data'] ?? {},
            'deterministic_validation': responseMap['deterministic_validation'] ?? {},
            'ml_analysis': responseMap['ml_analysis'] ?? {},
            'risk_score': responseMap['risk_score'] ?? 0.0,
            'risk_level': responseMap['risk_level'] ?? 'low',
            'reasoning': responseMap['reasoning'] ?? [],
            'needs_verification': responseMap['needs_verification'] ?? false,
            'verification_fields': responseMap['verification_fields'] ?? [],
          };
          
          task.result = BatchUploadResult.fromJson(resultData);
          _log('Batch upload result parsed for: ${task.fileName}');
        } catch (e) {
          _log('Error parsing result for ${task.fileName}: $e');
          // Create a basic result even if parsing fails
          task.result = BatchUploadResult(
            fileId: response.toJson()['file_id']?.toString() ?? '',
            filename: task.fileName,
            extractedData: ExtractedData.fromJson({}),
            deterministicValidation: DeterministicValidation.fromJson({}),
            mlAnalysis: MlAnalysis.fromJson({}),
            riskScore: 0.0,
            riskLevel: 'low',
            reasoning: [],
            needsVerification: false,
            verificationFields: [],
            timestamp: DateTime.now().toIso8601String(),
            processingTime: 0.0,
          );
        }
        
        _completedUploads.add(task);
        _emitEvent(BatchUploadEvent.taskCompleted(task));
      } else {
        throw Exception(response.error ?? 'Upload failed');
      }
    } catch (e) {
      task.status = UploadStatus.failed;
      _log('Upload exception for: ${task.fileName}, error: ${e.toString()}');
      // Provide more meaningful error message
      String errorMessage = 'Upload failed';
      if (e.toString().contains('database_save_failed')) {
        errorMessage = 'Processing succeeded but database save failed. Contact administrator.';
      } else if (e.toString().contains('Network error')) {
        errorMessage = 'Network error: Could not connect to server';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Upload timed out. Please try again.';
      } else {
        errorMessage = 'Upload failed: ${e.toString()}';
      }
      task.error = errorMessage;
      _emitEvent(BatchUploadEvent.taskFailed(task));
    } finally {
      _activeUploads.remove(task);
      _completedUploads.add(task);
      
      // Rate limiting
      await Future.delayed(Duration(milliseconds: rateLimitDelayMs));
      _processQueue();
    }
  }
  
  /// Pause all uploads
  void pause() {
    _isPaused = true;
    _emitEvent(const BatchUploadEvent.paused());
  }
  
  /// Resume all uploads
  void resume() {
    _isPaused = false;
    _emitEvent(const BatchUploadEvent.resumed());
    _processQueue();
  }
  
  /// Cancel all uploads
  void cancel() {
    _isCancelled = true;
    _isPaused = false;
    
    for (final task in _activeUploads) {
      task.status = UploadStatus.cancelled;
      _emitEvent(BatchUploadEvent.taskCancelled(task));
    }
    
    _activeUploads.clear();
    _uploadQueue.clear();
    _emitEvent(const BatchUploadEvent.cancelled());
  }
  
  /// Retry failed uploads
  void retryFailed() {
    final failedTasks = _completedUploads
        .where((t) => t.status == UploadStatus.failed)
        .toList();
    
    _completedUploads.removeWhere((t) => t.status == UploadStatus.failed);
    
    for (final task in failedTasks) {
      task.status = UploadStatus.pending;
      task.progress = 0.0;
      task.error = null;
      _uploadQueue.add(task);
    }
    
    _isCancelled = false;
    _processQueue();
  }
  
  /// Clear completed uploads
  void clearCompleted() {
    _completedUploads.clear();
    _emitEvent(const BatchUploadEvent.cleared());
  }
  
  /// Get current queue state
  BatchUploadState getState() {
    return BatchUploadState(
      queue: List.unmodifiable(_uploadQueue),
      active: List.unmodifiable(_activeUploads),
      completed: List.unmodifiable(_completedUploads),
      isPaused: _isPaused,
      isCancelled: _isCancelled,
      totalProgress: _calculateTotalProgress(),
    );
  }
  
  double _calculateTotalProgress() {
    final allTasks = [..._uploadQueue, ..._activeUploads, ..._completedUploads];
    if (allTasks.isEmpty) return 0.0;
    
    final totalProgress = allTasks.fold<double>(
      0.0,
      (sum, task) => sum + task.progress,
    );
    
    return totalProgress / allTasks.length;
  }
  
  void _emitEvent(BatchUploadEvent event) {
    _eventController?.add(event);
  }
  
  void dispose() {
    cancel();
    _eventController?.close();
  }
}

/// Upload task model
class UploadTask {
  final String id;
  final File? file;
  final PlatformFile? platformFile;
  UploadStatus status;
  double progress;
  String? error;
  String? response;
  BatchUploadResult? result;
  
  UploadTask({
    required this.id,
    this.file,
    this.platformFile,
    required this.status,
    this.progress = 0.0,
    this.error,
    this.response,
    this.result,
  }) : assert(file != null || platformFile != null, 'Either file or platformFile must be provided');
  
  UploadTask copyWith({
    UploadStatus? status,
    double? progress,
    String? error,
    String? response,
    BatchUploadResult? result,
  }) {
    return UploadTask(
      id: id,
      file: file,
      platformFile: platformFile,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      response: response ?? this.response,
      result: result ?? this.result,
    );
  }

  String get fileName {
    return platformFile?.name ?? file?.path.split('/').last ?? 'Unknown';
  }
}

/// Upload status enum
enum UploadStatus {
  pending,
  uploading,
  processing,
  completed,
  failed,
  cancelled,
}

/// Batch upload state
class BatchUploadState {
  final List<UploadTask> queue;
  final List<UploadTask> active;
  final List<UploadTask> completed;
  final bool isPaused;
  final bool isCancelled;
  final double totalProgress;
  
  BatchUploadState({
    required this.queue,
    required this.active,
    required this.completed,
    required this.isPaused,
    required this.isCancelled,
    required this.totalProgress,
  });
  
  int get totalTasks => queue.length + active.length + completed.length;
  int get completedTasks => completed.where((t) => t.status == UploadStatus.completed).length;
  int get failedTasks => completed.where((t) => t.status == UploadStatus.failed).length;
  int get activeTasks => active.length;
  int get pendingTasks => queue.length;
}

/// Batch upload events
sealed class BatchUploadEvent {
  const BatchUploadEvent();
  
  const factory BatchUploadEvent.taskAdded(UploadTask task) = TaskAddedEvent;
  const factory BatchUploadEvent.taskProgress(UploadTask task) = TaskProgressEvent;
  const factory BatchUploadEvent.taskCompleted(UploadTask task) = TaskCompletedEvent;
  const factory BatchUploadEvent.taskFailed(UploadTask task) = TaskFailedEvent;
  const factory BatchUploadEvent.taskCancelled(UploadTask task) = TaskCancelledEvent;
  const factory BatchUploadEvent.paused() = PausedEvent;
  const factory BatchUploadEvent.resumed() = ResumedEvent;
  const factory BatchUploadEvent.cancelled() = CancelledEvent;
  const factory BatchUploadEvent.cleared() = ClearedEvent;
}

class TaskAddedEvent extends BatchUploadEvent {
  final UploadTask task;
  const TaskAddedEvent(this.task);
}

class TaskProgressEvent extends BatchUploadEvent {
  final UploadTask task;
  const TaskProgressEvent(this.task);
}

class TaskCompletedEvent extends BatchUploadEvent {
  final UploadTask task;
  const TaskCompletedEvent(this.task);
}

class TaskFailedEvent extends BatchUploadEvent {
  final UploadTask task;
  const TaskFailedEvent(this.task);
}

class TaskCancelledEvent extends BatchUploadEvent {
  final UploadTask task;
  const TaskCancelledEvent(this.task);
}

class PausedEvent extends BatchUploadEvent {
  const PausedEvent();
}

class ResumedEvent extends BatchUploadEvent {
  const ResumedEvent();
}

class CancelledEvent extends BatchUploadEvent {
  const CancelledEvent();
}

class ClearedEvent extends BatchUploadEvent {
  const ClearedEvent();
}
