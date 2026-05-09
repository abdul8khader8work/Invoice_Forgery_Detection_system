import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings.dart';
import '../services/settings_service.dart';
import '../layouts/main_layout.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  AppSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _saved = false;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    }
  }
  
  Future<void> _saveSettings() async {
    if (_settings == null) return;
    
    setState(() {
      _isSaving = true;
    });
    
    final success = await _settingsService.saveSettings(_settings!);
    
    setState(() {
      _isSaving = false;
      _saved = success;
    });
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Settings saved successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      // Hide success message after 3 seconds
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _saved = false;
          });
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  
  void _updateSetting<T>(void Function(T) setter, T value) {
    setState(() {
      setter(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    Widget content;
    
    if (_isLoading || _settings == null) {
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading settings...'),
          ],
        ),
      );
    } else {
      content = SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Configure detection features and preferences',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: isMobile ? 16 : 32),
            _buildDetectionFeaturesSection(context, isMobile),
            SizedBox(height: isMobile ? 16 : 24),
            _buildNotificationsSection(context, isMobile),
            SizedBox(height: isMobile ? 16 : 24),
            _buildRiskThresholdSection(context, isMobile),
            SizedBox(height: isMobile ? 16 : 24),
            _buildDataManagementSection(context, isMobile),
            SizedBox(height: isMobile ? 80 : 32),
            _buildSaveButton(context),
          ],
        ),
      );
    }
    
    return MainLayout(child: content);
  }
  
  Widget _buildDetectionFeaturesSection(BuildContext context, bool isMobile) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Text(
              'Detection Features',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 12 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SettingToggle(
                  label: 'Advanced Detection',
                  description: 'Enable AI-powered deep learning models for enhanced forgery detection',
                  checked: _settings!.advancedDetection,
                  onChanged: (value) => setState(() => _settings = _settings!.copyWith(advancedDetection: value)),
                  isMobile: isMobile,
                ),
                SizedBox(height: isMobile ? 16 : 24),
                _SettingToggle(
                  label: 'OCR Processing',
                  description: 'Extract and analyze text content from invoice images',
                  checked: _settings!.ocrEnabled,
                  onChanged: (value) => setState(() => _settings = _settings!.copyWith(ocrEnabled: value)),
                  isMobile: isMobile,
                ),
                SizedBox(height: isMobile ? 16 : 24),
                _SettingToggle(
                  label: 'Batch Processing',
                  description: 'Allow uploading and processing multiple invoices simultaneously',
                  checked: _settings!.batchProcessing,
                  onChanged: (value) => setState(() => _settings = _settings!.copyWith(batchProcessing: value)),
                  isMobile: isMobile,
                ),
                SizedBox(height: isMobile ? 16 : 24),
                _SettingToggle(
                  label: 'Auto-Scan',
                  description: 'Automatically start analysis when files are uploaded',
                  checked: _settings!.autoScan,
                  onChanged: (value) => setState(() => _settings = _settings!.copyWith(autoScan: value)),
                  isMobile: isMobile,
                ),
                SizedBox(height: isMobile ? 16 : 24),
                _SettingToggle(
                  label: 'Dark Mode',
                  description: 'Switch between light and dark theme for comfortable viewing',
                  checked: _settings!.darkMode,
                  onChanged: (value) {
                    setState(() => _settings = _settings!.copyWith(darkMode: value));
                    ref.read(themeModeProvider.notifier).toggleTheme(value);
                  },
                  isMobile: isMobile,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNotificationsSection(BuildContext context, bool isMobile) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Text(
              'Notifications',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: _SettingToggle(
              label: 'Email Notifications',
              description: 'Receive email alerts when high-risk invoices are detected',
              checked: _settings!.emailNotifications,
              onChanged: (value) => setState(() => _settings = _settings!.copyWith(emailNotifications: value)),
              isMobile: isMobile,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRiskThresholdSection(BuildContext context, bool isMobile) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Text(
              'Risk Threshold',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Set the minimum risk score to flag invoices for review (0-100)',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                SizedBox(height: isMobile ? 16 : 24),
                
                // Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.red[600],
                    inactiveTrackColor: Colors.grey[300],
                    thumbColor: Colors.red[600],
                    overlayColor: Colors.red[200],
                    trackHeight: 4.0,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.0),
                  ),
                  child: Slider(
                    value: _settings!.riskThreshold.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: _settings!.riskThreshold.toString(),
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings!.copyWith(riskThreshold: value.round());
                      });
                    },
                  ),
                ),
                
                // Labels
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Low (0)',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      'High (100)',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                
                // Info box
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Invoices with a risk score of ',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        TextSpan(
                          text: _settings!.riskThreshold.toString(),
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[900]),
                        ),
                        TextSpan(
                          text: ' or higher will be flagged for manual review.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDataManagementSection(BuildContext context, bool isMobile) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Text(
              'Data Management',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDataManagementItem(
                  'Storage Location',
                  'Scan history is stored locally in your browser',
                  'Local',
                  Colors.green,
                  isMobile,
                ),
                SizedBox(height: 16),
                _buildDataManagementItem(
                  'Data Retention',
                  'Scans are retained until manually deleted',
                  'Manual',
                  Colors.blue,
                  isMobile,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDataManagementItem(String title, String description, String badge, Color badgeColor, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: isMobile ? 14 : null),
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[600], fontSize: isMobile ? 11 : 12),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: badgeColor,
                fontWeight: FontWeight.w600,
                fontSize: isMobile ? 10 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSaveButton(BuildContext context) {
    return Row(
      children: [
        if (_saved)
          Expanded(
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  'Settings saved successfully',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        Spacer(),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveSettings,
          icon: _isSaving 
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Icon(Icons.save),
          label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[600],
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            minimumSize: Size(150, 48),
          ),
        ),
      ],
    );
  }
}

// Setting Toggle Widget
class _SettingToggle extends StatelessWidget {
  final String label;
  final String description;
  final bool checked;
  final Function(bool) onChanged;
  final bool isMobile;

  const _SettingToggle({
    required this.label,
    required this.description,
    required this.checked,
    required this.onChanged,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: isMobile ? 14 : null),
              ),
              SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(color: Colors.grey[600], fontSize: isMobile ? 12 : 14),
              ),
            ],
          ),
        ),
        SizedBox(width: isMobile ? 12 : 16),
        Switch(
          value: checked,
          onChanged: onChanged,
          activeColor: Colors.red[600],
          activeTrackColor: Colors.red[200],
        ),
      ],
    );
  }
}
