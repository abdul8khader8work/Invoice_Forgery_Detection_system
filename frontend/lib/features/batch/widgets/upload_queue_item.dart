import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/batch_upload_result.dart';
import '../services/batch_upload_service.dart';
import '../../../core/api/models/scan_response.dart';
import '../../scan/screens/scan_result_screen.dart';

/// Widget for displaying a single upload queue item
class UploadQueueItem extends StatelessWidget {
  final UploadTask task;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final VoidCallback? onViewReport;
  
  const UploadQueueItem({
    super.key,
    required this.task,
    this.onRetry,
    this.onCancel,
    this.onViewReport,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _buildStatusText(),
                    ],
                  ),
                ),
                if (task.status == UploadStatus.failed && onRetry != null)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: onRetry,
                    tooltip: 'Retry',
                  ),
                if (task.status == UploadStatus.pending || task.status == UploadStatus.uploading)
                  IconButton(
                    icon: const Icon(Icons.cancel),
                    onPressed: onCancel,
                    tooltip: 'Cancel',
                  ),
                if (task.status == UploadStatus.completed && task.result != null)
                  IconButton(
                    icon: const Icon(Icons.visibility),
                    onPressed: () => _navigateToScanResultScreen(context, task.result!),
                    tooltip: 'View Report',
                  ),
              ],
            ),
            if (task.status == UploadStatus.uploading || task.status == UploadStatus.processing)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getStatusColor(task.status),
                  ),
                ),
              ),
            if (task.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  task.error!,
                  style: TextStyle(
                    color: Colors.red[700],
                    fontSize: 12,
                  ),
                ),
              ),
            if (task.status == UploadStatus.completed && task.result != null)
              _buildResultsSection(context),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusIcon() {
    IconData icon;
    Color color;
    
    switch (task.status) {
      case UploadStatus.pending:
        icon = Icons.schedule;
        color = Colors.grey;
        break;
      case UploadStatus.uploading:
      case UploadStatus.processing:
        icon = Icons.cloud_upload;
        color = Colors.blue;
        break;
      case UploadStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case UploadStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
      case UploadStatus.cancelled:
        icon = Icons.cancel;
        color = Colors.grey;
        break;
    }
    
    return Icon(icon, color: color, size: 24);
  }
  
  Widget _buildStatusText() {
    String text;
    Color color;
    
    switch (task.status) {
      case UploadStatus.pending:
        text = 'Pending';
        color = Colors.grey[600]!;
        break;
      case UploadStatus.uploading:
        text = 'Uploading... ${(task.progress * 100).toStringAsFixed(0)}%';
        color = Colors.blue[700]!;
        break;
      case UploadStatus.processing:
        text = 'Processing...';
        color = Colors.blue[700]!;
        break;
      case UploadStatus.completed:
        text = 'Completed';
        color = Colors.green[700]!;
        break;
      case UploadStatus.failed:
        text = 'Failed';
        color = Colors.red[700]!;
        break;
      case UploadStatus.cancelled:
        text = 'Cancelled';
        color = Colors.grey[600]!;
        break;
    }
    
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
      ),
    );
  }
  
  Color _getStatusColor(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return Colors.grey;
      case UploadStatus.uploading:
      case UploadStatus.processing:
        return Colors.blue;
      case UploadStatus.completed:
        return Colors.green;
      case UploadStatus.failed:
        return Colors.red;
      case UploadStatus.cancelled:
        return Colors.grey;
    }
  }

  Widget _buildResultsSection(BuildContext context) {
    final result = task.result!;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Risk summary row
          Row(
            children: [
              Icon(
                _getRiskIcon(result.riskLevel),
                color: _getRiskColor(result.riskLevel),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Risk: ${result.riskLevel.toUpperCase()}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _getRiskColor(result.riskLevel),
                ),
              ),
              const Spacer(),
              Text(
                'Score: ${result.riskScore.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Key extracted data
          if (result.extractedData.vendorName != null)
            _buildDataRow('Vendor', result.extractedData.vendorName!),
          if (result.extractedData.invoiceNumber != null)
            _buildDataRow('Invoice #', result.extractedData.invoiceNumber!),
          if (result.extractedData.total != null)
            _buildDataRow('Total', '\$${result.extractedData.total}'),
          // Validation status
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                result.deterministicValidation.passed
                    ? Icons.check_circle
                    : Icons.warning,
                color: result.deterministicValidation.passed
                    ? Colors.green
                    : Colors.orange,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                result.deterministicValidation.passed
                    ? 'Validation Passed'
                    : '${result.deterministicValidation.issueCount} validation issues',
                style: TextStyle(
                  color: result.deterministicValidation.passed
                      ? Colors.green[700]
                      : Colors.orange[700],
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // View full report button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _navigateToScanResultScreen(context, result),
              icon: const Icon(Icons.description, size: 16),
              label: const Text('View Full Report'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getRiskIcon(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return Icons.warning;
      case 'medium':
        return Icons.info;
      case 'low':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  ScanResponse _convertToScanResponse(BatchUploadResult result) {
    return ScanResponse(
      success: true,
      fileId: result.fileId,
      filename: result.filename,
      extractedData: result.extractedData.toJson(),
      deterministicValidation: result.deterministicValidation.toJson(),
      mlAnalysis: result.mlAnalysis.toJson(),
      riskScore: result.riskScore,
      riskLevel: result.riskLevel,
      reasoning: result.reasoning,
      needsVerification: result.needsVerification,
      processingTime: result.processingTime,
      timestamp: result.timestamp,
      verificationFields: result.verificationFields,
      lineItems: result.extractedData.lineItems.map((item) => item.toJson()).toList(),
    );
  }

  void _navigateToScanResultScreen(BuildContext context, BatchUploadResult result) {
    final scanResponse = _convertToScanResponse(result);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanResultScreen(result: scanResponse),
      ),
    );
  }
}
