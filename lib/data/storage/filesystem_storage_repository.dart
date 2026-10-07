import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/file_operation_models.dart';
import '../../domain/models/storage_location.dart';
import '../../domain/repositories/i_storage_repository.dart';

/// Concrete implementation of IStorageRepository using the Dart I/O filesystem.
class FilesystemStorageRepository implements IStorageRepository {
  @override
  Future<List<StorageLocation>> getStorageLocations() async {
    final locations = <StorageLocation>[];

    if (Platform.isAndroid) {
      // Primary shared storage
      final primaryPath = '/storage/emulated/0';
      final primaryDir = Directory(primaryPath);
      if (await primaryDir.exists()) {
        locations.add(
          StorageLocation(
            id: 'internal',
            name: 'Internal Storage',
            path: primaryPath,
            totalBytes: 128 * 1024 * 1024 * 1024, // Fallback nominal, refined via native in Phase 13
            freeBytes: 64 * 1024 * 1024 * 1024,
            isRemovable: false,
          ),
        );
      }

      // Downloads directory
      final downloadsPath = '$primaryPath/Download';
      if (await Directory(downloadsPath).exists()) {
        locations.add(
          StorageLocation(
            id: 'downloads',
            name: 'Downloads',
            path: downloadsPath,
            totalBytes: 128 * 1024 * 1024 * 1024,
            freeBytes: 64 * 1024 * 1024 * 1024,
            isRemovable: false,
          ),
        );
      }
    } else {
      // Fallback for desktop testing / dev environments
      try {
        final appDocsDir = await getApplicationDocumentsDirectory();
        locations.add(
          StorageLocation(
            id: 'documents',
            name: 'App Documents',
            path: appDocsDir.path,
            totalBytes: 500 * 1024 * 1024 * 1024,
            freeBytes: 250 * 1024 * 1024 * 1024,
          ),
        );
      } catch (_) {
        locations.add(
          StorageLocation(
            id: 'temp',
            name: 'System Temp Storage',
            path: Directory.systemTemp.path,
            totalBytes: 128 * 1024 * 1024 * 1024,
            freeBytes: 64 * 1024 * 1024 * 1024,
          ),
        );
      }

      try {
        final tempDir = await getTemporaryDirectory();
        locations.add(
          StorageLocation(
            id: 'temp_dir',
            name: 'Temporary Storage',
            path: tempDir.path,
            totalBytes: 500 * 1024 * 1024 * 1024,
            freeBytes: 250 * 1024 * 1024 * 1024,
          ),
        );
      } catch (_) {}
    }

    return locations;
  }

