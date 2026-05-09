import 'package:flutter/widgets.dart';

/// Centralized helper for responsive design
class ResponsiveHelper {
  /// Check if current screen is mobile (width < 600px)
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  /// Check if current screen is tablet (width < 900px)
  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width < 900;
  }

  /// Check if current screen is desktop (width >= 900px)
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 900;
  }
}
