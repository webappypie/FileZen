import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/file_operation_models.dart';
import '../../domain/repositories/i_archive_service.dart';

/// Concrete implementation of IArchiveService using package:archive.
class ArchiveService implements IArchiveService {
  @override
  Future<Result<String>> createZipArchive({
    required List<String> sourcePaths,
    required String targetZipPath,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  }) async {
    try {
      if (sourcePaths.isEmpty) {
        return Result.failure(const InvalidPathError(message: 'No files provided for archive'));
      }

      final archive = Archive();
      final allFiles = <File>[];

      // Collect all individual files to compress
      for (final path in sourcePaths) {
        final type = await FileSystemEntity.type(path);
        if (type == FileSystemEntityType.file) {
          allFiles.add(File(path));
        } else if (type == FileSystemEntityType.directory) {
          final dir = Directory(path);
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) allFiles.add(entity);
          }
        }
      }

      final total = allFiles.length;
      int processed = 0;

      // Determine common parent root for relative path structure
      final rootDir = sourcePaths.length == 1 && await FileSystemEntity.isDirectory(sourcePaths.first)
          ? sourcePaths.first
          : p.dirname(sourcePaths.first);

      for (final file in allFiles) {
        if (cancellationToken?.isCancelled == true) {
          onProgress?.call(FileOperationProgress(
            operationId: 'zip_create',
            type: FileOperationType.compress,
            totalItems: total,
            processedItems: processed,
            isCancelled: true,
          ));
          return Result.failure(const OperationCancelledError());
        }

        final relativePath = p.relative(file.path, from: rootDir);
        final bytes = await file.readAsBytes();
        final archiveFile = ArchiveFile(relativePath, bytes.length, bytes);
        archive.addFile(archiveFile);

        processed++;
        onProgress?.call(FileOperationProgress(
          operationId: 'zip_create',
          type: FileOperationType.compress,
          totalItems: total,
          processedItems: processed,
          currentItemName: p.basename(file.path),
        ));
      }

      // Encode into zip binary
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);
      if (zipBytes == null) {
        return Result.failure(const UnknownError(message: 'Zip encoding produced null bytes'));
      }

      final targetFile = File(targetZipPath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(zipBytes, flush: true);

      onProgress?.call(FileOperationProgress(
        operationId: 'zip_create',
        type: FileOperationType.compress,
        totalItems: total,
        processedItems: total,
        isCompleted: true,
      ));

      AppLogger.info('Successfully created archive: $targetZipPath', 'ArchiveService');
      return Result.success(targetZipPath);
    } catch (e, stack) {
      AppLogger.error('Archive compression failed: $e', 'ArchiveService', stack);
      // Clean up incomplete target file if failed
      try {
        final f = File(targetZipPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      return Result.failure(UnknownError(message: 'Archive creation failed: $e'));
    }
  }

  @override
  Future<Result<String>> extractZipArchive({
    required String zipFilePath,
    required String destinationDirectory,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  }) async {
    try {
      final zipFile = File(zipFilePath);
      if (!await zipFile.exists()) {
        return Result.failure(FileNotFoundError(path: zipFilePath));
      }

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final total = archive.length;
      int processed = 0;

      final destDir = Directory(destinationDirectory);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      for (final file in archive) {
        if (cancellationToken?.isCancelled == true) {
          onProgress?.call(FileOperationProgress(
            operationId: 'zip_extract',
            type: FileOperationType.extract,
            totalItems: total,
            processedItems: processed,
            isCancelled: true,
          ));
          return Result.failure(const OperationCancelledError());
        }

        final filename = file.name;
        final outPath = p.join(destinationDirectory, filename);

        if (file.isFile) {
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          final data = file.content as List<int>;
          await outFile.writeAsBytes(data, flush: true);
        } else {
          await Directory(outPath).create(recursive: true);
        }

        processed++;
        onProgress?.call(FileOperationProgress(
          operationId: 'zip_extract',
          type: FileOperationType.extract,
          totalItems: total,
          processedItems: processed,
          currentItemName: filename,
        ));
      }

      onProgress?.call(FileOperationProgress(
        operationId: 'zip_extract',
        type: FileOperationType.extract,
        totalItems: total,
        processedItems: total,
        isCompleted: true,
      ));

      AppLogger.info('Successfully extracted archive to $destinationDirectory', 'ArchiveService');
      return Result.success(destinationDirectory);
    } catch (e, stack) {
      AppLogger.error('Archive extraction failed: $e', 'ArchiveService', stack);
      return Result.failure(UnknownError(message: 'Extraction failed: $e'));
    }
  }
}
