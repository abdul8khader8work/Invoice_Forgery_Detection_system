class AppSettings {
  // Detection Features
  final bool advancedDetection;
  final bool ocrEnabled;
  final bool batchProcessing;
  final bool autoScan;
  
  // Notifications
  final bool emailNotifications;
  
  // Risk Threshold
  final int riskThreshold; // 0-100
  
  // Data Management
  final String storageLocation; // 'local' or 'cloud'
  final String dataRetention; // 'manual' or 'auto'
  
  // Theme
  final bool darkMode;
  
  const AppSettings({
    this.advancedDetection = true,
    this.ocrEnabled = true,
    this.batchProcessing = true,
    this.autoScan = true,
    this.emailNotifications = false,
    this.riskThreshold = 36,
    this.storageLocation = 'local',
    this.dataRetention = 'manual',
    this.darkMode = false,
  });
  
  AppSettings copyWith({
    bool? advancedDetection,
    bool? ocrEnabled,
    bool? batchProcessing,
    bool? autoScan,
    bool? emailNotifications,
    int? riskThreshold,
    String? storageLocation,
    String? dataRetention,
    bool? darkMode,
  }) {
    return AppSettings(
      advancedDetection: advancedDetection ?? this.advancedDetection,
      ocrEnabled: ocrEnabled ?? this.ocrEnabled,
      batchProcessing: batchProcessing ?? this.batchProcessing,
      autoScan: autoScan ?? this.autoScan,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      riskThreshold: riskThreshold ?? this.riskThreshold,
      storageLocation: storageLocation ?? this.storageLocation,
      dataRetention: dataRetention ?? this.dataRetention,
      darkMode: darkMode ?? this.darkMode,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'advancedDetection': advancedDetection,
      'ocrEnabled': ocrEnabled,
      'batchProcessing': batchProcessing,
      'autoScan': autoScan,
      'emailNotifications': emailNotifications,
      'riskThreshold': riskThreshold,
      'storageLocation': storageLocation,
      'dataRetention': dataRetention,
      'darkMode': darkMode,
    };
  }
  
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      advancedDetection: json['advancedDetection'] ?? true,
      ocrEnabled: json['ocrEnabled'] ?? true,
      batchProcessing: json['batchProcessing'] ?? true,
      autoScan: json['autoScan'] ?? true,
      emailNotifications: json['emailNotifications'] ?? false,
      riskThreshold: json['riskThreshold'] ?? 36,
      storageLocation: json['storageLocation'] ?? 'local',
      dataRetention: json['dataRetention'] ?? 'manual',
      darkMode: json['darkMode'] ?? false,
    );
  }
}
