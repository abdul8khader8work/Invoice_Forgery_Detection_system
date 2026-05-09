import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoice_forgery_detection/core/api/api_client.dart';
import 'package:invoice_forgery_detection/core/providers/api_providers.dart';
import 'package:invoice_forgery_detection/core/services/analytics_refresh_service.dart';

/// Analytics data model
class AnalyticsData {
  final int totalScans;
  final int highRiskScans;
  final int mediumRiskScans;
  final int lowRiskScans;
  final double averageConfidence;
  final List<VendorData> topVendors;
  final List<RiskTrendData> riskTrend;
  final int verifiedScans;
  final int unverifiedScans;
  final int approvedScans;
  final int editedScans;
  
  AnalyticsData({
    required this.totalScans,
    required this.highRiskScans,
    required this.mediumRiskScans,
    required this.lowRiskScans,
    required this.averageConfidence,
    required this.topVendors,
    required this.riskTrend,
    this.verifiedScans = 0,
    this.unverifiedScans = 0,
    this.approvedScans = 0,
    this.editedScans = 0,
  });
  
  factory AnalyticsData.fromJson(Map<String, dynamic> json) {
    return AnalyticsData(
      totalScans: json['total_scans'] ?? 0,
      highRiskScans: json['high_risk_scans'] ?? 0,
      mediumRiskScans: json['medium_risk_scans'] ?? 0,
      lowRiskScans: json['low_risk_scans'] ?? 0,
      averageConfidence: (json['average_confidence'] ?? 0.0).toDouble(),
      topVendors: (json['top_vendors'] as List?)
          ?.map((v) => VendorData.fromJson(v))
          .toList() ?? [],
      riskTrend: (json['risk_trend'] as List?)
          ?.map((r) => RiskTrendData.fromJson(r))
          .toList() ?? [],
      verifiedScans: json['verified_scans'] ?? 0,
      unverifiedScans: json['unverified_scans'] ?? 0,
      approvedScans: json['approved_scans'] ?? 0,
      editedScans: json['edited_scans'] ?? 0,
    );
  }
}

class VendorData {
  final String name;
  final int scanCount;
  final int highRiskCount;
  final double averageRiskScore;
  
  VendorData({
    required this.name,
    required this.scanCount,
    required this.highRiskCount,
    required this.averageRiskScore,
  });
  
  factory VendorData.fromJson(Map<String, dynamic> json) {
    return VendorData(
      name: json['name'] ?? 'Unknown',
      scanCount: json['scan_count'] ?? 0,
      highRiskCount: json['high_risk_count'] ?? 0,
      averageRiskScore: (json['average_risk_score'] ?? 0.0).toDouble(),
    );
  }
}

class RiskTrendData {
  final String date;
  final int highRisk;
  final int mediumRisk;
  final int lowRisk;
  
  RiskTrendData({
    required this.date,
    required this.highRisk,
    required this.mediumRisk,
    required this.lowRisk,
  });
  
  factory RiskTrendData.fromJson(Map<String, dynamic> json) {
    return RiskTrendData(
      date: json['date'] ?? '',
      highRisk: json['high_risk'] ?? 0,
      mediumRisk: json['medium_risk'] ?? 0,
      lowRisk: json['low_risk'] ?? 0,
    );
  }
}

/// Time range filter
enum TimeRange {
  last7Days,
  last30Days,
  last90Days,
  custom,
}

/// Analytics state
class AnalyticsState {
  final AnalyticsData? data;
  final bool isLoading;
  final String? error;
  final TimeRange selectedTimeRange;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  
  AnalyticsState({
    this.data,
    this.isLoading = false,
    this.error,
    this.selectedTimeRange = TimeRange.last30Days,
    this.customStartDate,
    this.customEndDate,
  });
  
  AnalyticsState copyWith({
    AnalyticsData? data,
    bool? isLoading,
    String? error,
    TimeRange? selectedTimeRange,
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) {
    return AnalyticsState(
      data: data ?? this.data,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      selectedTimeRange: selectedTimeRange ?? this.selectedTimeRange,
      customStartDate: customStartDate ?? this.customStartDate,
      customEndDate: customEndDate ?? this.customEndDate,
    );
  }
}

/// Analytics provider
class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  final InvoiceApiClient _apiClient;
  final AnalyticsRefreshService _refreshService;
  
  AnalyticsNotifier(this._apiClient, this._refreshService) : super(AnalyticsState()) {
    // Auto-fetch on initialization
    fetchAnalytics();
    // Listen to refresh service
    _refreshService.addListener(_onRefreshTriggered);
  }
  
