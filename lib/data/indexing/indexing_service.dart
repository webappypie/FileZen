import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/file_operation_models.dart';
import '../../domain/models/indexing_progress.dart';
import '../../domain/repositories/i_indexing_service.dart';
import '../../domain/repositories/i_storage_repository.dart';
import '../database/app_database.dart';
import '../storage/filesystem_storage_repository.dart';
import 'text_extractor.dart';

/// Implementation of IIndexingService for background incremental indexing.
class IndexingService implements IIndexingService {
  final AppDatabase db;
  final IStorageRepository storageRepo;
  final TextExtractor _textExtractor;

  final StreamController<IndexingProgress> _progressController =
      StreamController<IndexingProgress>.broadcast();

  IndexingProgress _currentProgress = const IndexingProgress();
  bool _isPaused = false;
  Timer? _backgroundSyncTimer;

  /// Asked before and during OCR; returning false defers OCR to a later run.
  final Future<bool> Function()? heavyWorkAllowed;

  IndexingService({
    required this.db,
    required this.storageRepo,
    TextExtractor? textExtractor,
    this.heavyWorkAllowed,
  }) : _textExtractor = textExtractor ?? TextExtractor();

  @override
  Stream<IndexingProgress> get progressStream => _progressController.stream;

  @override
  IndexingProgress get currentProgress => _currentProgress;

  bool get isPaused => _isPaused;

