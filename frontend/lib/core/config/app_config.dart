import 'dart:io';
import 'package:flutter/foundation.dart';

/// Application configuration for platform-specific settings
class AppConfig {
  /// Get correct backend URL based on platform
  static String get backendUrl {
    if (kIsWeb) {
      // Web uses localhost
      return 'http://localhost:8000';
    } else if (Platform.isAndroid) {
      // Android device - use computer's IP address
      return 'http://10.236.207.92:8000';
    } else if (Platform.isIOS) {
      // iOS device - use computer's IP address
      return 'http://10.236.207.92:8000';
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // Desktop uses localhost
      return 'http://localhost:8000';
    }
    return 'http://localhost:8000';
  }

  /// Test connectivity to backend server
  static Future<bool> testConnectivity() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(backendUrl)).timeout(
        const Duration(seconds: 5),
      );
      final response = await request.close();
      client.close();
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Connectivity test failed: $e');
      return false;
    }
  }
}
