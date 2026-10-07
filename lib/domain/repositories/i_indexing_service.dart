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

  /// Stream of active indexing progress.
  Stream<IndexingProgress> get progressStream;

  /// Current snapshot of indexing progress.
  IndexingProgress get currentProgress;
}
