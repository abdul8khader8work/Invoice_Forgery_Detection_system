import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Responsive layout utilities for multi-platform support
/// Breakpoints: 320px (mobile), 768px (tablet), 1024px (desktop), 1920px (wide)
class Responsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 768;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 768 && width < 1024;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  static bool isWide(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1920;

  /// Get responsive value based on screen size
  static T get<T>({
    required BuildContext context,
    required T mobile,
    T? tablet,
    T? desktop,
    T? wide,
  }) {
    if (isWide(context) && wide != null) return wide;
    if (isDesktop(context) && desktop != null) return desktop;
    if (isTablet(context) && tablet != null) return tablet;
    return mobile;
  }

  /// Get responsive padding
  static EdgeInsets padding(BuildContext context) =>
      get(
        context: context,
        mobile: const EdgeInsets.all(16),
        tablet: const EdgeInsets.all(24),
        desktop: const EdgeInsets.all(32),
      );

  /// Get responsive font size
  static double fontSize(BuildContext context, double baseSize) =>
      get(
        context: context,
        mobile: baseSize,
        tablet: baseSize * 1.1,
        desktop: baseSize * 1.2,
      );

  /// Get grid column count
  static int gridColumns(BuildContext context) =>
      get(
        context: context,
        mobile: 1,
        tablet: 2,
        desktop: 3,
        wide: 4,
      );

  /// Get max content width
  static double maxContentWidth(BuildContext context) =>
      get(
        context: context,
        mobile: double.infinity,
        tablet: 700,
        desktop: 1000,
        wide: 1400,
      );
}

/// Responsive layout builder
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;
  final Widget? wide;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
    this.wide,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1920 && wide != null) {
          return wide!;
        }
        if (constraints.maxWidth >= 1024 && desktop != null) {
          return desktop!;
        }
        if (constraints.maxWidth >= 768 && tablet != null) {
          return tablet!;
        }
        return mobile;
      },
    );
  }
}

/// Platform-specific optimizations
class PlatformAdaptive {
  /// Check if running on web
  static bool get isWeb =>
      identical(0, 0.0); // Web indicator

  /// Check if running on Windows (MSIX)
  static bool get isWindows =>
      !isWeb && _isWindowsImpl();

  /// Check if running on mobile
  static bool get isMobile =>
      !isWeb && (_isAndroidImpl() || _isIOSImpl());

  /// Get keyboard shortcuts map for desktop
  static Map<ShortcutActivator, Intent> get desktopShortcuts => {
    SingleActivator(LogicalKeyboardKey.keyO, control: true): 
        OpenFileIntent(),
    SingleActivator(LogicalKeyboardKey.keyS, control: true):
        SaveIntent(),
    SingleActivator(LogicalKeyboardKey.keyR, control: true):
        RefreshIntent(),
  };

  static bool _isWindowsImpl() {
    try {
      return const bool.fromEnvironment('dart.library.io') &&
             !const bool.fromEnvironment('dart.library.js');
    } catch (_) {
      return false;
    }
  }

  static bool _isAndroidImpl() {
    return const bool.fromEnvironment('dart.library.io', defaultValue: false) &&
           !const bool.fromEnvironment('dart.library.js', defaultValue: true);
  }

  static bool _isIOSImpl() {
    return _isAndroidImpl(); // Simplified check
  }
}

/// Safe area wrapper for mobile
class MobileSafeArea extends StatelessWidget {
  final Widget child;
  final bool maintainBottomViewPadding;

  const MobileSafeArea({
    super.key,
    required this.child,
    this.maintainBottomViewPadding = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!PlatformAdaptive.isMobile) {
      return child;
    }

    return SafeArea(
      maintainBottomViewPadding: maintainBottomViewPadding,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    );
  }
}

/// Desktop shortcut intents
class OpenFileIntent extends Intent {}
class SaveIntent extends Intent {}
class RefreshIntent extends Intent {}
