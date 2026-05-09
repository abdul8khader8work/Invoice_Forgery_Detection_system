/// Validation warning model for individual warnings
class ValidationWarning {
  final String type;
  final String severity;
  final String message;
  final double? expected;
  final double? found;

  ValidationWarning({
    required this.type,
    required this.severity,
    required this.message,
    this.expected,
    this.found,
  });

  factory ValidationWarning.fromJson(Map<String, dynamic> json) {
    return ValidationWarning(
      type: json['type'] as String? ?? '',
      severity: json['severity'] as String? ?? 'low',
      message: json['message'] as String? ?? '',
      expected: (json['expected'] as num?)?.toDouble(),
      found: (json['found'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'severity': severity,
      'message': message,
      if (expected != null) 'expected': expected,
      if (found != null) 'found': found,
    };
  }
}

/// Batch upload result model containing complete analysis data
class BatchUploadResult {
  final String fileId;
  final String filename;
  final ExtractedData extractedData;
  final DeterministicValidation deterministicValidation;
  final MlAnalysis mlAnalysis;
  final double riskScore;
  final String riskLevel;
  final List<String> reasoning;
  final bool needsVerification;
  final List<String> verificationFields;
  final String timestamp;
  final double processingTime;

  BatchUploadResult({
    required this.fileId,
    required this.filename,
    required this.extractedData,
    required this.deterministicValidation,
    required this.mlAnalysis,
    required this.riskScore,
    required this.riskLevel,
    required this.reasoning,
    required this.needsVerification,
    required this.verificationFields,
    required this.timestamp,
    required this.processingTime,
  });

  factory BatchUploadResult.fromJson(Map<String, dynamic> json) {
    return BatchUploadResult(
      fileId: json['file_id'] ?? '',
      filename: json['filename'] ?? '',
      extractedData: ExtractedData.fromJson(json['extracted_data'] ?? {}),
      deterministicValidation: DeterministicValidation.fromJson(
        json['deterministic_validation'] ?? {},
      ),
      mlAnalysis: MlAnalysis.fromJson(json['ml_analysis'] ?? {}),
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      riskLevel: json['risk_level'] ?? 'low',
      reasoning: List<String>.from(json['reasoning'] ?? []),
      needsVerification: json['needs_verification'] ?? false,
      verificationFields: List<String>.from(json['verification_fields'] ?? []),
      timestamp: json['timestamp'] ?? '',
      processingTime: (json['processing_time'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_id': fileId,
      'filename': filename,
      'extracted_data': extractedData.toJson(),
      'deterministic_validation': deterministicValidation.toJson(),
      'ml_analysis': mlAnalysis.toJson(),
      'risk_score': riskScore,
      'risk_level': riskLevel,
      'reasoning': reasoning,
      'needs_verification': needsVerification,
      'verification_fields': verificationFields,
      'timestamp': timestamp,
      'processing_time': processingTime,
    };
  }
}

/// Extracted invoice data from LLM/OCR
class ExtractedData {
  final String? vendorName;
  final String? invoiceNumber;
  final String? invoiceDate;
  final double? subtotal;
  final double? tax;
  final double? total;
  final String? currency;
  final List<LineItem> lineItems;
  final String? buyerName;
  final String? paymentTerms;
  final String? notes;
  final List<String> missingFields;
  final Map<String, double> confidenceScores;
  final List<dynamic> structuredFields;
  final bool requiresManualCheck;
  final String? extractionMethod;
  final List<ValidationWarning> validationWarnings;

  ExtractedData({
    this.vendorName,
    this.invoiceNumber,
    this.invoiceDate,
    this.subtotal,
    this.tax,
    this.total,
    this.currency,
    this.lineItems = const [],
    this.buyerName,
    this.paymentTerms,
    this.notes,
    this.missingFields = const [],
    this.confidenceScores = const {},
    this.structuredFields = const [],
    this.requiresManualCheck = false,
    this.extractionMethod,
    this.validationWarnings = const [],
  });

  factory ExtractedData.fromJson(Map<String, dynamic> json) {
    return ExtractedData(
      vendorName: json['vendor_name'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      invoiceDate: json['invoice_date'] as String?,
      subtotal: (json['subtotal'] as num?)?.toDouble(),
      tax: (json['tax'] as num?)?.toDouble(),
      total: (json['total'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      lineItems: (json['line_items'] as List<dynamic>?)
          ?.map((item) => LineItem.fromJson(item as Map<String, dynamic>))
          .toList() ?? [],
      buyerName: json['buyer_name'] as String?,
      paymentTerms: json['payment_terms'] as String?,
      notes: json['notes'] as String?,
      missingFields: List<String>.from(json['missing_fields'] ?? []),
      confidenceScores: Map<String, double>.from(
        json['confidence_scores']?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {},
      ),
      structuredFields: json['structured_fields'] as List<dynamic>? ?? [],
      requiresManualCheck: json['requires_manual_check'] ?? false,
      extractionMethod: json['extraction_method'] as String?,
      validationWarnings: (json['validation_warnings'] as List<dynamic>?)
          ?.map((item) => ValidationWarning.fromJson(item as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vendor_name': vendorName,
      'invoice_number': invoiceNumber,
      'invoice_date': invoiceDate,
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'currency': currency,
      'line_items': lineItems.map((item) => item.toJson()).toList(),
      'buyer_name': buyerName,
      'payment_terms': paymentTerms,
      'notes': notes,
      'missing_fields': missingFields,
      'confidence_scores': confidenceScores,
      'structured_fields': structuredFields,
      'requires_manual_check': requiresManualCheck,
      'extraction_method': extractionMethod,
      'validation_warnings': validationWarnings.map((w) => w.toJson()).toList(),
    };
  }
}

/// Line item from invoice
class LineItem {
  final String? description;
  final double? quantity;
  final double? unitPrice;
  final double? total;

  LineItem({
    this.description,
    this.quantity,
    this.unitPrice,
    this.total,
  });

  factory LineItem.fromJson(Map<String, dynamic> json) {
    return LineItem(
      description: json['description'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble(),
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      total: (json['total'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total': total,
    };
  }
}

/// Deterministic validation results (math, date, tax checks)
class DeterministicValidation {
  final bool passed;
  final double riskScore;
  final Map<String, ValidationCheck> checks;
  final String? overallReason;
  final int issueCount;
  final List<String> reasons;

  DeterministicValidation({
    this.passed = true,
    this.riskScore = 0.0,
    this.checks = const {},
    this.overallReason,
    this.issueCount = 0,
    this.reasons = const [],
  });

  factory DeterministicValidation.fromJson(Map<String, dynamic> json) {
    final checksMap = <String, ValidationCheck>{};
    if (json['checks'] != null) {
      (json['checks'] as Map<String, dynamic>).forEach((key, value) {
        checksMap[key] = ValidationCheck.fromJson(value as Map<String, dynamic>);
      });
    }

    return DeterministicValidation(
      passed: json['passed'] ?? true,
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      checks: checksMap,
      overallReason: json['overall_reason'] as String?,
      issueCount: json['issue_count'] ?? 0,
      reasons: List<String>.from(json['reasons'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'passed': passed,
      'risk_score': riskScore,
      'checks': checks.map((k, v) => MapEntry(k, v.toJson())),
      'overall_reason': overallReason,
      'issue_count': issueCount,
      'reasons': reasons,
    };
  }
}

/// Individual validation check result
class ValidationCheck {
  final bool passed;
  final String? reason;
  final Map<String, dynamic>? details;

  ValidationCheck({
    this.passed = true,
    this.reason,
    this.details,
  });

  factory ValidationCheck.fromJson(Map<String, dynamic> json) {
    return ValidationCheck(
      passed: json['passed'] ?? true,
      reason: json['reason'] as String?,
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'passed': passed,
      'reason': reason,
      'details': details,
    };
  }
}

/// ML analysis results for anomaly detection
class MlAnalysis {
  final double anomalyScore;
  final bool isAnomaly;
  final String? anomalyReason;
  final double? confidence;
  final Map<String, double> featureScores;
  final Map<String, double> featuresUsed;
  final String? modelVersion;

  MlAnalysis({
    this.anomalyScore = 0.0,
    this.isAnomaly = false,
    this.anomalyReason,
    this.confidence,
    this.featureScores = const {},
    this.featuresUsed = const {},
    this.modelVersion,
  });

  factory MlAnalysis.fromJson(Map<String, dynamic> json) {
    final featureScoresMap = <String, double>{};
    if (json['feature_scores'] != null) {
      (json['feature_scores'] as Map<String, dynamic>).forEach((key, value) {
        featureScoresMap[key] = (value as num).toDouble();
      });
    }

    final featuresUsedMap = <String, double>{};
    if (json['features_used'] != null) {
      (json['features_used'] as Map<String, dynamic>).forEach((key, value) {
        featuresUsedMap[key] = (value as num).toDouble();
      });
    }

    return MlAnalysis(
      anomalyScore: (json['anomaly_score'] as num?)?.toDouble() ?? 0.0,
      isAnomaly: json['is_anomaly'] ?? false,
      anomalyReason: json['anomaly_reason'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      featureScores: featureScoresMap,
      featuresUsed: featuresUsedMap,
      modelVersion: json['model_version'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'anomaly_score': anomalyScore,
      'is_anomaly': isAnomaly,
      'anomaly_reason': anomalyReason,
      'confidence': confidence,
      'feature_scores': featureScores,
      'features_used': featuresUsed,
      'model_version': modelVersion,
    };
  }
}
