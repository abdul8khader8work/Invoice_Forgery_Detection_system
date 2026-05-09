/// Scan response model for single invoice
class ScanResponse {
  final bool success;
  final String? fileId;
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
  final String? error;
  final List<Map<String, dynamic>>? lineItems;
  final String? paymentMethod;
  final String? vendorAddress;
  final String? vendorPhone;
  final int? validationScore;
  final double? mlScore;
  final List<String>? verificationFields;
  final String? timestamp;
  final String? aiReasoning;
  final List<String>? aiRiskFactors;
  final int? aiConfidence;

  ScanResponse({
    required this.success,
    this.fileId,
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
    this.error,
    this.lineItems,
    this.paymentMethod,
    this.vendorAddress,
    this.vendorPhone,
    this.validationScore,
    this.mlScore,
    this.verificationFields,
    this.timestamp,
    this.aiReasoning,
    this.aiRiskFactors,
    this.aiConfidence,
  });

  factory ScanResponse.fromJson(Map<String, dynamic> json) {
    return ScanResponse(
      success: json['success'] ?? false,
      fileId: json['file_id'] as String?,
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
      error: json['error'] as String?,
      lineItems: (json['line_items'] as List<dynamic>?)?.cast<Map<String, dynamic>>(),
      paymentMethod: json['payment_method'] as String?,
      vendorAddress: json['vendor_address'] as String?,
      vendorPhone: json['vendor_phone'] as String?,
      validationScore: json['validation_score'] as int?,
      mlScore: (json['ml_score'] as num?)?.toDouble(),
      verificationFields: (json['verification_fields'] as List<dynamic>?)?.cast<String>(),
      timestamp: json['timestamp'] as String?,
      aiReasoning: json['ai_reasoning'] as String?,
      aiRiskFactors: (json['ai_risk_factors'] as List<dynamic>?)?.cast<String>(),
      aiConfidence: json['ai_confidence'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'file_id': fileId,
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
      'error': error,
      'line_items': lineItems,
      'payment_method': paymentMethod,
      'vendor_address': vendorAddress,
      'vendor_phone': vendorPhone,
      'validation_score': validationScore,
      'ml_score': mlScore,
      'verification_fields': verificationFields,
      'timestamp': timestamp,
      'ai_reasoning': aiReasoning,
      'ai_risk_factors': aiRiskFactors,
      'ai_confidence': aiConfidence,
    };
  }

  ScanResponse copyWith({
    bool? success,
    String? fileId,
    String? filename,
    Map<String, dynamic>? extractedData,
    Map<String, dynamic>? deterministicValidation,
    Map<String, dynamic>? mlAnalysis,
    Map<String, dynamic>? xaiReport,
    double? riskScore,
    String? riskLevel,
    List<String>? reasoning,
    bool? needsVerification,
    double? processingTime,
    String? error,
    List<Map<String, dynamic>>? lineItems,
    String? paymentMethod,
    String? vendorAddress,
    String? vendorPhone,
    int? validationScore,
    double? mlScore,
    List<String>? verificationFields,
    String? timestamp,
  }) {
    return ScanResponse(
      success: success ?? this.success,
      fileId: fileId ?? this.fileId,
      filename: filename ?? this.filename,
      extractedData: extractedData ?? this.extractedData,
      deterministicValidation: deterministicValidation ?? this.deterministicValidation,
      mlAnalysis: mlAnalysis ?? this.mlAnalysis,
      xaiReport: xaiReport ?? this.xaiReport,
      riskScore: riskScore ?? this.riskScore,
      riskLevel: riskLevel ?? this.riskLevel,
      reasoning: reasoning ?? this.reasoning,
      needsVerification: needsVerification ?? this.needsVerification,
      processingTime: processingTime ?? this.processingTime,
      error: error ?? this.error,
      lineItems: lineItems ?? this.lineItems,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      vendorAddress: vendorAddress ?? this.vendorAddress,
      vendorPhone: vendorPhone ?? this.vendorPhone,
      validationScore: validationScore ?? this.validationScore,
      mlScore: mlScore ?? this.mlScore,
      verificationFields: verificationFields ?? this.verificationFields,
      timestamp: timestamp ?? this.timestamp,
      aiReasoning: aiReasoning ?? this.aiReasoning,
      aiRiskFactors: aiRiskFactors ?? this.aiRiskFactors,
      aiConfidence: aiConfidence ?? this.aiConfidence,
    );
  }
}
