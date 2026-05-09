import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/scan/screens/scan_upload_screen.dart';
import '../../features/scan/screens/scan_result_screen.dart';
import '../../features/scan/screens/scan_history_screen.dart';
import '../../features/feature_flags/feature_activation_screen.dart';
import '../../features/batch/screens/batch_upload_screen.dart';
import '../../features/batch/screens/batch_report_screen.dart';
import '../../features/analytics/screens/analytics_dashboard.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../core/api/models/scan_response.dart';
import '../../screens/settings_screen.dart';
import '../../providers/auth_provider.dart';

/// App router configuration
/// Routes: /scan (home), /feature-flags (settings)
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: true,
    routes: [
      // Redirect root to scan
      GoRoute(
        path: '/',
        name: 'home',
        redirect: (context, state) => '/scan',
      ),
      // Login route
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/scan',
        name: 'scan',
        builder: (context, state) => const ScanUploadScreen(),
      ),
      
      // Scan result screen
      GoRoute(
        path: '/scan/result',
        name: 'scan_result',
        builder: (context, state) {
          final result = state.extra as ScanResponse?;
          if (result == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: const Center(
                child: Text('No scan result data available'),
              ),
            );
          }
          return ScanResultScreen(result: result);
        },
      ),
      
      // Batch upload screen
      GoRoute(
        path: '/batch',
        name: 'batch',
        builder: (context, state) => const BatchUploadScreen(),
        routes: [
          // Batch report screen (nested route)
          GoRoute(
            path: ':batchId/report',
            name: 'batch_report',
            builder: (context, state) {
              final batchId = state.pathParameters['batchId']!;
              final invoiceIds = (state.extra as List<dynamic>?)?.cast<String>() ?? [];
              return BatchReportScreen(
                batchId: batchId,
                invoiceIds: invoiceIds,
              );
            },
          ),
        ],
      ),
      
      // Analytics dashboard
      GoRoute(
        path: '/analytics',
        name: 'analytics',
        builder: (context, state) => const AnalyticsDashboardScreen(),
      ),
      
      // Scan history
      GoRoute(
        path: '/history',
        name: 'history',
        builder: (context, state) => const ScanHistoryScreen(),
      ),
      
      // Settings screen
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      
      // Feature activation screen (read-only flag status)
      GoRoute(
        path: '/feature-flags',
        name: 'feature_flags',
        builder: (context, state) => const FeatureActivationScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(
        title: const Text('Page Not Found'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Page not found: ${state.uri.path}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/scan'),
              child: const Text('Back to Scan'),
            ),
          ],
        ),
      ),
    ),
  );
}
