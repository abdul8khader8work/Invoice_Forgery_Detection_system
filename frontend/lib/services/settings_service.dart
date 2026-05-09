import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/settings.dart';

class SettingsService {
  static const String _settingsKey = 'app_settings';
  
  // Default settings
  static const AppSettings defaultSettings = AppSettings();
  
  /// Load settings from local storage
  Future<AppSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);
      
      if (settingsJson != null) {
        return AppSettings.fromJson(json.decode(settingsJson));
      }
    } catch (e) {
      print('❌ Error loading settings: $e');
    }
    
    return defaultSettings;
  }
  
  /// Save settings to local storage
  Future<bool> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = json.encode(settings.toJson());
      await prefs.setString(_settingsKey, settingsJson);
      print('✅ Settings saved successfully');
      return true;
    } catch (e) {
      print('❌ Error saving settings: $e');
      return false;
    }
  }
  
  /// Reset to default settings
  Future<bool> resetToDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_settingsKey);
      print('✅ Settings reset to defaults');
      return true;
    } catch (e) {
      print('❌ Error resetting settings: $e');
      return false;
    }
  }
}
