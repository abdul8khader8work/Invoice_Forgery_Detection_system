import 'package:flutter/foundation.dart';

class AnalyticsRefreshService extends ChangeNotifier {
  static final AnalyticsRefreshService _instance = AnalyticsRefreshService._internal();
  factory AnalyticsRefreshService() => _instance;
  AnalyticsRefreshService._internal();

  bool _needsRefresh = false;

  bool get needsRefresh => _needsRefresh;

  void triggerRefresh() {
    _needsRefresh = true;
    notifyListeners();
    print('🔄 Analytics refresh triggered');
  }

  void markAsRefreshed() {
    _needsRefresh = false;
    notifyListeners();
    print('✅ Analytics marked as refreshed');
  }
}
