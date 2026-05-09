import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_border_radius.dart';

class UploadArea extends StatelessWidget {
  final Function(List<PlatformFile>) onFilesSelected;
  final bool isDragActive;
  final String? title;
  final String? subtitle;

  const UploadArea({
    super.key,
    required this.onFilesSelected,
    this.isDragActive = false,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        );
        
        if (result != null) {
          onFilesSelected(result.files);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.space12),
        decoration: BoxDecoration(
          color: isDragActive ? AppColors.primaryLight : Colors.white,
          border: Border.all(
            color: isDragActive ? AppColors.primary : AppColors.gray300,
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(AppBorderRadius.radiusMd),
        ),
        child: Column(
          children: [
            Icon(
              Icons.upload_file,
              size: 48,
              color: isDragActive ? AppColors.primary : AppColors.gray400,
            ),
            const SizedBox(height: AppSpacing.space4),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: AppTextStyles.body.copyWith(
                  color: isDragActive ? AppColors.primary : AppColors.gray700,
                ),
                children: [
                  TextSpan(text: title ?? 'Drop files here or '),
                  TextSpan(
                    text: 'browse',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              subtitle ?? 'Supports PDF, JPG, PNG (max 10MB per file)',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
