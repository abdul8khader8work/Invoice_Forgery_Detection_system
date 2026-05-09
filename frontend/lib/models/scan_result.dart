import 'dart:typed_data';

class ScanResult {
  final String fileId;
  final String filename;
  final Map<String, dynamic> extractedData;
  final Map<String, double> ocrConfidence;
  final Map<String, dynamic> deterministicValidation;
  final Map<String, dynamic> mlAnalysis;
  final double riskScore;
  final String riskLevel;
  final List<String> reasoning;
  final bool needsVerification;
  final List<String> verificationFields;
  final double processingTime;
  final String timestamp;
  final Uint8List? fileBytes; // Added to display uploaded image

  ScanResult({
    required this.fileId,
    required this.filename,
    required this.extractedData,
    required this.ocrConfidence,
    required this.deterministicValidation,
    required this.mlAnalysis,
    required this.riskScore,
    required this.riskLevel,
    required this.reasoning,
    required this.needsVerification,
    required this.verificationFields,
    required this.processingTime,
    required this.timestamp,
    this.fileBytes,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    print('ScanResult.fromJson called with keys: ${json.keys}');
    
    final extractedData = json['extracted_data'];
    print('extractedData type: ${extractedData.runtimeType}');
    
    final safeExtractedData = (extractedData is Map) ? extractedData : {};
    final confidenceScores = (safeExtractedData['confidence_scores'] is Map) 
        ? safeExtractedData['confidence_scores'] 
        : {};
    
    print('confidenceScores: $confidenceScores');
    
    return ScanResult(
      fileId: json['file_id']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      extractedData: Map<String, dynamic>.from(safeExtractedData),
      ocrConfidence: Map<String, double>.from(
        (confidenceScores is Map ? confidenceScores : {}).map(
          (key, value) => MapEntry(key.toString(), (value is num ? value : 0).toDouble()),
        ),
      ),
      deterministicValidation: Map<String, dynamic>.from(
        json['deterministic_validation'] is Map ? json['deterministic_validation'] : {},
      ),
      mlAnalysis: Map<String, dynamic>.from(
        json['ml_analysis'] is Map ? json['ml_analysis'] : {},
      ),
      riskScore: (json['risk_score'] is num ? json['risk_score'] : 0).toDouble(),
      riskLevel: json['risk_level']?.toString() ?? 'low',
      reasoning: List<String>.from(
        json['reasoning'] is List ? json['reasoning'] : [],
      ),
      needsVerification: json['needs_verification'] == true,
      verificationFields: List<String>.from(
        json['verification_fields'] is List ? json['verification_fields'] : [],
      ),
      processingTime: (json['processing_time'] is num ? json['processing_time'] : 0).toDouble(),
      timestamp: json['timestamp']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_id': fileId,
      'filename': filename,
      'extracted_data': extractedData,
      'deterministic_validation': deterministicValidation,
      'ml_analysis': mlAnalysis,
      'risk_score': riskScore,
      'risk_level': riskLevel,
      'reasoning': reasoning,
      'needs_verification': needsVerification,
      'verification_fields': verificationFields,
      'processing_time': processingTime,
      'timestamp': timestamp,
    };
  }
}
