import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Categories of files classified by FileZen.
enum FileCategory {
  image,
  video,
  audio,
  document,
  archive,
  apk,
  other;

  String get displayName => switch (this) {
        FileCategory.image => 'Images',
        FileCategory.video => 'Videos',
        FileCategory.audio => 'Audio',
        FileCategory.document => 'Documents',
        FileCategory.archive => 'Archives',
        FileCategory.apk => 'APKs',
        FileCategory.other => 'Other',
      };

  IconData get icon => switch (this) {
        FileCategory.image => Icons.image_rounded,
        FileCategory.video => Icons.movie_rounded,
        FileCategory.audio => Icons.headphones_rounded,
        FileCategory.document => Icons.description_rounded,
        FileCategory.archive => Icons.archive_rounded,
        FileCategory.apk => Icons.android_rounded,
        FileCategory.other => Icons.insert_drive_file_rounded,
      };

  Color get color => switch (this) {
        FileCategory.image => AppColors.typeImage,
        FileCategory.video => AppColors.typeVideo,
        FileCategory.audio => AppColors.typeAudio,
        FileCategory.document => AppColors.typeDocument,
        FileCategory.archive => AppColors.typeArchive,
        FileCategory.apk => AppColors.typeApk,
        FileCategory.other => AppColors.lightTextSecondary,
      };

  /// Resolves the category from extension and optional mime type.
  static FileCategory fromExtension(String ext, [String? mimeType]) {
    final cleanExt = ext.toLowerCase().replaceAll('.', '').trim();

    if (mimeType != null) {
      if (mimeType.startsWith('image/')) return FileCategory.image;
      if (mimeType.startsWith('video/')) return FileCategory.video;
      if (mimeType.startsWith('audio/')) return FileCategory.audio;
      if (mimeType.contains('pdf') || mimeType.contains('text') || mimeType.contains('document')) {
        return FileCategory.document;
      }
    }

    const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif', 'svg', 'tiff', 'raw', 'cr2', 'nef'};
    const videoExtensions = {'mp4', 'mkv', 'webm', 'mov', 'avi', 'wmv', 'flv', '3gp', 'm4v', 'ts'};
    const audioExtensions = {'mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg', 'wma', 'opus'};
    const documentExtensions = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'md', 'rtf', 'json', 'xml', 'html'};
    const archiveExtensions = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'targz', 'tgz', 'tbz2', 'txz', 'iso', 'z'};
    const apkExtensions = {'apk', 'xapk', 'apks'};

    if (imageExtensions.contains(cleanExt)) return FileCategory.image;
    if (videoExtensions.contains(cleanExt)) return FileCategory.video;
    if (audioExtensions.contains(cleanExt)) return FileCategory.audio;
    if (documentExtensions.contains(cleanExt)) return FileCategory.document;
    if (archiveExtensions.contains(cleanExt)) return FileCategory.archive;
    if (apkExtensions.contains(cleanExt)) return FileCategory.apk;

    return FileCategory.other;
  }
}