  @override
  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    // Only a running scan has anything to report as paused.
    if (_currentProgress.isRunning) {
      _updateProgress(_currentProgress.copyWith(status: IndexingStatus.paused), null);
    }
  }

  @override
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    if (_currentProgress.status == IndexingStatus.paused) {
      _updateProgress(_currentProgress.copyWith(status: IndexingStatus.indexing), null);
    }
  }

  @override
  void startPeriodicBackgroundSync({Duration interval = const Duration(minutes: 5)}) {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = Timer.periodic(interval, (_) async {
      if (!_currentProgress.isRunning && !_isPaused) {
        await runIndexScan();
      }
    });
  }

  @override
  void stopPeriodicBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
  }

  void _updateProgress(IndexingProgress progress, void Function(IndexingProgress)? onProgress) {
    _currentProgress = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
    onProgress?.call(progress);
  }

  /// Two passes over the device:
  ///
  /// 1. Discovery + metadata/text indexing. Only new or changed files are
  ///    processed (compared against one preloaded path map, not a query per
  ///    file); writes are batched per transaction. Entries whose files are gone
  ///    are pruned, except under folders that could not be read.
  /// 2. OCR for images whose current version has not been recognised yet
  ///    (tracked in `ocr_state`). Deferred — left pending for the next run — when
  ///    [heavyWorkAllowed] reports battery saver / low battery / thermal stress.
  @override
  Future<Result<IndexingProgress>> runIndexScan({
    List<String>? targetPaths,
    CancellationToken? cancellationToken,
    void Function(IndexingProgress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    bool cancelled() => cancellationToken?.isCancelled == true;

    IndexingProgress cancelledProgress() => _currentProgress.copyWith(
          status: IndexingStatus.cancelled,
          elapsedTime: stopwatch.elapsed,
        );

    try {
      List<String> roots = targetPaths ?? [];
      if (roots.isEmpty) {
        final locations = await storageRepo.getStorageLocations();
        roots = locations.map((l) => l.path).toList();
      }
      // "Downloads" lives inside "Internal Storage": walk it once.
      roots = FilesystemStorageRepository.distinctRoots(roots);

      if (roots.isEmpty) {
        _updateProgress(
          const IndexingProgress(status: IndexingStatus.completed),
          onProgress,
        );
        return Result.success(_currentProgress);
      }

      _updateProgress(
        IndexingProgress(
          status: IndexingStatus.scanning,
          elapsedTime: stopwatch.elapsed,
        ),
        onProgress,
      );

      final filesToProcess = <FileEntity>[];
      final unreadableDirs = <String>[];
      final scannedRoots = <String>[];
      for (final root in roots) {
        if (cancelled()) break;
        final dir = Directory(root);
        if (!await dir.exists()) continue;
        scannedRoots.add(root);
        await _discoverFiles(dir, filesToProcess, unreadableDirs, cancellationToken);
      }

      if (cancelled()) {
        _updateProgress(cancelledProgress(), onProgress);
        return Result.failure(const OperationCancelledError());
      }

      // Everything already indexed, keyed by path (one query).
      final existingByPath = <String, List<FileRecord>>{};
      for (final row in await db.select(db.fileRecords).get()) {
        (existingByPath[row.path] ??= []).add(row);
      }

      _updateProgress(
        IndexingProgress(
          status: IndexingStatus.indexing,
          totalFilesDiscovered: filesToProcess.length,
          elapsedTime: stopwatch.elapsed,
        ),
        onProgress,
      );

      int indexed = 0;
      int skipped = 0;
      int errors = 0;

      const batchSize = 25;
      for (var i = 0; i < filesToProcess.length; i += batchSize) {
        if (cancelled()) {
          _updateProgress(cancelledProgress(), onProgress);
          return Result.failure(const OperationCancelledError());
        }
        await _waitWhilePaused(cancellationToken);

        final end = (i + batchSize < filesToProcess.length) ? i + batchSize : filesToProcess.length;
        final batch = filesToProcess.sublist(i, end);
        final pending = <(FileEntity, String, List<String>)>[];

        for (final file in batch) {
          final existingRows = existingByPath[file.path] ?? const <FileRecord>[];
          // More than one row for a path is a leftover from an earlier edit
          // (the row id embeds the size): treat it as stale and replace them all.
          final existing = existingRows.length == 1 ? existingRows.single : null;
          if (existing != null && _isUnchanged(existing, file)) {
            skipped++;
            continue;
          }
          try {
            final extracted = await _textExtractor.extractContent(file, includeOcr: false);
            pending.add((file, extracted, existingRows.map((r) => r.id).toList()));
          } catch (e) {
            AppLogger.warning('Error reading file for index: $e', 'IndexingService');
            errors++;
          }
        }

        if (pending.isNotEmpty) {
          try {
            await db.transaction(() async {
              for (final (file, extracted, replaceIds) in pending) {
                await _writeIndexRecord(file, extracted, replaceIds: replaceIds);
              }
            });
            indexed += pending.length;
          } catch (e) {
            AppLogger.warning('Error writing index batch: $e', 'IndexingService');
            errors += pending.length;
          }
        }

        final isLast = end == filesToProcess.length;
        if (pending.isNotEmpty || isLast || (i ~/ batchSize) % 40 == 0) {
          _updateProgress(
            _currentProgress.copyWith(
              status: IndexingStatus.indexing,
              indexedCount: indexed,
              skippedCount: skipped,
              errorCount: errors,
              currentPath: batch.isNotEmpty ? batch.last.path : null,
              elapsedTime: stopwatch.elapsed,
            ),
            onProgress,
          );
        }

        // Yield so the UI keeps priority: a short pause after real work, a bare
        // event-loop turn after batches that were all unchanged.
        await Future<void>.delayed(pending.isNotEmpty ? const Duration(milliseconds: 2) : Duration.zero);
      }

      // Prune entries whose files were deleted outside FileZen.
      final discoveredPaths = {for (final f in filesToProcess) f.path};
      final stalePaths = existingByPath.keys.where((path) {
        if (discoveredPaths.contains(path)) return false;
        final underScannedRoot = scannedRoots.any((r) => path == r || p.isWithin(r, path));
        if (!underScannedRoot) return false;
        // A folder that could not be listed proves nothing about its files.
        return !unreadableDirs.any((d) => p.isWithin(d, path));
      }).toList();
      for (final path in stalePaths) {
        if (cancelled()) break;
        await removeFileByPath(path);
      }

      final pendingOcr = await _runOcrPass(filesToProcess, cancellationToken, onProgress);
      if (cancelled()) {
        _updateProgress(cancelledProgress(), onProgress);
        return Result.failure(const OperationCancelledError());
      }

      final finalProgress = IndexingProgress(
        status: IndexingStatus.completed,
        totalFilesDiscovered: filesToProcess.length,
        indexedCount: indexed,
        skippedCount: skipped,
        errorCount: errors,
        elapsedTime: stopwatch.elapsed,
        pendingOcrCount: pendingOcr,
        removedCount: stalePaths.length,
      );

      _updateProgress(finalProgress, onProgress);
      AppLogger.info(
        'Indexing completed in ${stopwatch.elapsed.inSeconds}s. '
        'Discovered: ${filesToProcess.length}, Indexed: $indexed, Skipped: $skipped, '
        'Removed: ${stalePaths.length}, OCR pending: $pendingOcr, Errors: $errors',
        'IndexingService',
      );

      return Result.success(finalProgress);
    } catch (e, stack) {
      AppLogger.error('Indexing failed: $e', 'IndexingService', stack);
      final errorProgress = _currentProgress.copyWith(
        status: IndexingStatus.error,
        errorMessage: e.toString(),
        elapsedTime: stopwatch.elapsed,
      );
      _updateProgress(errorProgress, onProgress);
      return Result.failure(UnknownError(message: 'Indexing failed: $e'));
    }
  }

  static bool _isUnchanged(FileRecord existing, FileEntity file) {
    final timeDiff =
        (existing.modifiedAt.millisecondsSinceEpoch - file.modifiedAt.millisecondsSinceEpoch).abs();
    return timeDiff <= 1000 && existing.size == BigInt.from(file.size) && existing.indexedAt != null;
  }

  Future<void> _waitWhilePaused(CancellationToken? token) async {
    while (_isPaused && token?.isCancelled != true) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Images larger than this are not OCR'd (decode memory on low-RAM phones).
  static const int maxOcrImageBytes = 30 * 1024 * 1024;

  /// OCR pass; returns how many images remain pending.
  Future<int> _runOcrPass(
    List<FileEntity> files,
    CancellationToken? token,
    void Function(IndexingProgress)? onProgress,
  ) async {
    if (!await _textExtractor.isOcrAvailable) return 0;

    final done = <String, (int, int)>{};
    for (final row in await db.customSelect('SELECT path, size, modified_ms FROM ocr_state').get()) {
      done[row.read<String>('path')] = (row.read<int>('size'), row.read<int>('modified_ms'));
    }
    final queue = files.where((f) {
      if (f.category != FileCategory.image || f.size <= 0 || f.size > maxOcrImageBytes) return false;
      final state = done[f.path];
      return state == null || state.$1 != f.size || state.$2 != f.modifiedAt.millisecondsSinceEpoch;
    }).toList();

    var remaining = queue.length;
    for (var i = 0; i < queue.length; i++) {
      if (token?.isCancelled == true) return remaining;
      await _waitWhilePaused(token);
      if (i % 10 == 0 && heavyWorkAllowed != null && !await heavyWorkAllowed!()) {
        AppLogger.info('OCR deferred (battery/thermal); $remaining images pending', 'IndexingService');
        return remaining;
      }

      final file = queue[i];
      try {
        final ocrText = await _textExtractor.extractOcrText(file);
        if (ocrText.isNotEmpty) {
          final base = await _textExtractor.extractContent(file, includeOcr: false);
          final rows = await (db.select(db.fileRecords)..where((t) => t.path.equals(file.path))).get();
          await db.transaction(() => _writeIndexRecord(
                file,
                '$base $ocrText',
                replaceIds: rows.map((r) => r.id).toList(),
              ));
        }
        await db.customStatement(
          'INSERT OR REPLACE INTO ocr_state (path, size, modified_ms) VALUES (?, ?, ?)',
          [file.path, file.size, file.modifiedAt.millisecondsSinceEpoch],
        );
      } catch (e) {
        AppLogger.warning('OCR pass failed for one image: $e', 'IndexingService');
      }
      remaining--;

      if (i % 5 == 0 || remaining == 0) {
        _updateProgress(
          _currentProgress.copyWith(
            status: IndexingStatus.indexing,
            currentPath: file.path,
            pendingOcrCount: remaining,
          ),
          onProgress,
        );
      }
      // OCR is CPU-heavy: leave room for the UI between images.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return remaining;
  }

  Future<void> _discoverFiles(
    Directory dir,
    List<FileEntity> results,
    List<String> unreadableDirs,
    CancellationToken? cancellationToken,
  ) async {
    if (cancellationToken?.isCancelled == true) return;

    try {
      var sinceYield = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (cancellationToken?.isCancelled == true) break;

        final basename = p.basename(entity.path);
        // Skip hidden files and Android system internal private directory
        if (basename.startsWith('.') || basename == 'Android') continue;

        if (entity is Directory) {
          await _discoverFiles(entity, results, unreadableDirs, cancellationToken);
        } else if (entity is File) {
          // A synchronous stat is a few microseconds; the async variant costs an
          // IO-thread round trip per file. Yield every 200 files instead.
          if (++sinceYield >= 200) {
            sinceYield = 0;
            await Future<void>.delayed(Duration.zero);
          }
          try {
            final stat = entity.statSync();
            final ext = p.extension(entity.path);
            final category = FileCategory.fromExtension(ext);

            results.add(
              FileEntity(
                id: 'file_${entity.path.hashCode.abs()}_${stat.size}',
                path: entity.path,
                name: basename,
                size: stat.size,
                modifiedAt: stat.modified,
                createdAt: stat.changed,
                isDirectory: false,
                extension: ext,
                category: category,
                isHidden: false,
              ),
            );
          } catch (_) {
            // Ignore unreadable individual files
          }
        }
      }
    } catch (e) {
      unreadableDirs.add(dir.path);
      AppLogger.warning('Cannot scan folder ${dir.path}: $e', 'IndexingService');
    }
  }

  Future<void> _writeIndexRecord(
    FileEntity file,
    String extractedContent, {
    List<String> replaceIds = const [],
  }) async {
    final fileId = 'file_${file.path.hashCode.abs()}_${file.size}';
    final now = DateTime.now();

    // Nested inside the caller's transaction when batching.
    await db.transaction(() async {
      // Drop superseded rows for this path (a changed size yields a new id).
      for (final oldId in replaceIds) {
        if (oldId == fileId) continue;
        await (db.delete(db.fileRecords)..where((t) => t.id.equals(oldId))).go();
        await db.deleteSearchDocumentByFileId(oldId);
      }

      // 1. Insert or update FileRecord
      await db.into(db.fileRecords).insertOnConflictUpdate(
            FileRecordsCompanion.insert(
              id: fileId,
              path: file.path,
              name: file.name,
              extension: file.extension,
              size: BigInt.from(file.size),
              modifiedAt: file.modifiedAt,
              createdAt: file.createdAt,
              mimeType: Value(file.mimeType),
              category: Value(file.category.displayName),
              indexedAt: Value(now),
            ),
          );

      // 2. Delete existing FTS5 document by file_id if present
      await db.deleteSearchDocumentByFileId(fileId);

      // 3. Insert into FTS5 virtual table
      await db.insertSearchDocument(
        fileId,
        file.name,
        file.path,
        extractedContent,
        '', // tags (populated in Phase 07 / AI)
        file.category.displayName,
      );
    });
  }

  @override
  Future<Result<void>> indexSingleFile(FileEntity file) async {
    try {
      final extracted = await _textExtractor.extractContent(file);
      final existing = await (db.select(db.fileRecords)
            ..where((t) => t.path.equals(file.path)))
          .get();
      await _writeIndexRecord(
        file,
        extracted,
        replaceIds: existing.map((r) => r.id).toList(),
      );
      return Result.success(null);
    } catch (e) {
      AppLogger.error('Failed to index file ${file.path}: $e', 'IndexingService');
      return Result.failure(UnknownError(message: 'Index failed: $e'));
    }
  }

  @override
  Future<Result<void>> removeFileByPath(String path) async {
    try {
      await db.transaction(() async {
        final rows = await (db.select(db.fileRecords)
              ..where((t) => t.path.equals(path)))
            .get();
        for (final row in rows) {
          await db.deleteSearchDocumentByFileId(row.id);
        }
        await (db.delete(db.fileRecords)..where((t) => t.path.equals(path))).go();
        await db.customStatement('DELETE FROM ocr_state WHERE path = ?', [path]);
      });
      return Result.success(null);
    } catch (e) {
      AppLogger.error('Failed to remove a file from the index: $e', 'IndexingService');
      return Result.failure(UnknownError(message: 'Remove failed: $e'));
    }
  }

  @override
  Future<Result<void>> removeFile(String fileId) async {
    try {
      await db.transaction(() async {
        await (db.delete(db.fileRecords)..where((t) => t.id.equals(fileId))).go();
        await db.deleteSearchDocumentByFileId(fileId);
      });
      return Result.success(null);
    } catch (e) {
      AppLogger.error('Failed to remove file $fileId from index: $e', 'IndexingService');
      return Result.failure(UnknownError(message: 'Remove failed: $e'));
    }
  }
}