  @override
  Future<List<FileEntity>> listDirectory(String path, {bool includeHidden = false}) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw FileNotFoundError(path: path);
    }

    final entities = <FileEntity>[];
    try {
      await for (final item in dir.list(followLinks: false)) {
        final basename = p.basename(item.path);
        final isHidden = basename.startsWith('.');
        if (isHidden && !includeHidden) continue;

        try {
          final stat = await item.stat();
          final isDirectory = item is Directory;
          final ext = isDirectory ? '' : p.extension(item.path).replaceAll('.', '').toLowerCase();
          final mime = isDirectory ? null : lookupMimeType(item.path);
          final category = isDirectory ? FileCategory.other : FileCategory.fromExtension(ext, mime);

          // Generate stable identity based on path, size, and modified time
          final idSeed = '${item.path}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
          final id = md5.convert(utf8.encode(idSeed)).toString();

          entities.add(
            FileEntity(
              id: id,
              path: item.path,
              name: basename,
              extension: ext,
              size: stat.size,
              modifiedAt: stat.modified,
              createdAt: stat.changed,
              isDirectory: isDirectory,
              isHidden: isHidden,
              mimeType: mime,
              category: category,
            ),
          );
        } catch (e) {
          AppLogger.warning('Skipping unreadable entity ${item.path}: $e', 'StorageRepo');
        }
      }

      // Sort directories first, then alphabetical by name
      entities.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return entities;
    } catch (e) {
      AppLogger.error('Failed to list directory $path: $e', 'StorageRepo');
      throw AccessDeniedError(path: path, technicalDetails: e.toString());
    }
  }

  @override
  Future<FileEntity> getFileDetails(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      throw FileNotFoundError(path: path);
    }

    final isDir = type == FileSystemEntityType.directory;
    final stat = await FileStat.stat(path);
    final basename = p.basename(path);
    final ext = isDir ? '' : p.extension(path).replaceAll('.', '').toLowerCase();
    final mime = isDir ? null : lookupMimeType(path);
    final category = isDir ? FileCategory.other : FileCategory.fromExtension(ext, mime);
    final idSeed = '${path}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
    final id = md5.convert(utf8.encode(idSeed)).toString();

    return FileEntity(
      id: id,
      path: path,
      name: basename,
      extension: ext,
      size: stat.size,
      modifiedAt: stat.modified,
      createdAt: stat.changed,
      isDirectory: isDir,
      isHidden: basename.startsWith('.'),
      mimeType: mime,
      category: category,
    );
  }

  @override
  Future<String> calculateChecksum(String path, {String algorithm = 'md5'}) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileNotFoundError(path: path);
    }

    try {
      final stream = file.openRead();
      final Hash hash = algorithm.toLowerCase() == 'sha256' ? sha256 : md5;
      final digest = await hash.bind(stream).first;
      return digest.toString();
    } catch (e) {
      AppLogger.error('Failed to compute checksum for $path: $e', 'StorageRepo');
      throw UnknownError(message: 'Checksum calculation failed: $e');
    }
  }

  @override
  Future<Result<FileEntity>> createFolder(String parentPath, String folderName) async {
    final sanitized = folderName.trim();
    if (sanitized.isEmpty) {
      return Result.failure(const UnknownError(message: 'Folder name cannot be empty.'));
    }

    final targetPath = p.join(parentPath, sanitized);
    final dir = Directory(targetPath);

    if (await dir.exists()) {
      return Result.failure(AccessDeniedError(
        path: targetPath,
        message: 'A folder with this name already exists.',
      ));
    }

    try {
      await dir.create(recursive: true);
      final details = await getFileDetails(targetPath);
      AppLogger.info('Folder created: $targetPath', 'StorageRepo');
      return Result.success(details);
    } catch (e) {
      AppLogger.error('Failed to create folder $targetPath: $e', 'StorageRepo');
      return Result.failure(UnknownError(message: 'Unable to create folder: $e'));
    }
  }

  @override
  Future<Result<FileEntity>> createFile(String parentPath, String fileName, [List<int>? bytes]) async {
    final sanitized = fileName.trim();
    if (sanitized.isEmpty) {
      return Result.failure(const UnknownError(message: 'File name cannot be empty.'));
    }

    final targetPath = p.join(parentPath, sanitized);
    final file = File(targetPath);

    if (await file.exists()) {
      return Result.failure(AccessDeniedError(
        path: targetPath,
        message: 'A file with this name already exists.',
      ));
    }

    try {
      await file.writeAsBytes(bytes ?? [], flush: true);
      final details = await getFileDetails(targetPath);
      AppLogger.info('File created: $targetPath', 'StorageRepo');
      return Result.success(details);
    } catch (e) {
      AppLogger.error('Failed to create file $targetPath: $e', 'StorageRepo');
      return Result.failure(UnknownError(message: 'Unable to create file: $e'));
    }
  }

  @override
  Future<Result<FileEntity>> rename(String path, String newName) async {
    final sanitized = newName.trim();
    if (sanitized.isEmpty) {
      return Result.failure(const UnknownError(message: 'New name cannot be empty.'));
    }

    final parent = p.dirname(path);
    final targetPath = p.join(parent, sanitized);

    if (targetPath == path) {
      return Result.success(await getFileDetails(path));
    }

    if (await FileSystemEntity.type(targetPath) != FileSystemEntityType.notFound) {
      return Result.failure(AccessDeniedError(
        path: targetPath,
        message: 'An item with this name already exists in this folder.',
      ));
    }

    try {
      final isDir = await FileSystemEntity.isDirectory(path);
      if (isDir) {
        await Directory(path).rename(targetPath);
      } else {
        await File(path).rename(targetPath);
      }
      final details = await getFileDetails(targetPath);
      AppLogger.info('Renamed $path -> $targetPath', 'StorageRepo');
      return Result.success(details);
    } catch (e) {
      AppLogger.error('Rename failed for $path: $e', 'StorageRepo');
      return Result.failure(UnknownError(message: 'Rename failed: $e'));
    }
  }

  @override
  Future<Result<void>> delete(String path) async {
    try {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.notFound) {
        return Result.failure(FileNotFoundError(path: path));
      }

      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      AppLogger.info('Deleted: $path', 'StorageRepo');
      return Result.success(null);
    } catch (e) {
      AppLogger.error('Failed to delete $path: $e', 'StorageRepo');
      return Result.failure(UnknownError(message: 'Delete failed: $e'));
    }
  }

  @override
  Future<Result<void>> batchDelete(
    List<String> paths, {
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  }) async {
    final total = paths.length;
    int processed = 0;

    for (final path in paths) {
      if (cancellationToken?.isCancelled == true) {
        onProgress?.call(FileOperationProgress(
          operationId: 'batch_delete',
          type: FileOperationType.delete,
          totalItems: total,
          processedItems: processed,
          isCancelled: true,
        ));
        return Result.failure(const OperationCancelledError());
      }

      try {
        final type = await FileSystemEntity.type(path);
        if (type == FileSystemEntityType.directory) {
          await Directory(path).delete(recursive: true);
        } else if (type == FileSystemEntityType.file) {
          await File(path).delete();
        }
      } catch (e) {
        AppLogger.warning('Partial failure deleting $path: $e', 'StorageRepo');
      }

      processed++;
      onProgress?.call(FileOperationProgress(
        operationId: 'batch_delete',
        type: FileOperationType.delete,
        totalItems: total,
        processedItems: processed,
        currentItemName: p.basename(path),
      ));
    }

    onProgress?.call(FileOperationProgress(
      operationId: 'batch_delete',
      type: FileOperationType.delete,
      totalItems: total,
      processedItems: total,
      isCompleted: true,
    ));

    return Result.success(null);
  }

  @override
  Future<Result<FileEntity>> copyFile(
    String sourcePath,
    String targetDirectory, {
    FileConflictStrategy conflictStrategy = FileConflictStrategy.renameNew,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return Result.failure(FileNotFoundError(path: sourcePath));
    }

    final targetDir = Directory(targetDirectory);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final fileName = p.basename(sourcePath);
    String destPath = p.join(targetDirectory, fileName);

    if (await File(destPath).exists()) {
      switch (conflictStrategy) {
        case FileConflictStrategy.skip:
          return Result.success(await getFileDetails(destPath));
        case FileConflictStrategy.overwrite:
          // Proceed with destPath
          break;
        case FileConflictStrategy.renameNew:
          destPath = _resolveAutoRenameConflict(targetDirectory, fileName);
          break;
      }
    }

    try {
      final totalBytes = await sourceFile.length();
      final inStream = sourceFile.openRead();
      final outSink = File(destPath).openWrite();

      int bytesCopied = 0;
      await for (final chunk in inStream) {
        if (cancellationToken?.isCancelled == true) {
          await outSink.close();
          await File(destPath).delete(); // Clean up incomplete copy
          return Result.failure(const OperationCancelledError());
        }

        outSink.add(chunk);
        bytesCopied += chunk.length;

        onProgress?.call(FileOperationProgress(
          operationId: 'copy_${p.basename(sourcePath)}',
          type: FileOperationType.copy,
          totalBytes: totalBytes,
          processedBytes: bytesCopied,
          currentItemName: fileName,
        ));
      }

      await outSink.flush();
      await outSink.close();

      final details = await getFileDetails(destPath);
      AppLogger.info('Copied $sourcePath -> $destPath ($bytesCopied bytes)', 'StorageRepo');
      return Result.success(details);
    } catch (e) {
      AppLogger.error('Copy failed $sourcePath -> $destPath: $e', 'StorageRepo');
      return Result.failure(UnknownError(message: 'File copy failed: $e'));
    }
  }

  @override
  Future<Result<FileEntity>> moveFile(
    String sourcePath,
    String targetDirectory, {
    FileConflictStrategy conflictStrategy = FileConflictStrategy.renameNew,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  }) async {
    final copyResult = await copyFile(
      sourcePath,
      targetDirectory,
      conflictStrategy: conflictStrategy,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );

    return copyResult.when(
      success: (copiedEntity) async {
        try {
          await File(sourcePath).delete();
          AppLogger.info('Moved $sourcePath -> ${copiedEntity.path}', 'StorageRepo');
          return Result.success(copiedEntity);
        } catch (e) {
          AppLogger.error('Failed to clean up source file after move: $e', 'StorageRepo');
          return Result.success(copiedEntity);
        }
      },
      failure: (error) => Result.failure(error),
    );
  }

  String _resolveAutoRenameConflict(String directory, String fileName) {
    final nameWithoutExt = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    int counter = 1;

    while (true) {
      final candidateName = '$nameWithoutExt ($counter)$ext';
      final candidatePath = p.join(directory, candidateName);
      if (!File(candidatePath).existsSync() && !Directory(candidatePath).existsSync()) {
        return candidatePath;
      }
      counter++;
    }
  }

  @override
  Future<Result<List<FileEntity>>> batchCopy(
    List<String> sourcePaths,
    String targetDirectory, {
    FileConflictStrategy conflictStrategy = FileConflictStrategy.renameNew,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  }) async {
    final results = <FileEntity>[];
    final total = sourcePaths.length;
    int processed = 0;

    for (final src in sourcePaths) {
      if (cancellationToken?.isCancelled == true) {
        onProgress?.call(FileOperationProgress(
          operationId: 'batch_copy',
          type: FileOperationType.copy,
          totalItems: total,
          processedItems: processed,
          isCancelled: true,
        ));
        return Result.failure(const OperationCancelledError());
      }

      final copyRes = await copyFile(
        src,
        targetDirectory,
        conflictStrategy: conflictStrategy,
        cancellationToken: cancellationToken,
      );

      copyRes.when(
        success: (entity) => results.add(entity),
        failure: (e) => AppLogger.warning('Partial failure copying $src: ${e.message}', 'StorageRepo'),
      );

      processed++;
      onProgress?.call(FileOperationProgress(
        operationId: 'batch_copy',
        type: FileOperationType.copy,
        totalItems: total,
        processedItems: processed,
        currentItemName: p.basename(src),
      ));
    }

    onProgress?.call(FileOperationProgress(
      operationId: 'batch_copy',
      type: FileOperationType.copy,
      totalItems: total,
      processedItems: total,
      isCompleted: true,
    ));

    return Result.success(results);
  }

  @override
  Future<Result<List<FileEntity>>> batchMove(
    List<String> sourcePaths,
    String targetDirectory, {
    FileConflictStrategy conflictStrategy = FileConflictStrategy.renameNew,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  }) async {
    final results = <FileEntity>[];
    final total = sourcePaths.length;
    int processed = 0;

    for (final src in sourcePaths) {
      if (cancellationToken?.isCancelled == true) {
        onProgress?.call(FileOperationProgress(
          operationId: 'batch_move',
          type: FileOperationType.move,
          totalItems: total,
          processedItems: processed,
          isCancelled: true,
        ));
        return Result.failure(const OperationCancelledError());
      }

      final moveRes = await moveFile(
        src,
        targetDirectory,
        conflictStrategy: conflictStrategy,
        cancellationToken: cancellationToken,
      );

      moveRes.when(
        success: (entity) => results.add(entity),
        failure: (e) => AppLogger.warning('Partial failure moving $src: ${e.message}', 'StorageRepo'),
      );

      processed++;
      onProgress?.call(FileOperationProgress(
        operationId: 'batch_move',
        type: FileOperationType.move,
        totalItems: total,
        processedItems: processed,
        currentItemName: p.basename(src),
      ));
    }

    onProgress?.call(FileOperationProgress(
      operationId: 'batch_move',
      type: FileOperationType.move,
      totalItems: total,
      processedItems: total,
      isCompleted: true,
    ));

    return Result.success(results);
  }

  @override
  Future<Result<List<FileEntity>>> batchRename(
    Map<String, String> pathToNewNames, {
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  }) async {
    final results = <FileEntity>[];
    final total = pathToNewNames.length;
    int processed = 0;

    for (final entry in pathToNewNames.entries) {
      if (cancellationToken?.isCancelled == true) {
        onProgress?.call(FileOperationProgress(
          operationId: 'batch_rename',
          type: FileOperationType.rename,
          totalItems: total,
          processedItems: processed,
          isCancelled: true,
        ));
        return Result.failure(const OperationCancelledError());
      }

      final renameRes = await rename(entry.key, entry.value);
      renameRes.when(
        success: (entity) => results.add(entity),
        failure: (e) => AppLogger.warning('Partial failure renaming ${entry.key}: ${e.message}', 'StorageRepo'),
      );

      processed++;
      onProgress?.call(FileOperationProgress(
        operationId: 'batch_rename',
        type: FileOperationType.rename,
        totalItems: total,
        processedItems: processed,
        currentItemName: entry.value,
      ));
    }

    onProgress?.call(FileOperationProgress(
      operationId: 'batch_rename',
      type: FileOperationType.rename,
      totalItems: total,
      processedItems: total,
      isCompleted: true,
    ));

    return Result.success(results);
  }

  @override
  Future<Result<FileEntity>> duplicate(String path) async {
    return copyFile(
      path,
      p.dirname(path),
      conflictStrategy: FileConflictStrategy.renameNew,
    );
  }
}