  void _onRefreshTriggered() {
    if (_refreshService.needsRefresh) {
      fetchAnalytics();
      _refreshService.markAsRefreshed();
    }
  }
  
  @override
  void dispose() {
    _refreshService.removeListener(_onRefreshTriggered);
    super.dispose();
  }
  
  Future<void> fetchAnalytics({TimeRange? timeRange}) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      selectedTimeRange: timeRange ?? state.selectedTimeRange,
    );
    
    try {
      // Build query parameters for date filtering
      final queryParams = <String, dynamic>{};
      
      final selectedRange = timeRange ?? state.selectedTimeRange;
      final now = DateTime.now();
      
      switch (selectedRange) {
        case TimeRange.last7Days:
          queryParams['start_date'] = now.subtract(const Duration(days: 7)).toIso8601String();
          queryParams['end_date'] = now.toIso8601String();
          break;
        case TimeRange.last30Days:
          queryParams['start_date'] = now.subtract(const Duration(days: 30)).toIso8601String();
          queryParams['end_date'] = now.toIso8601String();
          break;
        case TimeRange.last90Days:
          queryParams['start_date'] = now.subtract(const Duration(days: 90)).toIso8601String();
          queryParams['end_date'] = now.toIso8601String();
          break;
        case TimeRange.custom:
          if (state.customStartDate != null) {
            queryParams['start_date'] = state.customStartDate!.toIso8601String();
          }
          if (state.customEndDate != null) {
            queryParams['end_date'] = state.customEndDate!.toIso8601String();
          }
          break;
      }
      
      // Call new analytics dashboard endpoint
      final response = await _apiClient.get(
        '/api/analytics/dashboard',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      
      if (response != null) {
        // Transform response to AnalyticsData model
        final analyticsData = _transformResponseToAnalyticsData(response);
        state = state.copyWith(
          data: analyticsData,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          data: AnalyticsData(
            totalScans: 0,
            highRiskScans: 0,
            mediumRiskScans: 0,
            lowRiskScans: 0,
            averageConfidence: 0.0,
            topVendors: [],
            riskTrend: [],
            verifiedScans: 0,
            unverifiedScans: 0,
            approvedScans: 0,
            editedScans: 0,
          ),
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error loading analytics: $e',
      );
    }
  }
  
  AnalyticsData _transformResponseToAnalyticsData(Map<String, dynamic> response) {
    // Transform backend API response to AnalyticsData model
    return AnalyticsData(
      totalScans: response['total_scans'] ?? 0,
      highRiskScans: response['high_risk_scans'] ?? 0,
      mediumRiskScans: response['medium_risk_scans'] ?? 0,
      lowRiskScans: response['low_risk_scans'] ?? 0,
      averageConfidence: (response['average_confidence'] ?? 0.0).toDouble(),
      topVendors: (response['top_vendors'] as List?)
          ?.map((v) => VendorData(
                name: v['name'] ?? 'Unknown',
                scanCount: v['scan_count'] ?? 0,
                highRiskCount: v['high_risk_count'] ?? 0,
                averageRiskScore: (v['average_risk_score'] ?? 0.0).toDouble(),
              ))
          .toList() ?? [],
      riskTrend: (response['recent_activity'] as List?)
          ?.map((r) => RiskTrendData(
                date: r['date'] ?? '',
                highRisk: r['high_risk'] ?? 0,
                mediumRisk: r['medium_risk'] ?? 0,
                lowRisk: r['low_risk'] ?? 0,
              ))
          .toList() ?? [],
      verifiedScans: response['verification_status']?['verified'] ?? 0,
      unverifiedScans: response['verification_status']?['unverified'] ?? 0,
      approvedScans: response['verification_status']?['approved'] ?? 0,
      editedScans: response['verification_status']?['edited'] ?? 0,
    );
  }
  
  void setTimeRange(TimeRange range) {
    state = state.copyWith(selectedTimeRange: range);
    fetchAnalytics(timeRange: range);
  }
  
  void setCustomDateRange(DateTime start, DateTime end) {
    state = state.copyWith(
      selectedTimeRange: TimeRange.custom,
      customStartDate: start,
      customEndDate: end,
    );
    fetchAnalytics(timeRange: TimeRange.custom);
  }
}

/// Analytics provider
final analyticsProvider = StateNotifierProvider<AnalyticsNotifier, AnalyticsState>((ref) {
  final apiClient = ref.watch(invoiceApiClientProvider);
  final refreshService = AnalyticsRefreshService();
  return AnalyticsNotifier(apiClient, refreshService);
});
