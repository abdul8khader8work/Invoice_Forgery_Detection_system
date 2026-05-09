import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings.dart';
import '../services/settings_service.dart';

// Theme mode provider
final themeModeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  final SettingsService _settingsService = SettingsService();
  
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }
  
  Future<void> _loadTheme() async {
    final settings = await _settingsService.loadSettings();
    state = settings.darkMode ? ThemeMode.dark : ThemeMode.dark;
  }
  
  Future<void> toggleTheme(bool isDark) async {
    state = isDark ? ThemeMode.dark : ThemeMode.light;
    
    // Save to settings
    final settings = await _settingsService.loadSettings();
    await _settingsService.saveSettings(
      settings.copyWith(darkMode: isDark)
    );
  }
}

// Dark theme
final darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  primarySwatch: Colors.red,
  scaffoldBackgroundColor: Color(0xFF1A1A2E),
  cardColor: Color(0xFF16213E),
  dividerColor: Colors.white10,
  textTheme: TextTheme(
    headlineMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    bodyLarge: TextStyle(color: Colors.white70),
  ),
);

// Light theme
final lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  primarySwatch: Colors.red,
  scaffoldBackgroundColor: Colors.white,
  cardColor: Colors.white,
  dividerColor: Colors.grey[200],
  textTheme: TextTheme(
    headlineMedium: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
    bodyLarge: TextStyle(color: Colors.grey[700]),
  ),
);
