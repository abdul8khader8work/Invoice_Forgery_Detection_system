/// Batch scan request model for multiple invoices
class BatchScanRequest {
  final List<String> files;

  BatchScanRequest({required this.files});

  Map<String, dynamic> toJson() {
    return {
      'files': files,
    };
  }
}
