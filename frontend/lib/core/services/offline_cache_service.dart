import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';

/// Offline cache service for local storage and sync
class OfflineCacheService {
  static const String _cachedScansKey = 'cached_scans';
  static const String _pendingUploadsKey = 'pending_uploads';
  static const String _lastSyncKey = 'last_sync_timestamp';
  
  SharedPreferences? _prefs;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isOnline = true;
  
  final StreamController<SyncEvent> _syncEventController = StreamController<SyncEvent>.broadcast();
  
  /// Stream of sync events
  Stream<SyncEvent> get syncEvents => _syncEventController.stream;
  
  /// Current online status
  bool get isOnline => _isOnline;
  
  /// Number of pending uploads
  int get pendingUploadCount => _getPendingUploads().length;
  
  /// Initialize the service
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Monitor connectivity
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      _isOnline = result != ConnectivityResult.none;
      _emitEvent(SyncEvent.connectivityChanged(_isOnline));
      
      if (_isOnline) {
        // Auto-sync when coming online
        syncPendingUploads();
      }
    });
    
    // Check initial connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    _isOnline = connectivityResult != ConnectivityResult.none;
  }
  
  /// Cache scan result locally
  Future<void> cacheScanResult(Map<String, dynamic> scanResult) async {
    final cachedScans = _getCachedScans();
    
    // Add timestamp to track when cached
    scanResult['cached_at'] = DateTime.now().toIso8601String();
    
    cachedScans.add(scanResult);
    
    await _prefs!.setString(_cachedScansKey, json.encode(cachedScans));
    _emitEvent(SyncEvent.scanCached(scanResult['id']));
  }
  
  /// Get all cached scan results
  List<Map<String, dynamic>> getCachedScans() {
    return _getCachedScans();
  }
  
  /// Get cached scan by ID
  Map<String, dynamic>? getCachedScanById(String scanId) {
    final cachedScans = _getCachedScans();
    try {
      return cachedScans.firstWhere((scan) => scan['id'] == scanId);
    } catch (e) {
      return null;
    }
  }
  
  /// Clear cached scan results
  Future<void> clearCachedScans() async {
    await _prefs!.remove(_cachedScansKey);
    _emitEvent(const SyncEvent.cacheCleared());
  }
  
  /// Add upload to pending queue
  Future<void> addPendingUpload(Map<String, dynamic> uploadData) async {
    final pendingUploads = _getPendingUploads();
    
    // Add timestamp and retry count
    uploadData['queued_at'] = DateTime.now().toIso8601String();
    uploadData['retry_count'] = 0;
    uploadData['status'] = 'pending';
    
    pendingUploads.add(uploadData);
    
    await _prefs!.setString(_pendingUploadsKey, json.encode(pendingUploads));
    _emitEvent(SyncEvent.uploadQueued(uploadData['id']));
    
    // Try to sync immediately if online
    if (_isOnline) {
      syncPendingUploads();
    }
  }
  
  /// Get pending uploads
  List<Map<String, dynamic>> _getPendingUploads() {
    final data = _prefs?.getString(_pendingUploadsKey);
    if (data == null) return [];
    
    try {
      final List<dynamic> decoded = json.decode(data);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }
  
  /// Get cached scans
  List<Map<String, dynamic>> _getCachedScans() {
    final data = _prefs?.getString(_cachedScansKey);
    if (data == null) return [];
    
    try {
      final List<dynamic> decoded = json.decode(data);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }
  
  /// Sync pending uploads with server
  Future<void> syncPendingUploads() async {
    if (!_isOnline) {
      _emitEvent(const SyncEvent.syncFailed('Offline'));
      return;
    }
    
    final pendingUploads = _getPendingUploads();
    if (pendingUploads.isEmpty) {
      _emitEvent(const SyncEvent.syncComplete(0));
      return;
    }
    
    _emitEvent(SyncEvent.syncStarted(pendingUploads.length));
    
    int successCount = 0;
    int failCount = 0;
    final updatedUploads = <Map<String, dynamic>>[];
    
    for (final upload in pendingUploads) {
      try {
        // TODO: Implement actual upload logic
        // This would call the backend API to upload the file
        
        // Simulate successful upload
        upload['status'] = 'completed';
        upload['synced_at'] = DateTime.now().toIso8601String();
        successCount++;
        
        _emitEvent(SyncEvent.uploadSynced(upload['id']));
      } catch (e) {
        upload['status'] = 'failed';
        upload['error'] = e.toString();
        upload['retry_count'] = (upload['retry_count'] ?? 0) + 1;
        failCount++;
        
        _emitEvent(SyncEvent.uploadFailed(upload['id'], e.toString()));
        
        // Keep failed uploads for retry (max 3 retries)
        if (upload['retry_count'] < 3) {
          updatedUploads.add(upload);
        }
      }
    }
    
    // Update pending uploads
    await _prefs!.setString(_pendingUploadsKey, json.encode(updatedUploads));
    
    // Update last sync timestamp
    await _prefs!.setString(_lastSyncKey, DateTime.now().toIso8601String());
    
    if (failCount == 0) {
      _emitEvent(SyncEvent.syncComplete(successCount));
    } else {
      _emitEvent(SyncEvent.syncPartial(successCount, failCount));
    }
  }
  
  /// Manual sync trigger
  Future<void> manualSync() async {
    await syncPendingUploads();
  }
  
  /// Get last sync timestamp
  DateTime? getLastSyncTimestamp() {
    final timestamp = _prefs?.getString(_lastSyncKey);
    if (timestamp == null) return null;
    
    try {
      return DateTime.parse(timestamp);
    } catch (e) {
      return null;
    }
  }
  
  /// Clear pending uploads
  Future<void> clearPendingUploads() async {
    await _prefs!.remove(_pendingUploadsKey);
    _emitEvent(const SyncEvent.queueCleared());
  }
  
  /// Retry failed uploads
  Future<void> retryFailedUploads() async {
    final pendingUploads = _getPendingUploads();
    final failedUploads = pendingUploads
        .where((upload) => upload['status'] == 'failed')
        .toList();
    
    for (final upload in failedUploads) {
      upload['status'] = 'pending';
      upload['retry_count'] = 0;
    }
    
    await _prefs!.setString(_pendingUploadsKey, json.encode(pendingUploads));
    
    if (_isOnline) {
      await syncPendingUploads();
    }
  }
  
  /// Get sync status
  SyncStatus getSyncStatus() {
    final pendingUploads = _getPendingUploads();
    final lastSync = getLastSyncTimestamp();
    
    return SyncStatus(
      isOnline: _isOnline,
      pendingCount: pendingUploads.length,
      lastSync: lastSync,
      hasCachedData: _getCachedScans().isNotEmpty,
    );
  }
  
  void _emitEvent(SyncEvent event) {
    _syncEventController.add(event);
  }
  
  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncEventController.close();
  }
}

