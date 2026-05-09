import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../providers/batch_upload_provider.dart';
import '../widgets/upload_queue_item.dart';
import '../services/batch_upload_service.dart';
import '../../../core/services/analytics_refresh_service.dart';
import '../../../layouts/main_layout.dart';

/// Batch upload screen with queue management
class BatchUploadScreen extends ConsumerStatefulWidget {
  const BatchUploadScreen({super.key});

  @override
  ConsumerState<BatchUploadScreen> createState() => _BatchUploadScreenState();
}

class _BatchUploadScreenState extends ConsumerState<BatchUploadScreen> {
  bool _isDragging = false;
  bool _isGeneratingReport = false;
  bool _reportGenerated = false;
  bool _batchCompletionTriggered = false;
  String? _reportId;
  String? _reportUrl;
  
  // ✅ RACE CONDITION FIX: Track last counts to prevent duplicate triggers
  int _lastCompletedCount = 0;
  int _lastTotalTasks = 0;
  
  // ✅ DEBOUNCE FIX: Prevent multiple rapid completion checks
  Timer? _completionDebounce;

  Future<void> _pickFiles() async {
    // Reset batch completion flag for new batch
    _batchCompletionTriggered = false;
    // Provider handles file picking internally
    await ref.read(batchUploadStateProvider.notifier).addFiles();
  }

