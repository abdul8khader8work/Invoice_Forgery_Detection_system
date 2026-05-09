import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:invoice_forgery_detection/theme/app_colors.dart';
import 'package:invoice_forgery_detection/theme/app_text_styles.dart';
import 'package:invoice_forgery_detection/theme/app_spacing.dart';
import 'package:invoice_forgery_detection/theme/app_border_radius.dart';
import 'package:invoice_forgery_detection/layouts/main_layout.dart';
import 'package:invoice_forgery_detection/widgets/upload_area.dart';
import 'package:invoice_forgery_detection/core/utils/image_preprocessor.dart';
import 'package:invoice_forgery_detection/core/services/telemetry_service.dart';
import 'package:invoice_forgery_detection/core/services/platform_file_upload_service.dart';
import 'package:invoice_forgery_detection/features/scan/screens/scan_processing_screen.dart';

/// Enhanced scan upload screen with new design system
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
        await _navigateToProcessing(bytes, image.name);
      } else {
        await _processImageFile(File(image.path));
      }
    }
  }

  Future<void> _pickFromCamera() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _selectedFilePath = image.name);
      // Skip preprocessing on web (dart:io not supported)
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await _navigateToProcessing(bytes, image.name);
      } else {
        await _processImageFile(File(image.path));
      }
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      setState(() => _selectedFilePath = file.name);
      
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes != null) {
          await _navigateToProcessing(bytes, file.name);
        }
      } else {
        await _processImageFile(File(file.path!));
      }
    }
  }

  Future<void> _processImageFile(File imageFile) async {
    try {
      TelemetryService().trackUserAction(
        'scan_upload_image_selected',
        parameters: {
          'file_name': imageFile.path.split('/').last,
          'file_size': imageFile.lengthSync(),
        },
      );

      final processedImage = await ImagePreprocessor.preprocessImage(imageFile);
      final bytes = await processedImage.readAsBytes();
      
      await _navigateToProcessing(bytes, imageFile.path.split('/').last);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _navigateToProcessing(Uint8List bytes, String fileName) async {
    if (!mounted) return;

    TelemetryService().trackScreenView('scan_processing_screen');
    
    final uploadService = PlatformFileUploadService();
    final uploadResult = await uploadService.uploadFile(bytes, fileName);

    if (uploadResult.success && uploadResult.fileId != null) {
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScanProcessingScreen(
              file: bytes,
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uploadResult.error ?? 'Upload failed'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _handleFilesSelected(List<PlatformFile> files) {
    if (files.isNotEmpty) {
      final file = files.first;
      setState(() => _selectedFilePath = file.name);
      
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes != null) {
          _navigateToProcessing(bytes, file.name);
        }
      } else {
        _processImageFile(File(file.path!));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upload Invoice',
                  style: AppTextStyles.heading1,
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  'Upload an invoice image or PDF to analyze for forgery detection',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.gray600,
                  ),
                ),
              ],
            ).animate().slideX(duration: 300.ms),

            const SizedBox(height: AppSpacing.space8),

            // Upload Area
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Drag and Drop Area
                  UploadArea(
                    onFilesSelected: _handleFilesSelected,
                    isDragActive: _isDragOver,
                  ).animate().scale(duration: 400.ms, delay: 100.ms),

                  const SizedBox(height: AppSpacing.space6),

                  // Divider
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
                        child: Text(
                          'OR',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.gray500,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.space6),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pickFromGallery,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space4),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pickFromCamera,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
                          ),
                        ),
                      ),
                    ],
                  ).animate().slideY(duration: 300.ms, delay: 200.ms),

                  const SizedBox(height: AppSpacing.space4),

                  // File Picker Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Choose File (PDF, JPG, PNG)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
                      ),
                    ),
                  ).animate().slideY(duration: 300.ms, delay: 300.ms),

                  // Selected File Info
                  if (_selectedFilePath != null) ...[
                    const SizedBox(height: AppSpacing.space6),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.space4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(AppBorderRadius.radiusMd),
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppColors.primary),
                          const SizedBox(width: AppSpacing.space2),
                          Expanded(
                            child: Text(
                              'Selected: $_selectedFilePath',
                              style: AppTextStyles.body.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 300.ms),
                  ],

                  const SizedBox(height: AppSpacing.space8),

                  // Info Section
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.space6),
                    decoration: BoxDecoration(
                      color: AppColors.gray50,
                      borderRadius: BorderRadius.circular(AppBorderRadius.radiusMd),
                      border: Border.all(color: AppColors.gray200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, 
                                color: AppColors.info, size: 20),
                            const SizedBox(width: AppSpacing.space2),
                            Text(
                              'Supported Formats',
                              style: AppTextStyles.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.space3),
                        ...['PDF documents', 'JPG images', 'PNG images'].map(
                          (format) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.space1),
                            child: Row(
                              children: [
                                Icon(Icons.check, 
                                    color: AppColors.success, size: 16),
                                const SizedBox(width: AppSpacing.space2),
                                Text(format, style: AppTextStyles.bodySmall),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space3),
                        Text(
                          'Maximum file size: 10MB',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.gray500,
                          ),
                        ),
                      ],
                    ),
                  ).animate().slideY(duration: 300.ms, delay: 400.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
