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

  IndexingService({
    required this.db,
    required this.storageRepo,
    TextExtractor? textExtractor,
  }) : _textExtractor = textExtractor ?? TextExtractor();

  @override
  Stream<IndexingProgress> get progressStream => _progressController.stream;

  @override
  IndexingProgress get currentProgress => _currentProgress;

  bool get isPaused => _isPaused;

  @override
  void pause() {
    _isPaused = true;
    _updateProgress(
      _currentProgress.copyWith(status: IndexingStatus.paused),
      null,
    );
  }

  @override
  void resume() {
    _isPaused = false;
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

  @override
  Future<Result<IndexingProgress>> runIndexScan({
    List<String>? targetPaths,
    CancellationToken? cancellationToken,
    void Function(IndexingProgress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      List<String> roots = targetPaths ?? [];
      if (roots.isEmpty) {
        final locations = await storageRepo.getStorageLocations();
        roots = locations.map((l) => l.path).toList();
      }

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

      // Collect all candidate file entities across roots
      final filesToProcess = <FileEntity>[];

      for (final root in roots) {
        if (cancellationToken?.isCancelled == true) break;
        await _discoverFiles(Directory(root), filesToProcess, cancellationToken);
      }

      if (cancellationToken?.isCancelled == true) {
        _updateProgress(
          _currentProgress.copyWith(status: IndexingStatus.cancelled, elapsedTime: stopwatch.elapsed),
          onProgress,
        );
        return Result.failure(const OperationCancelledError());
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

      // Process in batches of 25 with small micro-yields to prevent UI jank
      const batchSize = 25;
      for (var i = 0; i < filesToProcess.length; i += batchSize) {
        if (cancellationToken?.isCancelled == true) {
          _updateProgress(
            _currentProgress.copyWith(
              status: IndexingStatus.cancelled,
              indexedCount: indexed,
              skippedCount: skipped,
              errorCount: errors,
              elapsedTime: stopwatch.elapsed,
            ),
            onProgress,
          );
          return Result.failure(const OperationCancelledError());
        }

        final end = (i + batchSize < filesToProcess.length) ? i + batchSize : filesToProcess.length;
        final batch = filesToProcess.sublist(i, end);

        for (final file in batch) {
          if (cancellationToken?.isCancelled == true) break;

          while (_isPaused && cancellationToken?.isCancelled != true) {
            await Future.delayed(const Duration(milliseconds: 100));
          }

          try {
            // Incremental check: has file changed since last index?
            final existingRows = await (db.select(db.fileRecords)
                  ..where((t) => t.path.equals(file.path)))
                .get();
            // More than one row for a path is a leftover from an earlier edit
            // (the row id embeds the size): treat it as stale and replace them all.
            final existing = existingRows.length == 1 ? existingRows.single : null;

            final timeDiff = existing == null
                ? 999999
                : (existing.modifiedAt.millisecondsSinceEpoch - file.modifiedAt.millisecondsSinceEpoch).abs();

            if (existing != null &&
                timeDiff <= 1000 &&
                existing.size == BigInt.from(file.size) &&
                existing.indexedAt != null) {
              skipped++;
            } else {
              // Yield briefly for image OCR to keep UI responsive and prevent thermal throttling
              if (file.category == FileCategory.image) {
                await Future.delayed(const Duration(milliseconds: 10));
              }

              // Extract text tokens and index into SQLite & FTS5
              final extracted = await _textExtractor.extractContent(file);
              await _writeIndexRecord(
                file,
                extracted,
                replaceIds: existingRows.map((r) => r.id).toList(),
              );
              indexed++;
            }
          } catch (e) {
            AppLogger.warning('Error indexing file ${file.path}: $e', 'IndexingService');
            errors++;
          }
        }

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

        // Micro-yield to allow UI event loop processing
        await Future.delayed(const Duration(milliseconds: 2));
      }

      final finalProgress = IndexingProgress(
        status: IndexingStatus.completed,
        totalFilesDiscovered: filesToProcess.length,
        indexedCount: indexed,
        skippedCount: skipped,
        errorCount: errors,
        elapsedTime: stopwatch.elapsed,
      );

      _updateProgress(finalProgress, onProgress);
      AppLogger.info(
        'Indexing completed in ${stopwatch.elapsed.inSeconds}s. '
        'Discovered: ${filesToProcess.length}, Indexed: $indexed, Skipped: $skipped, Errors: $errors',
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

  Future<void> _discoverFiles(
    Directory dir,
    List<FileEntity> results,
    CancellationToken? cancellationToken,
  ) async {
    if (cancellationToken?.isCancelled == true) return;
    if (!await dir.exists()) return;

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (cancellationToken?.isCancelled == true) break;

        final basename = p.basename(entity.path);
        // Skip hidden files and Android system internal private directory
        if (basename.startsWith('.') || basename == 'Android') continue;

        if (entity is Directory) {
          await _discoverFiles(entity, results, cancellationToken);
        } else if (entity is File) {
          try {
            final stat = await entity.stat();
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
