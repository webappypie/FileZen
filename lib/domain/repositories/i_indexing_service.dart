import '../../core/result/result.dart';
import '../models/file_entity.dart';
import '../models/file_operation_models.dart';
import '../models/indexing_progress.dart';

/// Contract for incremental background filesystem indexing engine.
abstract class IIndexingService {
  /// Scans directories, discovers files, and writes metadata/FTS records incrementally.
  Future<Result<IndexingProgress>> runIndexScan({
    List<String>? targetPaths,
    CancellationToken? cancellationToken,
    void Function(IndexingProgress)? onProgress,
  });

  /// Indexes a single file into the SQLite database and FTS virtual table.
  Future<Result<void>> indexSingleFile(FileEntity file);

  /// Removes a file record and its corresponding FTS search document.
  Future<Result<void>> removeFile(String fileId);

  /// Removes every index entry (record and full-text document) for [path].
  ///
  /// Prefer this over [removeFile] when only the file's location is known: index
  /// row ids are derived from path and size and do not match `FileEntity.id`.
  Future<Result<void>> removeFileByPath(String path);

  /// Stream of active indexing progress.
  Stream<IndexingProgress> get progressStream;

  /// Current snapshot of indexing progress.
  IndexingProgress get currentProgress;

  /// Pauses the active indexing process (giving priority to foreground tasks).
  void pause();

  /// Resumes a paused indexing process.
  void resume();

  /// Schedules continuous incremental background sync.
  void startPeriodicBackgroundSync({Duration interval = const Duration(minutes: 5)});

  /// Stops continuous background sync.
  void stopPeriodicBackgroundSync();
}
