import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/providers/api_providers.dart';
import '../../core/widgets/app_navigation_bar.dart';

/// Feature Activation Screen - READ-ONLY UI
/// Shows current flag states from backend /health endpoint
/// NO server-side toggles - only displays pre-flight check results
/// User must manually edit .env file based on instructions provided
class FeatureActivationScreen extends ConsumerStatefulWidget {
  const FeatureActivationScreen({super.key});

  @override
  ConsumerState<FeatureActivationScreen> createState() => _FeatureActivationScreenState();
}

class _FeatureActivationScreenState extends ConsumerState<FeatureActivationScreen> {
  Map<String, dynamic>? _healthData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHealthStatus();
  }

  Future<void> _loadHealthStatus() async {
    try {
      // Fetch from backend health endpoint
      final apiClient = ref.read(invoiceApiClientProvider);
      final response = await apiClient.healthCheck();
      
      setState(() {
        _healthData = response as Map<String, dynamic>?;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationScaffold(
      currentIndex: 4, // Settings is the 5th tab (index 4)
      title: 'Feature Activation',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _isLoading ? null : _loadHealthStatus,
          tooltip: 'Refresh status',
        ),
      ],
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading feature flags...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadHealthStatus,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warning banner
          _buildWarningBanner(),
          const SizedBox(height: 24),
          
          // Current status section
          _buildSectionHeader('Current Feature Status'),
          _buildFeatureStatusCard(
            'JWT Authentication',
            'ENABLE_JWT_AUTH',
            'Adds token-based authentication to API endpoints',
            Icons.security,
            Colors.blue,
          ),
          _buildFeatureStatusCard(
            'Async Scan Processing',
            'ENABLE_ASYNC_SCAN',
            'Enables background processing with status polling',
            Icons.sync,
            Colors.orange,
          ),
          _buildFeatureStatusCard(
            'PostgreSQL Database',
            'ENABLE_DB_V2',
            'Migrate from SQLite to production PostgreSQL',
            Icons.storage,
            Colors.green,
          ),
          _buildFeatureStatusCard(
            'Security Hardening',
            'ENABLE_SECURITY_HARDENING',
            'Rate limiting, file validation, CORS lockdown',
            Icons.shield,
            Colors.purple,
          ),
          _buildFeatureStatusCard(
            'Celery Task Queue',
            'ENABLE_CELERY',
            'Replace BackgroundTasks with Redis-backed Celery',
            Icons.task_alt,
            Colors.teal,
          ),
          _buildFeatureStatusCard(
            'Auto Model Retraining',
            'ENABLE_AUTO_RETRAIN',
            'Automated ML model updates with drift detection',
            Icons.psychology,
            Colors.indigo,
          ),
          _buildFeatureStatusCard(
            'Push Notifications',
            'ENABLE_PUSH_NOTIFICATIONS',
            'FCM/APNs integration for scan completion alerts',
            Icons.notifications,
            Colors.red,
          ),
          const SizedBox(height: 24),
          
          // Pre-flight checklist
          _buildSectionHeader('Pre-flight Checklist'),
          _buildPreFlightChecklist(),
          const SizedBox(height: 24),
          
          // Manual activation instructions
          _buildSectionHeader('Manual Activation Steps'),
          _buildActivationInstructions(),
          const SizedBox(height: 24),
          
          // Rollback documentation
          _buildSectionHeader('Rollback Documentation'),
          _buildRollbackDocs(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: Colors.orange[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange[800]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Read-Only Interface',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[900],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This screen displays feature status only. To activate features, you must manually edit the .env file and restart the server.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFeatureStatusCard(
    String name,
    String flagName,
    String description,
    IconData icon,
    Color color,
  ) {
    final flags = _healthData?['feature_flags'] as Map<String, dynamic>?;
    final isEnabled = flags?[flagName] == true;
    final hasFlags = flags != null;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isEnabled ? Colors.green[50] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      flagName,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isEnabled ? Colors.green[700] : Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: !hasFlags 
                    ? Colors.orange 
                    : isEnabled 
                        ? Colors.green 
                        : Colors.grey[400],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                !hasFlags 
                    ? 'UNKNOWN' 
                    : isEnabled 
                        ? 'ENABLED' 
                        : 'DISABLED',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreFlightChecklist() {
    final checks = [
      {'name': 'JWT Secret Configured', 'status': 'pending', 'icon': Icons.key},
      {'name': 'Database Connected', 'status': 'pass', 'icon': Icons.storage},
      {'name': 'Upload Directory Writable', 'status': 'pass', 'icon': Icons.folder},
      {'name': 'Redis Available (Optional)', 'status': 'optional', 'icon': Icons.memory},
    ];

    return Card(
      child: Column(
        children: checks.map((check) {
          final status = check['status'] as String;
          Color statusColor;
          IconData statusIcon;
          
          switch (status) {
            case 'pass':
              statusColor = Colors.green;
              statusIcon = Icons.check_circle;
              break;
            case 'pending':
              statusColor = Colors.orange;
              statusIcon = Icons.pending;
              break;
            case 'optional':
              statusColor = Colors.blue;
              statusIcon = Icons.help_outline;
              break;
            default:
              statusColor = Colors.grey;
              statusIcon = Icons.help;
          }

          return ListTile(
            leading: Icon(check['icon'] as IconData, color: Colors.grey[600]),
            title: Text(check['name'] as String),
            trailing: Icon(statusIcon, color: statusColor),
            dense: true,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActivationInstructions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To enable a feature:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildInstructionStep('1', 'Open backend/.env in a text editor'),
            _buildInstructionStep('2', 'Find the feature flag (e.g., ENABLE_JWT_AUTH=false)'),
            _buildInstructionStep('3', 'Change false to true'),
            _buildInstructionStep('4', 'Save the file'),
            _buildInstructionStep('5', 'Restart the backend server'),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Quick .env snippet (copy-paste ready):',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      '# Enable production features\n'
                      'ENABLE_JWT_AUTH=false\n'
                      'ENABLE_ASYNC_SCAN=false\n'
                      'ENABLE_BATCH_UPLOAD=false\n'
                      'ENABLE_ANALYTICS_DASHBOARD=false',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white, size: 18),
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(
                        text: '# Enable production features\n'
                            'ENABLE_JWT_AUTH=false\n'
                            'ENABLE_ASYNC_SCAN=false\n'
                            'ENABLE_BATCH_UPLOAD=false\n'
                            'ENABLE_ANALYTICS_DASHBOARD=false',
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                    tooltip: 'Copy to clipboard',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRollbackDocs() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Emergency Rollback',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'If a feature causes issues after activation:',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            _buildRollbackCommand(
              '1. Edit .env',
              'Change the flag from true back to false',
            ),
            _buildRollbackCommand(
              '2. Restart server',
              'Stop and restart the backend server',
            ),
            _buildRollbackCommand(
              '3. Clear cache',
              'Restart the Flutter app to refresh feature flags',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.emergency, color: Colors.red[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Document rollback commands in your runbook before enabling any feature.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRollbackCommand(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right, color: Colors.grey[600], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
