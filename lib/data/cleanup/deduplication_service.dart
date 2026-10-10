import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../domain/models/cleanup_models.dart';
import '../../domain/models/deduplication_models.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/file_operation_models.dart';
import '../../domain/repositories/i_deduplication_service.dart';
import '../../domain/repositories/i_storage_repository.dart';
import '../../domain/repositories/i_trash_recovery_service.dart';
import '../database/app_database.dart';
import '../storage/file_walker.dart';
import '../storage/filesystem_storage_repository.dart';

/// Implementation of IDeduplicationService providing 3-tier duplicate detection,
/// similar-media heuristics, cleanup candidate generators, and safe execution.
class DeduplicationService implements IDeduplicationService {
  final AppDatabase db;
  final IStorageRepository storageRepo;
  final ITrashRecoveryService trashService;

  DeduplicationService({
    required this.db,
    required this.storageRepo,
    required this.trashService,
  });

  /// Gathers all available FileEntities from SQLite database or direct disk scan.
  Future<List<FileEntity>> _getAllFiles({List<String>? targetPaths}) async {
    final records = await db.select(db.fileRecords).get();

    if (records.isNotEmpty) {
      return records
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
    }

    // Index empty: walk explicitly requested roots only. Without roots the
    // automatic index supplies the data shortly; walking all shared storage
    // here duplicated the indexer's work.
    if (targetPaths == null) return const [];
    return FileWalker.files(targetPaths);
  }

  @override
  Future<List<DuplicateGroup>> scanExactDuplicates({
    List<String>? scanPaths,
    CancellationToken? cancellationToken,
    void Function(DuplicateScanProgress)? onProgress,
  }) async {
    final allFiles = await _getAllFiles(targetPaths: scanPaths);
    final totalCount = allFiles.length;

    onProgress?.call(DuplicateScanProgress(
      phaseDescription: 'Clustering files by exact size...',
      totalFiles: totalCount,
    ));

    // Tier 1: Group files by exact byte size (exclude 0-byte files)
    final sizeMap = <int, List<FileEntity>>{};
    for (final file in allFiles) {
      if (cancellationToken?.isCancelled == true) return [];
      if (file.size <= 0) continue;
      sizeMap.putIfAbsent(file.size, () => []).add(file);
    }

    // Retain only groups with 2 or more files of identical size
    final candidateGroups = sizeMap.values.where((list) => list.length >= 2).toList();
    final candidateCount = candidateGroups.fold<int>(0, (sum, g) => sum + g.length);

    onProgress?.call(DuplicateScanProgress(
      phaseDescription: 'Computing cryptographic checksums...',
      processedFiles: 0,
      totalFiles: candidateCount,
    ));

    // Tier 2: Checksum hashing for size-matched candidate groups
    final checksumGroups = <String, List<FileEntity>>{};
    int processedCandidates = 0;
    int foundGroups = 0;
    int potentialSavings = 0;

    for (final group in candidateGroups) {
      if (cancellationToken?.isCancelled == true) return [];

      for (final file in group) {
        if (cancellationToken?.isCancelled == true) return [];
        try {
          final hash = await storageRepo.calculateChecksum(file.path);
          checksumGroups.putIfAbsent(hash, () => []).add(file);
        } catch (e) {
          AppLogger.warning('Failed to compute checksum for ${file.path}: $e', 'DedupService');
        }

        processedCandidates++;
        if (processedCandidates % 10 == 0 || processedCandidates == candidateCount) {
          onProgress?.call(DuplicateScanProgress(
            phaseDescription: 'Analyzing cryptographic hashes ($processedCandidates/$candidateCount)...',
            processedFiles: processedCandidates,
            totalFiles: candidateCount,
            foundDuplicateGroups: foundGroups,
            potentialSavingsBytes: potentialSavings,
          ));
        }
      }
    }

    // Tier 3: Group synthesis and designation of primary file
    final duplicateResults = <DuplicateGroup>[];

    for (final entry in checksumGroups.entries) {
      final copies = entry.value;
      if (copies.length < 2) continue;

      // Sort copies by modifiedAt ascending: oldest file is considered the original/primary
      copies.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
      final primary = copies.first;
      final redundant = copies.sublist(1);

      final group = DuplicateGroup(
        checksum: entry.key,
        fileSize: primary.size,
        primaryFile: primary,
        duplicateFiles: redundant,
      );

      duplicateResults.add(group);
      foundGroups++;
      potentialSavings += group.recoverableSize;
    }

    // Sort duplicate groups descending by recoverable size (biggest savings first)
    duplicateResults.sort((a, b) => b.recoverableSize.compareTo(a.recoverableSize));

    onProgress?.call(DuplicateScanProgress(
      phaseDescription: 'Duplicate scan complete',
      processedFiles: candidateCount,
      totalFiles: candidateCount,
      foundDuplicateGroups: duplicateResults.length,
      potentialSavingsBytes: potentialSavings,
      isCompleted: true,
    ));

    return duplicateResults;
  }

