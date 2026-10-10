import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';

/// Optimized, memory-safe thumbnail widget for files.
/// Never decodes full-resolution images into memory; enforces cacheWidth/cacheHeight limits.
class FileThumbnailWidget extends StatelessWidget {
  const FileThumbnailWidget({
    super.key,
    required this.file,
    this.size = 48.0,
    this.borderRadius = 8.0,
  });

  final FileEntity file;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (file.isDirectory) {
      return _buildContainer(
        color: AppColors.folderYellow.withValues(alpha: 0.15),
        child: Icon(Icons.folder_rounded, color: AppColors.folderYellow, size: size * 0.55),
      );
    }

    final ext = file.extension.toLowerCase().replaceAll('.', '');

    // 1. IMAGE: Optimized thumbnail with strict cacheWidth/cacheHeight to prevent OOM
    if (file.category == FileCategory.image) {
      final imgFile = File(file.path);
      return Image.file(
        imgFile,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Bound the decoded buffer. Only the width is given: with both set Flutter
        // decodes to that exact size and distorts non-square photos.
        cacheWidth: 160,
        errorBuilder: (_, __, ___) => _buildFallback(file.category.icon, file.category.color),
      );
    }

    // 2. VIDEO: Representative frame container with video badge
    if (file.category == FileCategory.video) {
      return _buildContainer(
        color: AppColors.typeVideo.withValues(alpha: 0.15),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.movie_rounded, color: AppColors.typeVideo, size: size * 0.5),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  ext.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 3. AUDIO: Sound waveform representation with audio badge
    if (file.category == FileCategory.audio) {
      return _buildContainer(
        color: AppColors.typeAudio.withValues(alpha: 0.15),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.headphones_rounded, color: AppColors.typeAudio, size: size * 0.5),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.typeAudio,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  ext.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 4. PDF: Distinct document preview badge
    if (ext == 'pdf') {
      return _buildContainer(
        color: Colors.red.withValues(alpha: 0.15),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 26),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'PDF',
                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 5. Office Documents: Format-specific previews
    if (ext == 'doc' || ext == 'docx') {
      return _buildBadgeContainer(
        color: Colors.blue.withValues(alpha: 0.15),
        icon: Icons.article_rounded,
        iconColor: Colors.blueAccent,
        label: 'DOC',
        labelColor: Colors.blueAccent,
      );
    }
    if (ext == 'xls' || ext == 'xlsx' || ext == 'csv') {
      return _buildBadgeContainer(
        color: Colors.green.withValues(alpha: 0.15),
        icon: Icons.table_chart_rounded,
        iconColor: Colors.green,
        label: ext.toUpperCase(),
        labelColor: Colors.green,
      );
    }
    if (ext == 'ppt' || ext == 'pptx') {
      return _buildBadgeContainer(
        color: Colors.deepOrange.withValues(alpha: 0.15),
        icon: Icons.slideshow_rounded,
        iconColor: Colors.deepOrange,
        label: 'PPT',
        labelColor: Colors.deepOrange,
      );
    }
    if (ext == 'xml') {
      return _buildBadgeContainer(
        color: Colors.purple.withValues(alpha: 0.15),
        icon: Icons.code_rounded,
        iconColor: Colors.purple,
        label: 'XML',
        labelColor: Colors.purple,
      );
    }
    if (ext == 'zip' || ext == 'rar' || ext == '7z' || ext == 'tar' || ext == 'gz') {
      return _buildBadgeContainer(
        color: AppColors.typeArchive.withValues(alpha: 0.15),
        icon: Icons.archive_rounded,
        iconColor: AppColors.typeArchive,
        label: ext.toUpperCase(),
        labelColor: AppColors.typeArchive,
      );
    }
    if (ext == 'apk') {
      return _buildBadgeContainer(
        color: AppColors.typeApk.withValues(alpha: 0.15),
        icon: Icons.android_rounded,
        iconColor: AppColors.typeApk,
        label: 'APK',
        labelColor: AppColors.typeApk,
      );
    }

    // Default category fallback
    return _buildFallback(file.category.icon, file.category.color);
  }

  Widget _buildContainer({required Color color, required Widget child}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color),
      child: Center(child: child),
    );
  }

  Widget _buildBadgeContainer({
    required Color color,
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color labelColor,
  }) {
    return Container(
      width: size,
      height: size,
      color: color,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, color: iconColor, size: size * 0.5),
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: labelColor,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallback(IconData icon, Color color) {
    return Container(
      width: size,
      height: size,
      color: color.withValues(alpha: 0.15),
      child: Center(
        child: Icon(icon, color: color, size: size * 0.55),
      ),
    );
  }
}
