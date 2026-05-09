import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoice_forgery_detection/core/config/feature_flags.dart';

/// Debug overlay for toggling feature flags without app restart
/// Only visible in debug mode
class DebugFeatureFlagOverlay extends ConsumerStatefulWidget {
  const DebugFeatureFlagOverlay({super.key});

  @override
  ConsumerState<DebugFeatureFlagOverlay> createState() =>
      _DebugFeatureFlagOverlayState();
}

class _DebugFeatureFlagOverlayState
    extends ConsumerState<DebugFeatureFlagOverlay> {
  bool _showOverlay = false;

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode
    if (!kDebugMode) return const SizedBox.shrink();

    return Stack(
      children: [
        // Floating button to toggle overlay
        Positioned(
          top: 100,
          right: 16,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Colors.orange,
            onPressed: () {
              setState(() => _showOverlay = !_showOverlay);
            },
            child: const Icon(Icons.settings, color: Colors.white),
          ),
        ),
        // Overlay panel
        if (_showOverlay)
          Positioned(
            top: 100,
            right: 16,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Feature Flags',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() => _showOverlay = false);
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildFeatureFlagToggle(
                      'Enable New Scan UI',
                      FeatureFlags.enableNewScanUI,
                      (value) {
                        // This is for display only - actual toggle requires app restart
                        // In a real implementation, this would use a remote config service
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Feature flag change requires app restart with --dart-define',
                            ),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Current Flags:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...FeatureFlags.getAllFlags().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              entry.value ? Icons.check_circle : Icons.cancel,
                              color: entry.value ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(entry.key),
                            const Spacer(),
                            Text(
                              entry.value.toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Emergency Actions:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushNamed('/legacy-home');
                      },
                      icon: const Icon(Icons.restore),
                      label: const Text('Go to Legacy UI'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'To enable: flutter run --dart-define=ENABLE_NEW_SCAN_UI=true',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFeatureFlagToggle(
    String label,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
        ),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
