import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/storage_intelligence_models.dart';
import '../../domain/repositories/i_storage_hygiene_service.dart';
import '../../domain/repositories/i_storage_repository.dart';
import '../database/app_database.dart';

/// Service implementing storage intelligence calculations and trend tracking.
class StorageHygieneService implements IStorageHygieneService {
  final AppDatabase db;
  final IStorageRepository storageRepo;
  final String? customTrendFilePath;

  StorageHygieneService({
    required this.db,
    required this.storageRepo,
    this.customTrendFilePath,
  });

  Future<File> _getTrendsFile() async {
    if (customTrendFilePath != null) {
      final file = File(customTrendFilePath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, 'storage_trends.json'));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  /// Device totals come from [deviceStats] (the OS measurement shared with the
  /// Home card); category totals come from the index only. When the device
  /// cannot be measured the totals are 0 and [StorageOverview.hasDeviceTotals]
  /// is false — no nominal capacity is ever substituted.
  @override
  Future<StorageOverview> getStorageOverview({
    List<String>? targetPaths,
    DeviceStorageStats? deviceStats,
  }) async {
    final categorySizes = <FileCategory, int>{
      for (final cat in FileCategory.values) cat: 0,
    };
    final categoryCounts = <FileCategory, int>{
      for (final cat in FileCategory.values) cat: 0,
    };

    // One aggregate query instead of loading every row into memory.
    final rows = await db.customSelect(
      'SELECT category, COUNT(*) AS c, COALESCE(SUM(size), 0) AS s '
      'FROM file_records GROUP BY category',
      readsFrom: {db.fileRecords},
    ).get();
    for (final row in rows) {
      final cat = categoryFromDisplayName(row.readNullable<String>('category'));
      categorySizes[cat] = categorySizes[cat]! + row.read<int>('s');
      categoryCounts[cat] = categoryCounts[cat]! + row.read<int>('c');
    }

    final stats = deviceStats;
    return StorageOverview(
      totalBytes: stats?.totalBytes ?? 0,
      usedBytes: stats?.usedBytes ?? 0,
      freeBytes: stats?.freeBytes ?? 0,
      categorySizes: categorySizes,
      categoryCounts: categoryCounts,
      hasDeviceTotals: stats != null,
    );
  }

  /// Maps the `category` column (a [FileCategory.displayName]) back to the enum.
  static FileCategory categoryFromDisplayName(String? name) {
    for (final cat in FileCategory.values) {
      if (cat.displayName == name) return cat;
    }
    return FileCategory.other;
  }

  /// Folder totals of indexed files, aggregated in SQL (the parent folder is the
  /// path up to its last '/').
  @override
  Future<List<FolderStorageItem>> getTopFolders({
    List<String>? targetPaths,
    int limit = 10,
  }) async {
    const folderExpr = "rtrim(path, replace(path, '/', ''))";
    final rows = await db.customSelect(
      'SELECT $folderExpr AS folder, COUNT(*) AS c, COALESCE(SUM(size), 0) AS s '
      'FROM file_records GROUP BY folder ORDER BY s DESC LIMIT ?',
      variables: [Variable.withInt(limit)],
      readsFrom: {db.fileRecords},
    ).get();
    final totalRow = await db.customSelect(
      'SELECT COALESCE(SUM(size), 0) AS s FROM file_records',
      readsFrom: {db.fileRecords},
    ).getSingle();
    final total = totalRow.read<int>('s');
    final denominator = total > 0 ? total : 1;

    return rows.map((row) {
      var folder = row.read<String>('folder');
      if (folder.length > 1 && folder.endsWith('/')) {
        folder = folder.substring(0, folder.length - 1);
      }
      final size = row.read<int>('s');
      final name = p.basename(folder);
      return FolderStorageItem(
        path: folder,
        name: name.isEmpty ? folder : name,
        sizeBytes: size,
        fileCount: row.read<int>('c'),
        percentageOfTotal: (size / denominator * 100.0).clamp(0.0, 100.0),
      );
    }).toList();
  }

  @override
  Future<List<FileEntity>> getLargestFiles({
    List<String>? targetPaths,
    int limit = 20,
    int minSizeBytes = 50 * 1024 * 1024,
  }) async {
    final query = db.select(db.fileRecords)
      ..orderBy([(t) => OrderingTerm.desc(t.size)])
      ..limit(limit);
    final records = await query.get();

    final entities = records
        .map((r) => FileEntity(
              id: r.id,
              path: r.path,
              name: r.name,
              extension: r.extension,
              size: r.size.toInt(),
              modifiedAt: r.modifiedAt,
              createdAt: r.createdAt,
              isDirectory: false,
              mimeType: r.mimeType,
              category: FileCategory.fromExtension(r.extension, r.mimeType),
            ))
        .toList();

    // Prefer files above the threshold; if none qualify show the largest anyway.
    final aboveThreshold = entities.where((e) => e.size >= minSizeBytes).toList();
    return aboveThreshold.isNotEmpty ? aboveThreshold : entities;
  }

  @override
  Future<List<StorageTrendPoint>> getStorageTrends() async {
    try {
      final file = await _getTrendsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
          final points = jsonList
              .map((item) => StorageTrendPoint.fromJson(item as Map<String, dynamic>))
              .toList();
          if (points.isNotEmpty) {
            points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            return points;
          }
        }
      }
    } catch (e) {
      AppLogger.warning('Failed to load storage trends: $e', 'StorageHygiene');
    }

    // No history recorded yet: report none rather than inventing points.
    return const [];
  }

  /// Minimum spacing between recorded trend points.
  static const snapshotInterval = Duration(hours: 12);

  /// Appends a point of *device* usage. Skipped when the device cannot be
  /// measured or when the previous point is newer than [snapshotInterval].
  @override
  Future<void> recordCurrentStorageSnapshot({
    List<String>? targetPaths,
    DeviceStorageStats? deviceStats,
  }) async {
    final stats = deviceStats;
    if (stats == null) return;
    try {
      final trends = await getStorageTrends();
      if (trends.isNotEmpty &&
          stats.measuredAt.difference(trends.last.timestamp) < snapshotInterval) {
        return;
      }

      final delta = trends.isNotEmpty ? stats.usedBytes - trends.last.usedBytes : 0;
      final newPoint = StorageTrendPoint(
        timestamp: stats.measuredAt,
        usedBytes: stats.usedBytes,
        totalBytes: stats.totalBytes,
        changeDeltaBytes: delta,
      );

      final updated = [...trends, newPoint];
      // Keep up to 60 historical points
      final trimmed = updated.length > 60 ? updated.sublist(updated.length - 60) : updated;

      final file = await _getTrendsFile();
      final jsonStr = jsonEncode(trimmed.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonStr, flush: true);
      AppLogger.info('Recorded storage snapshot', 'StorageHygiene');
    } catch (e) {
      AppLogger.error('Failed to record storage snapshot: $e', 'StorageHygiene');
    }
  }
}
