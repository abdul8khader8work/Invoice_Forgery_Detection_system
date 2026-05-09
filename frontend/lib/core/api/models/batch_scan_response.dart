/// Batch scan response model for multiple invoices
class BatchScanResponse {
  final bool success;
  final int totalFiles;
  final int processed;
  final int failed;
  final List<BatchScanResult> results;
  final List<BatchScanError> errors;
  final String? message;

  BatchScanResponse({
    required this.success,
    required this.totalFiles,
    required this.processed,
    required this.failed,
    required this.results,
    required this.errors,
    this.message,
  });

  factory BatchScanResponse.fromJson(Map<String, dynamic> json) {
    return BatchScanResponse(
      success: json['success'] ?? false,
      totalFiles: json['total_files'] ?? 0,
      processed: json['processed'] ?? 0,
      failed: json['failed'] ?? 0,
      results: (json['results'] as List<dynamic>?)
              ?.map((e) => BatchScanResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => BatchScanError.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'total_files': totalFiles,
      'processed': processed,
      'failed': failed,
      'results': results.map((e) => e.toJson()).toList(),
      'errors': errors.map((e) => e.toJson()).toList(),
      'message': message,
    };
  }
}

class BatchScanResult {
  final String? filename;
  final Map<String, dynamic>? extractedData;
  final Map<String, dynamic>? deterministicValidation;
  final Map<String, dynamic>? mlAnalysis;
  final Map<String, dynamic>? xaiReport;
  final double? riskScore;
  final String? riskLevel;
  final List<String>? reasoning;
  final bool? needsVerification;
  final double? processingTime;

  BatchScanResult({
    this.filename,
    this.extractedData,
    this.deterministicValidation,
    this.mlAnalysis,
    this.xaiReport,
    this.riskScore,
    this.riskLevel,
    this.reasoning,
    this.needsVerification,
    this.processingTime,
  });

  factory BatchScanResult.fromJson(Map<String, dynamic> json) {
    return BatchScanResult(
      filename: json['filename'] as String?,
      extractedData: json['extracted_data'] as Map<String, dynamic>?,
      deterministicValidation: json['deterministic_validation'] as Map<String, dynamic>?,
      mlAnalysis: json['ml_analysis'] as Map<String, dynamic>?,
      xaiReport: json['xai_report'] as Map<String, dynamic>?,
      riskScore: (json['risk_score'] as num?)?.toDouble(),
      riskLevel: json['risk_level'] as String?,
      reasoning: (json['reasoning'] as List<dynamic>?)?.cast<String>(),
      needsVerification: json['needs_verification'] as bool?,
      processingTime: (json['processing_time'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'extracted_data': extractedData,
      'deterministic_validation': deterministicValidation,
      'ml_analysis': mlAnalysis,
      'xai_report': xaiReport,
      'risk_score': riskScore,
      'risk_level': riskLevel,
      'reasoning': reasoning,
      'needs_verification': needsVerification,
      'processing_time': processingTime,
    };
  }
}

class BatchScanError {
  final String? filename;
  final String? error;

  BatchScanError({
    this.filename,
    this.error,
  });

  factory BatchScanError.fromJson(Map<String, dynamic> json) {
    return BatchScanError(
      filename: json['filename'] as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'error': error,
    };
  }
}
