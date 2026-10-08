import 'file_category.dart';

/// Aggregated breakdown of device storage and category occupancy.
class StorageOverview {
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final Map<FileCategory, int> categorySizes;
  final Map<FileCategory, int> categoryCounts;

  const StorageOverview({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.categorySizes,
    required this.categoryCounts,
  });

  /// Ratio of used bytes to total bytes (0.0 to 1.0).
  double get usedRatio => totalBytes > 0 ? (usedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  /// Percentage of used bytes (0 to 100).
  double get usedPercentage => usedRatio * 100.0;

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
