import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:invoice_forgery_detection/core/theme/app_colors.dart';
import 'package:invoice_forgery_detection/core/theme/app_typography.dart';
import 'package:invoice_forgery_detection/core/theme/app_spacing.dart';
import 'package:invoice_forgery_detection/core/utils/image_preprocessor.dart';
import 'package:invoice_forgery_detection/core/services/telemetry_service.dart';
import 'package:invoice_forgery_detection/core/services/platform_file_upload_service.dart';
import 'package:invoice_forgery_detection/features/scan/screens/scan_processing_screen.dart';
import '../../../layouts/main_layout.dart';

/// Scan upload screen with drag/drop, camera/gallery picker, and progress indicator
class ScanUploadScreen extends ConsumerStatefulWidget {
  const ScanUploadScreen({super.key});

  @override
  ConsumerState<ScanUploadScreen> createState() => _ScanUploadScreenState();
}

class _ScanUploadScreenState extends ConsumerState<ScanUploadScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isDragOver = false;
  String? _selectedFilePath;
  final FocusNode _galleryFocusNode = FocusNode();
  final FocusNode _cameraFocusNode = FocusNode();
  final FocusNode _filePickerFocusNode = FocusNode();

  @override
  void dispose() {
    _galleryFocusNode.dispose();
    _cameraFocusNode.dispose();
    _filePickerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _selectedFilePath = image.name);
      // Skip preprocessing on web (dart:io not supported)
      if (kIsWeb) {
        // On web, read bytes instead of using path
        final bytes = await image.readAsBytes();
        await TelemetryService().logScanStart(
          fileType: 'image',
          fileSize: bytes.length,
        );
        _navigateToProcessing(bytes);
      } else {
        // Preprocess image before navigation
        final file = File(image.path);
        final processedFile = await ImagePreprocessor.preprocessImage(file);
        await TelemetryService().logScanStart(
          fileType: 'image',
          fileSize: processedFile.lengthSync(),
        );
        _navigateToProcessing(processedFile.path);
      }
    }
  }

  Future<void> _pickFromCamera() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _selectedFilePath = image.name);
      // Skip preprocessing on web (dart:io not supported)
      if (kIsWeb) {
        // On web, read bytes instead of using path
        final bytes = await image.readAsBytes();
        await TelemetryService().logScanStart(
          fileType: 'camera',
          fileSize: bytes.length,
        );
        _navigateToProcessing(bytes);
      } else {
        // Preprocess image before navigation
        final file = File(image.path);
        final processedFile = await ImagePreprocessor.preprocessImage(file);
        await TelemetryService().logScanStart(
          fileType: 'camera',
          fileSize: processedFile.lengthSync(),
        );
        _navigateToProcessing(processedFile.path);
      }
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      allowMultiple: false,
    );

    if (result != null) {
      final file = result.files.single;
      
      // Handle web platform differently (use bytes instead of path)
      if (kIsWeb) {
        if (file.bytes != null) {
          setState(() => _selectedFilePath = file.name);
          await TelemetryService().logScanStart(
            fileType: file.extension ?? 'unknown',
            fileSize: file.bytes!.length,
          );
          // On web, pass bytes to processing screen
          _navigateToProcessing(file.bytes!);
        }
      } else {
        // Desktop/mobile platform
        if (file.path != null) {
          final filePath = file.path!;
          setState(() => _selectedFilePath = filePath);
          
          // Preprocess image files (not PDFs)
          if (!filePath.toLowerCase().endsWith('.pdf')) {
            final file = File(filePath);
            final processedFile = await ImagePreprocessor.preprocessImage(file);
            await TelemetryService().logScanStart(
              fileType: filePath.split('.').last,
              fileSize: processedFile.lengthSync(),
            );
            _navigateToProcessing(processedFile.path);
          } else {
            await TelemetryService().logScanStart(
              fileType: 'pdf',
              fileSize: File(filePath).lengthSync(),
            );
            _navigateToProcessing(filePath);
          }
        }
      }
    }
  }

  void _navigateToProcessing(dynamic file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanProcessingScreen(file: file),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upload Invoice',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Upload single invoices for forgery detection',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 32),
            // Upload Invoice Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Upload Invoice',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Divider(height: 1),
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: DragTarget<String>(
                      onWillAcceptWithDetails: (details) => true,
                      onAcceptWithDetails: (details) async {
                        setState(() => _isDragOver = false);
                        if (kIsWeb) {
                          try {
                            final bytes = await File(details.data).readAsBytes();
                            _navigateToProcessing(bytes);
                          } catch (e) {
                            _navigateToProcessing(details.data);
                          }
                        } else {
                          _navigateToProcessing(details.data);
                        }
                      },
                      onLeave: (details) {
                        setState(() => _isDragOver = false);
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Focus(
                          focusNode: _filePickerFocusNode,
                          onKeyEvent: (node, event) {
                            if (event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.space) {
                              _pickFile();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: GestureDetector(
                            onTap: _pickFile,
                            child: Semantics(
                              button: true,
                              label: 'Upload invoice file',
                              hint: 'Tap to browse files or drag and drop',
                              child: Container(
                                height: 300,
                                decoration: BoxDecoration(
                                  color: _isDragOver
                                      ? Color(0xFF2A2A4E)
                                      : Color(0xFF16213E),
                                  border: Border.all(
                                    color: _isDragOver
                                        ? AppColors.primary
                                        : Colors.white10,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isDragOver ? Icons.cloud_upload : Icons.cloud_upload_outlined,
                                      size: 64,
                                      color: _isDragOver ? AppColors.primary : Colors.grey[400],
                                    )
                                        .animate()
                                        .scale(duration: 200.ms)
                                        .then()
                                        .shake(),
                                    SizedBox(height: AppSpacing.md),
                                    Text(
                                      _isDragOver ? 'Drop invoice here' : 'Drag & drop invoice',
                                      style: AppTypography.headlineSmall.copyWith(
                                        color: _isDragOver ? AppColors.primary : Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: AppSpacing.sm),
                                    Text(
                                      'or click to browse',
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                    SizedBox(height: AppSpacing.md),
                                    Text(
                                      'Supported: JPG, PNG, PDF (max 10MB)',
                                      style: AppTypography.bodySmall.copyWith(
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ).animate().fadeIn(duration: 600.ms),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 600.ms),
            SizedBox(height: 32),

            // Quick Actions Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Divider(height: 1),
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Expanded(
                          child: Focus(
                            focusNode: _galleryFocusNode,
                            onKeyEvent: (node, event) {
                              if (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey == LogicalKeyboardKey.space) {
                                _pickFromGallery();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: ElevatedButton.icon(
                              onPressed: _pickFromGallery,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Gallery'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                                minimumSize: const Size(0, 48),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: AppSpacing.md),
                        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                          Expanded(
                            child: Focus(
                              focusNode: _cameraFocusNode,
                              onKeyEvent: (node, event) {
                                if (event.logicalKey == LogicalKeyboardKey.enter ||
                                    event.logicalKey == LogicalKeyboardKey.space) {
                                  _pickFromCamera();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: ElevatedButton.icon(
                                onPressed: _pickFromCamera,
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Camera'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondary,
                                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                                  minimumSize: const Size(0, 48),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ).animate().fadeIn(duration: 600.ms, delay: 200.ms),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 600.ms, delay: 200.ms),
          ],
        ),
      ),
    );
  }
}
