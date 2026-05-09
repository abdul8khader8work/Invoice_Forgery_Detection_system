/// Design tokens for app spacing
/// Uses 4px grid system for consistent spacing
class AppSpacing {
  // Base spacing unit (4px)
  static const double unit = 4.0;

  // Spacing scale (multiples of 4px)
  static const double xs = 4.0;   // 0.25rem
  static const double sm = 8.0;   // 0.5rem
  static const double md = 16.0;  // 1rem
  static const double lg = 24.0;  // 1.5rem
  static const double xl = 32.0;  // 2rem
  static const double xxl = 48.0; // 3rem
  static const double xxxl = 64.0; // 4rem

  // Specific use cases
  static const double paddingXS = xs;
  static const double paddingSM = sm;
  static const double paddingMD = md;
  static const double paddingLG = lg;
  static const double paddingXL = xl;

  static const double marginXS = xs;
  static const double marginSM = sm;
  static const double marginMD = md;
  static const double marginLG = lg;
  static const double marginXL = xl;

  static const double gapXS = xs;
  static const double gapSM = sm;
  static const double gapMD = md;
  static const double gapLG = lg;
  static const double gapXL = xl;

  // Component-specific spacing
  static const double cardPadding = md;
  static const double buttonPadding = sm;
  static const double inputPadding = sm;
  static const double sectionSpacing = xl;
  static const double listItemSpacing = md;
}
