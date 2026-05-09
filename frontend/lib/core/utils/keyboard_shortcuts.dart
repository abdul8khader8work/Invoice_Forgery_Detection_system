import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Desktop keyboard shortcuts for Windows MSIX and Web
/// Provides quick navigation via keyboard
class KeyboardShortcuts {
  /// Build shortcut activators for the app
  static Map<ShortcutActivator, Intent> get shortcuts => {
    // Ctrl+1: Navigate to Scan
    SingleActivator(LogicalKeyboardKey.digit1, control: true): 
        NavigateToScanIntent(),
    
    // Ctrl+2: Navigate to Batch (placeholder)
    SingleActivator(LogicalKeyboardKey.digit2, control: true): 
        NavigateToBatchIntent(),
    
    // Ctrl+3: Navigate to Analytics (placeholder)
    SingleActivator(LogicalKeyboardKey.digit3, control: true): 
        NavigateToAnalyticsIntent(),
    
    // Ctrl+4: Navigate to History (placeholder)
    SingleActivator(LogicalKeyboardKey.digit4, control: true): 
        NavigateToHistoryIntent(),
    
    // Ctrl+5: Navigate to Settings/Feature Flags
    SingleActivator(LogicalKeyboardKey.digit5, control: true): 
        NavigateToSettingsIntent(),
    
    // Ctrl+O: Open file (upload)
    SingleActivator(LogicalKeyboardKey.keyO, control: true): 
        OpenFileIntent(),
    
    // Ctrl+R: Refresh
    SingleActivator(LogicalKeyboardKey.keyR, control: true): 
        RefreshIntent(),
    
    // F5: Refresh (alternative)
    SingleActivator(LogicalKeyboardKey.f5): 
        RefreshIntent(),
    
    // Escape: Go back
    SingleActivator(LogicalKeyboardKey.escape): 
        GoBackIntent(),
  };
}

/// Intent definitions for keyboard shortcuts
class NavigateToScanIntent extends Intent {}
class NavigateToBatchIntent extends Intent {}
class NavigateToAnalyticsIntent extends Intent {}
class NavigateToHistoryIntent extends Intent {}
class NavigateToSettingsIntent extends Intent {}
class OpenFileIntent extends Intent {}
class RefreshIntent extends Intent {}
class GoBackIntent extends Intent {}

/// Action handlers for keyboard shortcuts
class KeyboardActionHandlers {
  static Map<Type, Action<Intent>> getActions(BuildContext context) {
    return {
      NavigateToScanIntent: CallbackAction<NavigateToScanIntent>(
        onInvoke: (_) => context.go('/scan'),
      ),
      NavigateToBatchIntent: CallbackAction<NavigateToBatchIntent>(
        onInvoke: (_) {
          // Placeholder - will navigate when batch screen is implemented
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Batch screen coming soon')),
          );
          return null;
        },
      ),
      NavigateToAnalyticsIntent: CallbackAction<NavigateToAnalyticsIntent>(
        onInvoke: (_) {
          // Placeholder - will navigate when analytics screen is implemented
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Analytics screen coming soon')),
          );
          return null;
        },
      ),
      NavigateToHistoryIntent: CallbackAction<NavigateToHistoryIntent>(
        onInvoke: (_) {
          // Placeholder - will navigate when history screen is implemented
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('History screen coming soon')),
          );
          return null;
        },
      ),
      NavigateToSettingsIntent: CallbackAction<NavigateToSettingsIntent>(
        onInvoke: (_) => context.go('/feature-flags'),
      ),
      OpenFileIntent: CallbackAction<OpenFileIntent>(
        onInvoke: (_) {
          // Triggered on Scan screen - handled by screen itself
          // This is a signal that user wants to open file picker
          return null;
        },
      ),
      RefreshIntent: CallbackAction<RefreshIntent>(
        onInvoke: (_) {
          // Handled by individual screens
          return null;
        },
      ),
      GoBackIntent: CallbackAction<GoBackIntent>(
        onInvoke: (_) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else if (GoRouter.of(context).canPop()) {
            GoRouter.of(context).pop();
          }
          return null;
        },
      ),
    };
  }
}

/// Widget that wraps the app with keyboard shortcuts
class KeyboardShortcutsWrapper extends StatelessWidget {
  final Widget child;

  const KeyboardShortcutsWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Only enable shortcuts on desktop platforms
    final isDesktop = _isDesktopPlatform();
    
    if (!isDesktop) {
      return child;
    }

    return Shortcuts(
      shortcuts: KeyboardShortcuts.shortcuts,
      child: Actions(
        actions: KeyboardActionHandlers.getActions(context),
        child: child,
      ),
    );
  }

  bool _isDesktopPlatform() {
    // On web, enable keyboard shortcuts
    if (kIsWeb) return true;
    
    // Check if running on desktop (Windows, macOS, Linux)
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }
}