  Future<void> _generateConsolidatedReport() async {
    print('=== _generateConsolidatedReport called ===');
    if (_isGeneratingReport) return; // Prevent duplicate clicks

    setState(() {
      _isGeneratingReport = true;
    });

    try {
      final state = ref.read(batchUploadStateProvider);
      print('State total tasks: ${state.totalTasks}');
      print('State completed count: ${state.completed.length}');
      
      final batchId = DateTime.now().millisecondsSinceEpoch.toString();
      final invoiceIds = state.completed
          .where((task) => task.result != null && task.result!.fileId.isNotEmpty)
          .map((task) => task.result!.fileId)
          .toList();

      print('Invoice IDs found: $invoiceIds');
      print('Completed tasks with results: ${state.completed.where((t) => t.result != null).length}');

      if (invoiceIds.isNotEmpty) {
        setState(() {
          _reportId = batchId;
          _reportUrl = '/batch/$batchId/report';
        });

        print('Navigating to: /batch/$batchId/report');
        print('With invoice IDs: $invoiceIds');

        // Navigate to report screen
        if (mounted) {
          await context.push(
            '/batch/$batchId/report',
            extra: invoiceIds,
          );

          setState(() {
            _reportGenerated = true;
          });
          print('Navigation completed');
        }
      } else {
        print('No invoice IDs found - cannot generate report');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No completed scans to generate report from'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print('Error in _generateConsolidatedReport: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingReport = false;
        });
      }
    }
  }

  void _checkBatchCompletion() {
    // ✅ DEBOUNCE FIX: Cancel previous check
    _completionDebounce?.cancel();
    
    _completionDebounce = Timer(const Duration(milliseconds: 500), () {
      final state = ref.read(batchUploadStateProvider);
      final totalTasks = state.totalTasks;
      final completedTasks = state.completed.length;

      print('=== _checkBatchCompletion ===');
      print('Total tasks: $totalTasks');
      print('Completed tasks: $completedTasks');
      print('Last total: $_lastTotalTasks, Last completed: $_lastCompletedCount');
      
      // ✅ RACE CONDITION FIX: Only trigger if counts changed
      if (totalTasks > 0 && 
          completedTasks == totalTasks && 
          (completedTasks != _lastCompletedCount || totalTasks != _lastTotalTasks) &&
          !_reportGenerated && 
          !_batchCompletionTriggered) {
        
        // Update tracked counts BEFORE triggering
        _lastCompletedCount = completedTasks;
        _lastTotalTasks = totalTasks;
        _batchCompletionTriggered = true;
        
        AnalyticsRefreshService().triggerRefresh();
        print('🔄 Analytics refresh triggered after batch completion');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(batchUploadStateProvider);
    final stats = ref.watch(uploadStatsProvider);
    final isPaused = ref.watch(isPausedProvider);

    // Check for batch completion to auto-trigger report generation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBatchCompletion();
    });
    
    return MainLayout(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          if (stats.hasActive || stats.failed > 0 || stats.completed > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (stats.hasActive)
                    IconButton(
                      icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                      onPressed: () {
                        if (isPaused) {
                          ref.read(batchUploadStateProvider.notifier).resume();
                        } else {
                          ref.read(batchUploadStateProvider.notifier).pause();
                        }
                      },
                      tooltip: isPaused ? 'Resume' : 'Pause',
                    ),
                  if (stats.failed > 0)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () {
                        ref.read(batchUploadStateProvider.notifier).retryFailed();
                      },
                      tooltip: 'Retry Failed',
                    ),
                  if (stats.completed > 0)
                    IconButton(
                      icon: const Icon(Icons.clear_all),
                      onPressed: () {
                        ref.read(batchUploadStateProvider.notifier).clearCompleted();
                      },
                      tooltip: 'Clear Completed',
                    ),
                ],
              ),
            ),
          SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Batch Upload',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Upload multiple invoices for batch processing',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  SizedBox(height: 32),
                  _buildStatsCard(context, stats, state.totalProgress),
                  SizedBox(height: 32),
                  _buildDragDropZone(context, ref),
                  SizedBox(height: 32),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,  // 60% of screen
                    ),
                    child: _buildQueueList(state, ref),
                  ),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }
  
  Widget _buildStatsCard(BuildContext context, UploadStats stats, double totalProgress) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Upload Progress',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${stats.completed}/${stats.total}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: stats.progress,
                  backgroundColor: Colors.grey[700],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(context, 'Pending', stats.pending, Colors.grey),
                    _buildStatItem(context, 'Active', stats.active, Colors.blue),
                    _buildStatItem(context, 'Completed', stats.completed, Colors.green),
                    _buildStatItem(context, 'Failed', stats.failed, Colors.red),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatItem(BuildContext context, String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }
  
  Widget _buildDragDropZone(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Add Files',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(24),
            child: GestureDetector(
              onTap: _pickFiles,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isDragging ? Colors.blue : Colors.white10,
                    width: _isDragging ? 3 : 2,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: _isDragging ? Color(0xFF2A2A4E) : Color(0xFF16213E),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 48,
                        color: _isDragging ? Colors.blue : Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Drag & drop files here',
                        style: TextStyle(
                          color: _isDragging ? Colors.blue : Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'or click anywhere here',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQueueList(BatchUploadState state, WidgetRef ref) {
    if (state.totalTasks == 0) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Upload Queue',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Divider(height: 1),
            Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox,
                      size: 64,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No files in queue',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Upload Queue',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                if (state.queue.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Pending',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                  ...state.queue.map((task) => UploadQueueItem(task: task)),
                ],
                if (state.active.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Active',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  ...state.active.map((task) => UploadQueueItem(task: task)),
                ],
                if (state.completed.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Completed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  ...state.completed.map((task) => UploadQueueItem(
                        task: task,
                        onRetry: task.status == UploadStatus.failed
                            ? () => ref.read(batchUploadStateProvider.notifier).retryFailed()
                            : null,
                        onViewReport: () => _viewIndividualReport(task),
                      )),
                  // Generate Report button when all uploads complete
                  if (state.totalTasks > 0 && state.completed.length == state.totalTasks)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: _isGeneratingReport
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf),
                          label: Text(_isGeneratingReport ? 'Generating...' : 'Generate Consolidated Report'),
                          onPressed: _isGeneratingReport ? null : _generateConsolidatedReport,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Report generated success indicator
                  if (_reportGenerated)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFF16213E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[400]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[400]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Report Generated Successfully',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                if (_reportId != null)
                                  Text(
                                    'Report ID: $_reportId',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                                  ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              if (_reportUrl != null) {
                                context.push(_reportUrl!, extra: []);
                              }
                            },
                            icon: const Icon(Icons.visibility),
                            label: const Text('View'),
                          ),
                        ],
                      ),
                    ),
                ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _viewIndividualReport(UploadTask task) {
    if (task.result != null) {
      context.push('/scan/result', extra: task.result);
    }
  }

  @override
  void dispose() {
    _completionDebounce?.cancel();
    super.dispose();
  }
}
