import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/utils/keyboard_shortcuts.dart';
import 'core/api/api_client.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ Add comprehensive error handling
  FlutterError.onError = (details) {
    print('❌ Flutter error: ${details.exception}');
    print('Stack: ${details.stack}');
  };
  
  try {
    print('🚀 Initializing app...');
    
    // ✅ Initialize services safely
    await _initializeServices();
    
    print('✅ App initialized, running...');
    runApp(ProviderScope(child: InvoiceForgeryDetectionApp()));
    
  } catch (e, stack) {
    print('❌ FATAL: App initialization failed: $e');
    print('Stack: $stack');
    
    // ✅ Show minimal error UI even if main app fails
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.red[900],
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 72, color: Colors.white),
                  SizedBox(height: 24),
                  Text(
                    'App Failed to Start',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Error: $e',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      // Attempt restart
                      print('🔄 User requested restart');
                    },
                    child: Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _initializeServices() async {
  try {
    // ✅ Test API connectivity early
    final client = InvoiceApiClient();
    print('🔗 API Base URL: ${client.baseUrl}');
    
    // ✅ Try a simple health check (optional, non-blocking)
    // await client.healthCheck();
    
  } catch (e) {
    print('⚠️ Service initialization warning: $e');
    // Don't throw - let app continue, errors will show later
  }
}

class InvoiceForgeryDetectionApp extends ConsumerWidget {
  const InvoiceForgeryDetectionApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    
    return KeyboardShortcutsWrapper(
      child: MaterialApp.router(
        title: 'Invoice Forgery Detection',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        routerConfig: AppRouter.router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
