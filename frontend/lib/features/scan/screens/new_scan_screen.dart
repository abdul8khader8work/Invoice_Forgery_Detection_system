import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoice_forgery_detection/features/scan/screens/scan_upload_screen.dart';

/// New scan screen (Phase 2A parallel implementation)
/// Entry point for the new scan flow
class NewScanScreen extends ConsumerWidget {
  const NewScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ScanUploadScreen();
  }
}
