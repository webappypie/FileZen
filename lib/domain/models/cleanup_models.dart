import 'package:flutter/material.dart';
import 'file_entity.dart';

/// Categories of cleanup candidates supported by FileZen.
enum CleanupCategoryType {
  exactDuplicates(
    'Exact Duplicate Files',
    'Bit-for-bit identical files across different folders.',
    Icons.copy_all_rounded,
  ),
  similarPhotos(
    'Similar & Burst Photos',
    'Photos captured in quick succession or with identical framing.',
    Icons.photo_library_outlined,
  ),
  blurryPhotos(
    'Blurry & Low-Quality Media',
    'Low-resolution images or unclear shots.',
    Icons.blur_on_rounded,
  ),
  largeFiles(
    'Large Files (> 50 MB)',
    'High-resolution videos, large archives, and offline caches.',
    Icons.donut_large_rounded,
  ),
  oldApks(
    'Old APK Installers',
    'Package installer files lingering in Downloads folder.',
    Icons.android_rounded,
  ),
  oldScreenshots(
    'Old Screenshots',
    'Screen captures older than 14 days.',
    Icons.screenshot_monitor_rounded,
  ),
  repeatedDownloads(
    'Repeated Downloads',
    'Duplicate downloaded files with copy suffixes like (1), (2).',
    Icons.download_done_rounded,
  ),
  emptyFolders(
    'Empty Folders',
    'Directories containing no files or subfolders.',
    Icons.folder_off_outlined,
  ),
  dormantFiles(
    'Never-Opened & Dormant Files',
    'Files untouched for over 90 days.',
    Icons.history_toggle_off_rounded,
  ),
  oldRecordings(
    'Old Voice Recordings',
    'Audio voice notes and clips older than 30 days.',
    Icons.mic_none_rounded,
  );

  final String title;
  final String description;
  final IconData icon;

  const CleanupCategoryType(this.title, this.description, this.icon);
}

/// A cluster of cleanup candidates belonging to a specific category.
class CleanupCandidateGroup {
  final CleanupCategoryType type;
  final String title;
  final String description;
  final List<FileEntity> items;
  final int totalSize;

  const CleanupCandidateGroup({
    required this.type,
    required this.title,
    required this.description,
    required this.items,
    required this.totalSize,
  });

  int get itemCount => items.length;
}

/// Plan describing files selected for cleanup before confirmation.
class CleanupExecutionPlan {
  final List<FileEntity> selectedFiles;
  final List<String> emptyFolderPaths;
  final int totalBytesToFree;
  final bool moveToTrash;

  const CleanupExecutionPlan({
    required this.selectedFiles,
    this.emptyFolderPaths = const [],
    required this.totalBytesToFree,
    this.moveToTrash = true,
  });

  int get totalItemCount => selectedFiles.length + emptyFolderPaths.length;
}

/// Result of executing a cleanup plan.
class CleanupExecutionResult {
  final bool success;
  final int itemsCleaned;
  final int bytesFreed;
  final bool movedToTrash;
  final List<String> failedPaths;
  final String? errorMessage;

  const CleanupExecutionResult({
    required this.success,
    required this.itemsCleaned,
    required this.bytesFreed,
    required this.movedToTrash,
    this.failedPaths = const [],
    this.errorMessage,
  });

  bool get hasErrors => failedPaths.isNotEmpty || errorMessage != null;
}