/// Sync events
sealed class SyncEvent {
  const SyncEvent();
  
  const factory SyncEvent.connectivityChanged(bool isOnline) = ConnectivityChangedEvent;
  const factory SyncEvent.scanCached(String scanId) = ScanCachedEvent;
  const factory SyncEvent.uploadQueued(String uploadId) = UploadQueuedEvent;
  const factory SyncEvent.uploadSynced(String uploadId) = UploadSyncedEvent;
  const factory SyncEvent.uploadFailed(String uploadId, String error) = UploadFailedEvent;
  const factory SyncEvent.syncStarted(int totalCount) = SyncStartedEvent;
  const factory SyncEvent.syncComplete(int successCount) = SyncCompleteEvent;
  const factory SyncEvent.syncPartial(int successCount, int failCount) = SyncPartialEvent;
  const factory SyncEvent.syncFailed(String reason) = SyncFailedEvent;
  const factory SyncEvent.cacheCleared() = CacheClearedEvent;
  const factory SyncEvent.queueCleared() = QueueClearedEvent;
}

class ConnectivityChangedEvent extends SyncEvent {
  final bool isOnline;
  const ConnectivityChangedEvent(this.isOnline);
}

class ScanCachedEvent extends SyncEvent {
  final String scanId;
  const ScanCachedEvent(this.scanId);
}

class UploadQueuedEvent extends SyncEvent {
  final String uploadId;
  const UploadQueuedEvent(this.uploadId);
}

class UploadSyncedEvent extends SyncEvent {
  final String uploadId;
  const UploadSyncedEvent(this.uploadId);
}

class UploadFailedEvent extends SyncEvent {
  final String uploadId;
  final String error;
  const UploadFailedEvent(this.uploadId, this.error);
}

class SyncStartedEvent extends SyncEvent {
  final int totalCount;
  const SyncStartedEvent(this.totalCount);
}

class SyncCompleteEvent extends SyncEvent {
  final int successCount;
  const SyncCompleteEvent(this.successCount);
}

class SyncPartialEvent extends SyncEvent {
  final int successCount;
  final int failCount;
  const SyncPartialEvent(this.successCount, this.failCount);
}

class SyncFailedEvent extends SyncEvent {
  final String reason;
  const SyncFailedEvent(this.reason);
}

class CacheClearedEvent extends SyncEvent {
  const CacheClearedEvent();
}

class QueueClearedEvent extends SyncEvent {
  const QueueClearedEvent();
}

/// Sync status model
class SyncStatus {
  final bool isOnline;
  final int pendingCount;
  final DateTime? lastSync;
  final bool hasCachedData;
  
  SyncStatus({
    required this.isOnline,
    required this.pendingCount,
    this.lastSync,
    required this.hasCachedData,
  });
  
  /// Get status message for UI
  String getStatusMessage() {
    if (!isOnline) {
      return 'You are offline';
    }
    
    if (pendingCount > 0) {
      return '$pendingCount scans pending sync';
    }
    
    if (lastSync != null) {
      final timeSince = DateTime.now().difference(lastSync!);
      if (timeSince.inMinutes < 1) {
        return 'Synced just now';
      } else if (timeSince.inHours < 1) {
        return 'Synced ${timeSince.inMinutes}m ago';
      } else if (timeSince.inDays < 1) {
        return 'Synced ${timeSince.inHours}h ago';
      } else {
        return 'Synced ${timeSince.inDays}d ago';
      }
    }
    
    return 'All synced';
  }
}