  @override
  Future<List<FileEntity>> scanSimilarPhotos({
    List<String>? scanPaths,
    Duration burstWindow = const Duration(seconds: 5),
  }) async {
    final allFiles = await _getAllFiles(targetPaths: scanPaths);
    final images = allFiles.where((f) => f.category == FileCategory.image).toList();

    // Sort images chronologically
    images.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));

    final similarPhotos = <FileEntity>{};

    for (int i = 0; i < images.length - 1; i++) {
      final current = images[i];
      final next = images[i + 1];

      // Signal 1: Burst window (taken within burstWindow seconds)
      final timeDiff = next.modifiedAt.difference(current.modifiedAt).abs();
      final isBurstTime = timeDiff <= burstWindow;

      // Signal 2: Identical directory and near-identical file sizes (within 3%)
      final sameDir = p.dirname(current.path) == p.dirname(next.path);
      final sizeDelta = (current.size - next.size).abs();
      final sizeRatio = current.size > 0 ? sizeDelta / current.size : 1.0;
      final isSimilarSize = sameDir && sizeRatio < 0.03;

      // Signal 3: Burst naming pattern like IMG_..._01.jpg, IMG_..._02.jpg
      final currentBase = p.basenameWithoutExtension(current.name);
      final nextBase = p.basenameWithoutExtension(next.name);
      final isBurstNaming = currentBase.length > 5 &&
          nextBase.length > 5 &&
          currentBase.substring(0, currentBase.length - 2) ==
              nextBase.substring(0, nextBase.length - 2);

      if (isBurstTime || (isSimilarSize && isBurstNaming)) {
        similarPhotos.add(current);
        similarPhotos.add(next);
      }
    }

    return similarPhotos.toList();
  }

  @override
  Future<List<FileEntity>> scanBlurryPhotos({List<String>? scanPaths}) async {
    final allFiles = await _getAllFiles(targetPaths: scanPaths);
    final images = allFiles.where((f) => f.category == FileCategory.image).toList();

    // Heuristics:
    // 1. Files labeled 'blur', 'corrupt', 'thumb', 'sample' in name
    // 2. Camera photos that are suspiciously tiny (< 30 KB) where typical photos are > 1 MB
    final results = <FileEntity>[];
    for (final img in images) {
      final lowerName = img.name.toLowerCase();
      final isBlurryLabel = lowerName.contains('blur') || lowerName.contains('lowres');
      final isTinyPhoto = img.size < 30 * 1024 &&
          (lowerName.startsWith('img_') || lowerName.startsWith('dsc_') || lowerName.startsWith('photo_'));

      if (isBlurryLabel || isTinyPhoto) {
        results.add(img);
      }
    }
    return results;
  }

  @override
  Future<List<FileEntity>> scanLargeFiles({
    List<String>? scanPaths,
    int minSizeBytes = 50 * 1024 * 1024,
  }) async {
    final allFiles = await _getAllFiles(targetPaths: scanPaths);
    final large = allFiles.where((f) => f.size >= minSizeBytes).toList();
    large.sort((a, b) => b.size.compareTo(a.size));
    return large;
  }

  @override
  Future<List<FileEntity>> scanOldApks({
    List<String>? scanPaths,
    int daysOld = 7,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysOld));
    final allFiles = await _getAllFiles(targetPaths: scanPaths);
    return allFiles
        .where((f) =>
            (f.extension.toLowerCase() == '.apk' || f.category == FileCategory.apk) &&
            f.modifiedAt.isBefore(cutoff))
        .toList();
  }

  @override
  Future<List<FileEntity>> scanOldScreenshots({
    List<String>? scanPaths,
    int daysOld = 14,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysOld));
    final allFiles = await _getAllFiles(targetPaths: scanPaths);
    return allFiles.where((f) {
      if (f.category != FileCategory.image) return false;
      final lowerPath = f.path.toLowerCase();
      final isScreenshot = lowerPath.contains('screenshot') ||
          f.name.toLowerCase().startsWith('screen_') ||
          f.name.toLowerCase().startsWith('screencap');
      return isScreenshot && f.modifiedAt.isBefore(cutoff);
    }).toList();
  }

  @override
  Future<List<FileEntity>> scanRepeatedDownloads({List<String>? scanPaths}) async {
    final allFiles = await _getAllFiles(targetPaths: scanPaths);
    // Regex matching repeated copy suffixes like (1), (2), _copy, -copy
    final regex = RegExp(r'(\s*[\(_-]\s*\d+\s*[\)]?|_copy|-copy)\.[a-zA-Z0-9]+$', caseSensitive: false);

    return allFiles.where((f) {
      final inDownload = f.path.toLowerCase().contains('download');
      final matchesPattern = regex.hasMatch(f.name);
      return matchesPattern || (inDownload && f.name.contains('(1)'));
    }).toList();
  }

  @override
  Future<List<String>> scanEmptyFolders({List<String>? scanPaths}) async {
    final locations = await storageRepo.getStorageLocations();
    final roots = scanPaths ?? FilesystemStorageRepository.distinctRoots(locations.map((l) => l.path));
    return FileWalker.emptyFolders(roots);
  }

  @override
  Future<List<FileEntity>> scanDormantFiles({
    List<String>? scanPaths,
    int daysInactive = 90,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysInactive));
    final allFiles = await _getAllFiles(targetPaths: scanPaths);
    return allFiles
        .where((f) => !f.isDirectory && f.modifiedAt.isBefore(cutoff))
        .toList();
  }

  @override
  Future<List<FileEntity>> scanOldRecordings({
    List<String>? scanPaths,
    int daysOld = 30,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysOld));
    final allFiles = await _getAllFiles(targetPaths: scanPaths);
    return allFiles.where((f) {
      if (f.category != FileCategory.audio) return false;
      final lower = f.path.toLowerCase();
      final isRecording = lower.contains('recording') ||
          lower.contains('voice') ||
          lower.contains('call') ||
          f.extension.toLowerCase() == '.amr' ||
          f.extension.toLowerCase() == '.m4a';
      return isRecording && f.modifiedAt.isBefore(cutoff);
    }).toList();
  }

  @override
  Future<List<CleanupCandidateGroup>> scanAllCleanupOpportunities({
    List<String>? scanPaths,
  }) async {
    final opportunities = <CleanupCandidateGroup>[];

    // 1. Exact duplicates
    final dupes = await scanExactDuplicates(scanPaths: scanPaths);
    final redundantDupeFiles = dupes.expand((g) => g.duplicateFiles).toList();
    if (redundantDupeFiles.isNotEmpty) {
      final size = dupes.fold<int>(0, (sum, g) => sum + g.recoverableSize);
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.exactDuplicates,
        title: CleanupCategoryType.exactDuplicates.title,
        description: CleanupCategoryType.exactDuplicates.description,
        items: redundantDupeFiles,
        totalSize: size,
      ));
    }

    // 2. Similar & Burst photos
    final similar = await scanSimilarPhotos(scanPaths: scanPaths);
    if (similar.isNotEmpty) {
      final size = similar.fold<int>(0, (sum, f) => sum + f.size);
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.similarPhotos,
        title: CleanupCategoryType.similarPhotos.title,
        description: CleanupCategoryType.similarPhotos.description,
        items: similar,
        totalSize: size,
      ));
    }

    // 3. Blurry Photos
    final blurry = await scanBlurryPhotos(scanPaths: scanPaths);
    if (blurry.isNotEmpty) {
      final size = blurry.fold<int>(0, (sum, f) => sum + f.size);
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.blurryPhotos,
        title: CleanupCategoryType.blurryPhotos.title,
        description: CleanupCategoryType.blurryPhotos.description,
        items: blurry,
        totalSize: size,
      ));
    }

    // 4. Large Files (> 50 MB)
    final large = await scanLargeFiles(scanPaths: scanPaths);
    if (large.isNotEmpty) {
      final size = large.fold<int>(0, (sum, f) => sum + f.size);
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.largeFiles,
        title: CleanupCategoryType.largeFiles.title,
        description: CleanupCategoryType.largeFiles.description,
        items: large,
        totalSize: size,
      ));
    }

    // 5. Old APKs
    final oldApks = await scanOldApks(scanPaths: scanPaths);
    if (oldApks.isNotEmpty) {
      final size = oldApks.fold<int>(0, (sum, f) => sum + f.size);
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.oldApks,
        title: CleanupCategoryType.oldApks.title,
        description: CleanupCategoryType.oldApks.description,
        items: oldApks,
        totalSize: size,
      ));
    }

    // 6. Old Screenshots
    final oldScreenshots = await scanOldScreenshots(scanPaths: scanPaths);
    if (oldScreenshots.isNotEmpty) {
      final size = oldScreenshots.fold<int>(0, (sum, f) => sum + f.size);
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.oldScreenshots,
        title: CleanupCategoryType.oldScreenshots.title,
        description: CleanupCategoryType.oldScreenshots.description,
        items: oldScreenshots,
        totalSize: size,
      ));
    }

    // 7. Repeated Downloads
    final repeated = await scanRepeatedDownloads(scanPaths: scanPaths);
    if (repeated.isNotEmpty) {
      final size = repeated.fold<int>(0, (sum, f) => sum + f.size);
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.repeatedDownloads,
        title: CleanupCategoryType.repeatedDownloads.title,
        description: CleanupCategoryType.repeatedDownloads.description,
        items: repeated,
        totalSize: size,
      ));
    }

    // 8. Empty Folders
    final emptyFolders = await scanEmptyFolders(scanPaths: scanPaths);
    if (emptyFolders.isNotEmpty) {
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.emptyFolders,
        title: CleanupCategoryType.emptyFolders.title,
        description: CleanupCategoryType.emptyFolders.description,
        items: emptyFolders
            .map((p) => FileEntity(
                  id: p,
                  path: p,
                  name: p.split(Platform.pathSeparator).last,
                  extension: '',
                  size: 0,
                  modifiedAt: DateTime.now(),
                  createdAt: DateTime.now(),
                  isDirectory: true,
                  category: FileCategory.other,
                ))
            .toList(),
        totalSize: 0,
      ));
    }

    // 9. Dormant / Never-Opened Files
    final dormant = await scanDormantFiles(scanPaths: scanPaths);
    if (dormant.isNotEmpty) {
      final size = dormant.fold<int>(0, (sum, f) => sum + f.size);
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.dormantFiles,
        title: CleanupCategoryType.dormantFiles.title,
        description: CleanupCategoryType.dormantFiles.description,
        items: dormant,
        totalSize: size,
      ));
    }

    // 10. Old Recordings
    final recordings = await scanOldRecordings(scanPaths: scanPaths);
    if (recordings.isNotEmpty) {
      final size = recordings.fold<int>(0, (sum, f) => sum + f.size);
      opportunities.add(CleanupCandidateGroup(
        type: CleanupCategoryType.oldRecordings,
        title: CleanupCategoryType.oldRecordings.title,
        description: CleanupCategoryType.oldRecordings.description,
        items: recordings,
        totalSize: size,
      ));
    }

    return opportunities;
  }

  @override
  Future<CleanupExecutionResult> executeCleanup(CleanupExecutionPlan plan) async {
    final failed = <String>[];
    int cleaned = 0;
    int freed = 0;

    // Phase 1: Handle files (via Trash or Hard Delete)
    if (plan.selectedFiles.isNotEmpty) {
      if (plan.moveToTrash) {
        final res = await trashService.batchMoveToTrash(plan.selectedFiles);
        final trashedItems = res.dataOrNull;
        if (res.isSuccess && trashedItems != null) {
          cleaned += trashedItems.length;
          freed += trashedItems.fold<int>(0, (sum, i) => sum + i.size);
        } else {
          failed.addAll(plan.selectedFiles.map((f) => f.path));
        }
      } else {
        // Direct hard delete
        for (final file in plan.selectedFiles) {
          final res = await storageRepo.delete(file.path);
          if (res.isSuccess) {
            cleaned++;
            freed += file.size;
          } else {
            failed.add(file.path);
          }
        }
      }
    }

    // Phase 2: Handle empty folders
    if (plan.emptyFolderPaths.isNotEmpty) {
      final deletedCount = await deleteEmptyFolders(plan.emptyFolderPaths);
      cleaned += deletedCount;
    }

    // Phase 3: Remove cleaned records from Drift database
    try {
      final cleanedPaths = plan.selectedFiles.map((f) => f.path).toList();
      await (db.delete(db.fileRecords)..where((t) => t.path.isIn(cleanedPaths))).go();
    } catch (_) {}

    AppLogger.info(
      'Executed cleanup: $cleaned items, $freed bytes freed, moved to trash: ${plan.moveToTrash}',
      'DedupService',
    );

    return CleanupExecutionResult(
      success: failed.isEmpty,
      itemsCleaned: cleaned,
      bytesFreed: freed,
      movedToTrash: plan.moveToTrash,
      failedPaths: failed,
    );
  }

  @override
  Future<int> deleteEmptyFolders(List<String> folderPaths) async {
    int deleted = 0;
    for (final path in folderPaths) {
      try {
        final dir = Directory(path);
        if (await dir.exists() && dir.listSync().isEmpty) {
          await dir.delete();
          deleted++;
        }
      } catch (e) {
        AppLogger.warning('Failed to delete empty folder $path: $e', 'DedupService');
      }
    }
    return deleted;
  }
}
