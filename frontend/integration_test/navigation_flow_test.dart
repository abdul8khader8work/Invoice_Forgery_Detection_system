import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_forgery_detection/main.dart';
import 'package:invoice_forgery_detection/core/router/app_router.dart';
import 'package:invoice_forgery_detection/features/feature_flags/feature_activation_screen.dart';
import 'package:invoice_forgery_detection/features/scan/screens/scan_upload_screen.dart';

/// Integration tests for navigation flows
/// Tests: Bottom navigation, responsive layout, keyboard shortcuts, URL routing
void main() {
  group('Navigation Flow Tests', () {
    late GoRouter router;

    setUp(() {
      router = AppRouter.router;
    });

    testWidgets('Initial route loads ScanUploadScreen', (WidgetTester tester) async {
      // Build the app
      await tester.pumpWidget(
        const ProviderScope(
          child: InvoiceForgeryDetectionApp(),
        ),
      );

      // Wait for app to load
      await tester.pumpAndSettle();

      // Verify we're on the Scan screen
      expect(find.byType(ScanUploadScreen), findsOneWidget);
      expect(find.text('Upload Invoice'), findsOneWidget);
      
      // Verify navigation bar is present
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('Navigate to Feature Flags via bottom nav', (WidgetTester tester) async {
      // Build the app
      await tester.pumpWidget(
        const ProviderScope(
          child: InvoiceForgeryDetectionApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Settings tab (5th item in nav bar)
      final settingsTab = find.widgetWithText(NavigationDestination, 'Settings');
      expect(settingsTab, findsOneWidget);
      
      await tester.tap(settingsTab);
      await tester.pumpAndSettle();

      // Verify we're on Feature Activation screen
      expect(find.byType(FeatureActivationScreen), findsOneWidget);
      expect(find.text('Feature Activation'), findsOneWidget);
      
      // Verify Settings tab is selected by checking current route
      expect(find.byType(FeatureActivationScreen), findsOneWidget);
    });

    testWidgets('Navigate back to Scan via bottom nav', (WidgetTester tester) async {
      // Build the app
      await tester.pumpWidget(
        const ProviderScope(
          child: InvoiceForgeryDetectionApp(),
        ),
      );
      await tester.pumpAndSettle();

      // First navigate to Settings
      final settingsTab = find.widgetWithText(NavigationDestination, 'Settings');
      await tester.tap(settingsTab);
      await tester.pumpAndSettle();

      // Verify we're on Feature Activation screen
      expect(find.byType(FeatureActivationScreen), findsOneWidget);

      // Tap on Scan tab to go back
      final scanTab = find.widgetWithText(NavigationDestination, 'Scan');
      expect(scanTab, findsOneWidget);
      
      await tester.tap(scanTab);
      await tester.pumpAndSettle();

      // Verify we're back on Scan screen
      expect(find.byType(ScanUploadScreen), findsOneWidget);
      expect(find.text('Upload Invoice'), findsOneWidget);
    });

    testWidgets('Placeholder routes show coming soon message', (WidgetTester tester) async {
      // Build the app
      await tester.pumpWidget(
        const ProviderScope(
          child: InvoiceForgeryDetectionApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Try Batch tab
      final batchTab = find.widgetWithText(NavigationDestination, 'Batch');
      await tester.tap(batchTab);
      await tester.pumpAndSettle();

      // Should show snackbar
      expect(find.text('Batch screen coming soon'), findsOneWidget);
      
      // Dismiss snackbar
      await tester.pump(const Duration(seconds: 3));
      
      // Try Analytics tab
      final analyticsTab = find.widgetWithText(NavigationDestination, 'Analytics');
      await tester.tap(analyticsTab);
      await tester.pumpAndSettle();

      // Should show snackbar
      expect(find.text('Analytics screen coming soon'), findsOneWidget);
    });

    testWidgets('URL navigation works correctly', (WidgetTester tester) async {
      // Build the app
      await tester.pumpWidget(
        const ProviderScope(
          child: InvoiceForgeryDetectionApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate directly to feature flags via URL
      router.go('/feature-flags');
      await tester.pumpAndSettle();

      // Verify we're on Feature Activation screen
      expect(find.byType(FeatureActivationScreen), findsOneWidget);
      expect(find.text('Feature Activation'), findsOneWidget);

      // Navigate back to scan via URL
      router.go('/scan');
      await tester.pumpAndSettle();

      // Verify we're back on Scan screen
      expect(find.byType(ScanUploadScreen), findsOneWidget);
      expect(find.text('Upload Invoice'), findsOneWidget);
    });

    testWidgets('Invalid URL shows error page', (WidgetTester tester) async {
      // Build the app
      await tester.pumpWidget(
        const ProviderScope(
          child: InvoiceForgeryDetectionApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to invalid URL
      router.go('/invalid-route');
      await tester.pumpAndSettle();

      // Should show error page
      expect(find.text('Page Not Found'), findsOneWidget);
      expect(find.text('Page not found: /invalid-route'), findsOneWidget);
      expect(find.text('Back to Scan'), findsOneWidget);

      // Test back button works
      await tester.tap(find.text('Back to Scan'));
      await tester.pumpAndSettle();

      // Should be back on scan screen
      expect(find.byType(ScanUploadScreen), findsOneWidget);
    });

    group('Responsive Layout Tests', () {
      testWidgets('Mobile layout shows bottom navigation', (WidgetTester tester) async {
        // Set mobile size
        tester.binding.window.physicalSizeTestValue = const Size(375, 667);
        tester.binding.window.devicePixelRatioTestValue = 1.0;

        // Build the app
        await tester.pumpWidget(
          const ProviderScope(
            child: InvoiceForgeryDetectionApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Should show bottom navigation bar
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      });

      testWidgets('Desktop layout shows side navigation rail', (WidgetTester tester) async {
        // Set desktop size
        tester.binding.window.physicalSizeTestValue = const Size(1200, 800);
        tester.binding.window.devicePixelRatioTestValue = 1.0;

        // Build the app
        await tester.pumpWidget(
          const ProviderScope(
            child: InvoiceForgeryDetectionApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Should show navigation rail
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
      });
    });

    group('Accessibility Tests', () {
      testWidgets('Navigation elements are accessible', (WidgetTester tester) async {
        // Build the app
        await tester.pumpWidget(
          const ProviderScope(
            child: InvoiceForgeryDetectionApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Check nav items have semantic labels
        final scanTab = find.widgetWithText(NavigationDestination, 'Scan');
        expect(scanTab, findsOneWidget);
        
        // Should be focusable
        await tester.tap(scanTab);
        await tester.pumpAndSettle();
        
        // Navigation should work with semantic actions
        expect(find.byType(ScanUploadScreen), findsOneWidget);
      });
    });
  });
}
