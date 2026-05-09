/// Design tokens for app elevation
/// Consistent elevation levels for depth and hierarchy
class AppElevation {
  static const double level0 = 0.0;
  static const double level1 = 1.0;
  static const double level2 = 2.0;
  static const double level3 = 4.0;
  static const double level4 = 6.0;
  static const double level5 = 8.0;
  static const double level6 = 12.0;
  static const double level7 = 16.0;
  static const double level8 = 24.0;

  // Common use cases
  static const double card = level1;
  static const double elevatedCard = level3;
  static const double modal = level6;
  static const double bottomSheet = level8;
  static const double dropdown = level4;
  static const double button = level2;
  static const double floatingButton = level6;
}
