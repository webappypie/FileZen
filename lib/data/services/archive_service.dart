import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/file_operation_models.dart';
import '../../domain/repositories/i_archive_service.dart';

/// Concrete implementation of IArchiveService using package:archive with
/// security hardening against ZIP path traversal, symlink attacks,
/// and archive/decompression bombs.
class ArchiveService implements IArchiveService {
  /// Maximum permitted files in a single archive to prevent archive bombs.
  static const int maxArchiveFileCount = 10000;

  /// Maximum permitted uncompressed size for a single archive entry (2 GB).
  static const int maxSingleFileSize = 2 * 1024 * 1024 * 1024;

  /// Maximum total permitted uncompressed extraction size across an entire archive (5 GB).
  static const int maxTotalExtractionSize = 5 * 1024 * 1024 * 1024;

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
    final createdFiles = <String>[];
    final createdDirs = <String>[];

    try {
      final zipFile = File(zipFilePath);
      if (!await zipFile.exists()) {
        return Result.failure(FileNotFoundError(path: zipFilePath));
      }

      final canonicalDest = p.canonicalize(p.normalize(destinationDirectory));
      final destDir = Directory(canonicalDest);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
        createdDirs.add(canonicalDest);
      }

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Defense 1: Archive bomb (file count)
      if (archive.length > maxArchiveFileCount) {
        return Result.failure(SecurityError(
          message: 'Archive contains too many entries (${archive.length}). Limit is $maxArchiveFileCount.',
          technicalDetails: 'Archive bomb protection triggered',
        ));
      }

      final total = archive.length;
      int processed = 0;
      int totalExtractedBytes = 0;

      // Defense 2: Pre-validate all entries before writing any to disk
      for (final file in archive) {
        final rawName = file.name;

        // Null byte check
        if (rawName.contains('\x00')) {
          return Result.failure(SecurityError(
            message: 'Archive contains invalid file path with null characters: $rawName',
            technicalDetails: 'Path traversal / null byte injection attempt',
          ));
        }

        // Absolute path check (Unix '/', Windows '\', or drive letter 'C:')
        if (p.isAbsolute(rawName) ||
            rawName.startsWith('/') ||
            rawName.startsWith('\\') ||
            RegExp(r'^[a-zA-Z]:').hasMatch(rawName)) {
          return Result.failure(SecurityError(
            message: 'Archive contains prohibited absolute path: $rawName',
            technicalDetails: 'Archive path traversal attempt blocked',
          ));
        }

        // Directory traversal sequence check
        final segments = p.split(rawName);
        if (segments.any((s) => s == '..')) {
          return Result.failure(SecurityError(
            message: 'Archive contains prohibited directory traversal sequence: $rawName',
            technicalDetails: 'Archive path traversal attempt blocked',
          ));
        }

        // Symlink attack check
        if (file.isSymbolicLink) {
          return Result.failure(SecurityError(
            message: 'Archive contains prohibited symbolic link: $rawName',
            technicalDetails: 'Symbolic link traversal attack blocked',
          ));
        }

        // Target path canonicalization and boundary containment check
        final targetPath = p.canonicalize(p.join(canonicalDest, rawName));
        if (!p.isWithin(canonicalDest, targetPath) && targetPath != canonicalDest) {
          return Result.failure(SecurityError(
            message: 'Archive entry escapes target destination directory: $rawName',
            technicalDetails: 'Archive path traversal escape blocked ($targetPath outside $canonicalDest)',
          ));
        }

        // Decompression bomb check (individual file size & cumulative size)
        final uncompressedSize = file.size;
        if (uncompressedSize > maxSingleFileSize) {
          return Result.failure(SecurityError(
            message: 'Archive file exceeds maximum allowed entry size ($uncompressedSize bytes): $rawName',
            technicalDetails: 'Decompression bomb protection triggered',
          ));
        }

        totalExtractedBytes += uncompressedSize;
        if (totalExtractedBytes > maxTotalExtractionSize) {
          return Result.failure(SecurityError(
            message: 'Total uncompressed archive size exceeds maximum permitted quota of $maxTotalExtractionSize bytes.',
            technicalDetails: 'Decompression bomb protection triggered',
          ));
        }
      }

      // Extraction loop
      for (final file in archive) {
        if (cancellationToken?.isCancelled == true) {
          await _rollback(createdFiles, createdDirs, canonicalDest);
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
        final targetPath = p.canonicalize(p.join(canonicalDest, filename));

        if (file.isFile) {
          final outFile = File(targetPath);
          final parentDir = outFile.parent;
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
            createdDirs.add(parentDir.path);
          }
          final data = file.content as List<int>;
          await outFile.writeAsBytes(data, flush: true);
          createdFiles.add(targetPath);
        } else {
          final outDir = Directory(targetPath);
          if (!await outDir.exists()) {
            await outDir.create(recursive: true);
            createdDirs.add(targetPath);
          }
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

      AppLogger.info('Successfully extracted archive to $canonicalDest', 'ArchiveService');
      return Result.success(canonicalDest);
    } on AppError catch (e) {
      await _rollback(createdFiles, createdDirs, destinationDirectory);
      return Result.failure(e);
    } catch (e, stack) {
      await _rollback(createdFiles, createdDirs, destinationDirectory);
      AppLogger.error('Archive extraction failed: $e', 'ArchiveService', stack);
      return Result.failure(UnknownError(message: 'Extraction failed: $e'));
    }
  }

  Future<void> _rollback(List<String> files, List<String> dirs, String rootDest) async {
    for (final f in files) {
      try {
        final file = File(f);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    final sortedDirs = List<String>.from(dirs)..sort((a, b) => b.length.compareTo(a.length));
    for (final d in sortedDirs) {
      if (d != rootDest) {
        try {
          final dir = Directory(d);
          if (await dir.exists()) await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
