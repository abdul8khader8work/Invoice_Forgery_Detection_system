import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../config/app_config.dart';

class AuthService {
  final http.Client _httpClient;
  final FlutterSecureStorage _secureStorage;
  final String _baseUrl = AppConfig.apiBaseUrl;

  AuthService({http.Client? httpClient, FlutterSecureStorage? secureStorage})
    : _httpClient = httpClient ?? http.Client(),
      _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // Login with email/password
  Future<User> login(String email, String password) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = User.fromJson(data);
        
        // Store tokens securely
        await _secureStorage.write(key: 'access_token', value: user.accessToken);
        await _secureStorage.write(key: 'user_data', value: jsonEncode(user.toJson()));
        
        return user;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Login failed');
      }
    } catch (e) {
      throw Exception('Login error: $e');
    }
  }

  // Logout - clear tokens
  Future<void> logout() async {
    await _secureStorage.delete(key: 'access_token');
    await _secureStorage.delete(key: 'user_data');
  }

  // Get current user from storage
  Future<User?> getCurrentUser() async {
    try {
      final userData = await _secureStorage.read(key: 'user_data');
      if (userData != null) {
        return User.fromJson(jsonDecode(userData));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final user = await getCurrentUser();
    return user?.isAuthenticated ?? false;
  }

  // Get access token for API calls
  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: 'access_token');
  }
}
