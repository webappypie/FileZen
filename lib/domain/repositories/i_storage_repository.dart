import '../../core/result/result.dart';
import '../models/file_entity.dart';
import '../models/file_operation_models.dart';
import '../models/storage_location.dart';

/// Domain contract for local storage access and file operations.
abstract class IStorageRepository {
  /// Returns accessible storage volumes (e.g. Internal Storage, Downloads, SD Card).
  Future<List<StorageLocation>> getStorageLocations();

  /// Lists entries in a directory with file entities.
  Future<List<FileEntity>> listDirectory(String path, {bool includeHidden = false});

  /// Reads detailed metadata for a file or directory.
  Future<FileEntity> getFileDetails(String path);

  /// Calculates a cryptographic checksum (e.g. MD5, SHA-256) using chunked streams.
  Future<String> calculateChecksum(String path, {String algorithm = 'md5'});

  /// Creates a new directory at the target parent path.
  Future<Result<FileEntity>> createFolder(String parentPath, String folderName);

  /// Creates a new file at the target parent path with optional initial bytes.
  Future<Result<FileEntity>> createFile(String parentPath, String fileName, [List<int>? bytes]);

  /// Renames an existing file or directory with collision detection.
  Future<Result<FileEntity>> rename(String path, String newName);

  /// Deletes a single file or directory.
  Future<Result<void>> delete(String path);

  /// Deletes multiple files or directories with cancellation and progress reporting.
  Future<Result<void>> batchDelete(
    List<String> paths, {
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  });

  /// Copies a file to target directory with conflict resolution, cancellation, and progress.
  Future<Result<FileEntity>> copyFile(
    String sourcePath,
    String targetDirectory, {
    FileConflictStrategy conflictStrategy = FileConflictStrategy.renameNew,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  });

  /// Moves a file to target directory with conflict resolution, cancellation, and progress.
  Future<Result<FileEntity>> moveFile(
    String sourcePath,
    String targetDirectory, {
    FileConflictStrategy conflictStrategy = FileConflictStrategy.renameNew,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  });

  /// Batch copies multiple files/folders to target directory.
  Future<Result<List<FileEntity>>> batchCopy(
    List<String> sourcePaths,
    String targetDirectory, {
    FileConflictStrategy conflictStrategy = FileConflictStrategy.renameNew,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  });

  /// Batch moves multiple files/folders to target directory.
  Future<Result<List<FileEntity>>> batchMove(
    List<String> sourcePaths,
    String targetDirectory, {
    FileConflictStrategy conflictStrategy = FileConflictStrategy.renameNew,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  });

  /// Batch renames files with progress and cancellation.
  Future<Result<List<FileEntity>>> batchRename(
    Map<String, String> pathToNewNames, {
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  });

  /// Duplicates a file in place by appending copy indicator.
  Future<Result<FileEntity>> duplicate(String path);
}
