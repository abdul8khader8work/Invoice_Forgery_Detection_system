import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class AuthMiddleware {
  // Check if user is authenticated before accessing route
  static Widget requireAuth(Widget child, WidgetRef ref, BuildContext context) {
    final authState = ref.watch(authProvider);
    
    return authState.when(
      data: (user) {
        if (user == null || !user.isAuthenticated) {
          // Redirect to login
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacementNamed('/login');
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return child;
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: Center(child: Text('Error: $error')),
      ),
    );
  }
}
