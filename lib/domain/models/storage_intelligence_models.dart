import 'file_category.dart';

/// Real capacity of the shared-storage volume, measured by the OS (Android `StatFs`).
///
/// This is the only source for "device storage used/free". It is a different
/// metric from the total size of files FileZen has indexed (see
/// [StorageOverview.indexedBytes]); the two must never be mixed in one ratio.
class DeviceStorageStats {
  final int totalBytes;
  final int freeBytes;
  final DateTime measuredAt;

  const DeviceStorageStats({
    required this.totalBytes,
    required this.freeBytes,
    required this.measuredAt,
  });

  int get usedBytes => totalBytes > freeBytes ? totalBytes - freeBytes : 0;

  /// Used share of the volume, 0.0–1.0.
  double get usedRatio => usedRatioOf(usedBytes, totalBytes);

  /// The one rounding rule every screen uses for the "% used" label.
  int get usedPercentLabel => percentLabel(usedRatio);

  static double usedRatioOf(int used, int total) =>
      total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;

  /// Whole-number percentage, rounded half up (35.9% -> 36%).
  static int percentLabel(double ratio) => (ratio * 100).round().clamp(0, 100);
}

/// Aggregated breakdown of device storage and category occupancy.
///
/// [totalBytes], [usedBytes] and [freeBytes] describe the device volume and are
/// 0 when the device could not be measured ([hasDeviceTotals] is false).
/// [categorySizes] / [categoryCounts] describe indexed files only.
class StorageOverview {
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final Map<FileCategory, int> categorySizes;
  final Map<FileCategory, int> categoryCounts;
  final bool hasDeviceTotals;

  const StorageOverview({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.categorySizes,
    required this.categoryCounts,
    this.hasDeviceTotals = true,
  });

  /// Ratio of used bytes to total bytes (0.0 to 1.0).
  double get usedRatio => DeviceStorageStats.usedRatioOf(usedBytes, totalBytes);

  /// Percentage of used bytes (0 to 100).
  double get usedPercentage => usedRatio * 100.0;

  /// Same rounding as the Home card ([DeviceStorageStats.percentLabel]).
  int get usedPercentLabel => DeviceStorageStats.percentLabel(usedRatio);

  /// Total size of all indexed files (sum of the category sizes).
  int get indexedBytes => categorySizes.values.fold(0, (sum, v) => sum + v);

  /// Number of indexed files.
  int get indexedFileCount => categoryCounts.values.fold(0, (sum, v) => sum + v);

  /// Device usage not explained by indexed files: system, apps, app data,
  /// hidden/`Android/` folders and anything not indexed yet.
  int get unindexedUsedBytes =>
      usedBytes > indexedBytes ? usedBytes - indexedBytes : 0;

  /// Returns size in bytes for a specific category.
  int sizeForCategory(FileCategory category) => categorySizes[category] ?? 0;

  /// Returns file count for a specific category.
  int countForCategory(FileCategory category) => categoryCounts[category] ?? 0;
}

/// Storage consumption data for a specific directory.
class FolderStorageItem {
  final String path;
  final String name;
  final int sizeBytes;
  final int fileCount;
  final double percentageOfTotal;

  const FolderStorageItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.fileCount,
    this.percentageOfTotal = 0.0,
  });

  FolderStorageItem copyWith({
    String? path,
    String? name,
    int? sizeBytes,
    int? fileCount,
    double? percentageOfTotal,
  }) {
    return FolderStorageItem(
      path: path ?? this.path,
      name: name ?? this.name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      fileCount: fileCount ?? this.fileCount,
      percentageOfTotal: percentageOfTotal ?? this.percentageOfTotal,
    );
  }
}

/// Historical snapshot point tracking storage usage over time.
class StorageTrendPoint {
  final DateTime timestamp;
  final int usedBytes;
  final int totalBytes;
  final int changeDeltaBytes;

  const StorageTrendPoint({
    required this.timestamp,
    required this.usedBytes,
    required this.totalBytes,
    this.changeDeltaBytes = 0,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'usedBytes': usedBytes,
        'totalBytes': totalBytes,
        'changeDeltaBytes': changeDeltaBytes,
      };

  factory StorageTrendPoint.fromJson(Map<String, dynamic> json) => StorageTrendPoint(
        timestamp: DateTime.parse(json['timestamp'] as String),
        usedBytes: json['usedBytes'] as int,
        totalBytes: json['totalBytes'] as int,
        changeDeltaBytes: (json['changeDeltaBytes'] as int?) ?? 0,
      );
}
