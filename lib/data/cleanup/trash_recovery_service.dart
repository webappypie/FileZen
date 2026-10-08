import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/trash_item.dart';
import '../../domain/repositories/i_storage_repository.dart';
import '../../domain/repositories/i_trash_recovery_service.dart';

/// Concrete implementation of ITrashRecoveryService managing the FileZen Recycle Bin.
class TrashRecoveryService implements ITrashRecoveryService {
  final IStorageRepository storageRepo;
  final String? customTrashDirectoryPath;

  TrashRecoveryService({
    required this.storageRepo,
    this.customTrashDirectoryPath,
  });

  Directory? _cachedTrashDir;

  Future<Directory> _getTrashDirectory() async {
    if (_cachedTrashDir != null && await _cachedTrashDir!.exists()) {
      return _cachedTrashDir!;
    }

    if (customTrashDirectoryPath != null) {
      final dir = Directory(customTrashDirectoryPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cachedTrashDir = dir;
      return dir;
    }

    final appDocsDir = await getApplicationDocumentsDirectory();
    final trashDir = Directory(p.join(appDocsDir.path, '.filezen_trash'));
    if (!await trashDir.exists()) {
      await trashDir.create(recursive: true);
    }
    _cachedTrashDir = trashDir;
    return trashDir;
  }

  File _getManifestFile(Directory trashDir) {
    return File(p.join(trashDir.path, 'trash_manifest.json'));
  }

  Future<List<TrashItem>> _readManifest() async {
    try {
      final trashDir = await _getTrashDirectory();
      final manifestFile = _getManifestFile(trashDir);
      if (!await manifestFile.exists()) {
        return [];
      }
      final content = await manifestFile.readAsString();
      if (content.trim().isEmpty) return [];
      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      return list
          .map((item) => TrashItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.warning('Failed to read trash manifest: $e', 'TrashService');
      return [];
    }
  }

  Future<void> _writeManifest(List<TrashItem> items) async {
    try {
      final trashDir = await _getTrashDirectory();
      final manifestFile = _getManifestFile(trashDir);
      final jsonStr = jsonEncode(items.map((i) => i.toJson()).toList());
      await manifestFile.writeAsString(jsonStr, flush: true);
    } catch (e) {
      AppLogger.error('Failed to write trash manifest: $e', 'TrashService');
    }
  }

  @override
  Future<Result<TrashItem>> moveToTrash(FileEntity file) async {
    final source = File(file.path);
    if (!await source.exists()) {
      return Result.failure(FileNotFoundError(path: file.path));
    }

    try {
      final trashDir = await _getTrashDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = '${timestamp}_${p.basename(file.path)}';
      final destinationPath = p.join(trashDir.path, safeName);

      // Move the physical file to trash directory
      await source.rename(destinationPath);

      final trashItem = TrashItem(
        id: file.id,
        originalPath: file.path,
        trashPath: destinationPath,
        fileName: file.name,
        size: file.size,
        trashedAt: DateTime.now(),
        mimeType: file.mimeType,
        category: file.category,
      );

      final manifest = await _readManifest();
      manifest.removeWhere((i) => i.id == file.id || i.trashPath == destinationPath);
      manifest.add(trashItem);
      await _writeManifest(manifest);

      AppLogger.info('Moved file to trash: ${file.path} -> $destinationPath', 'TrashService');
      return Result.success(trashItem);
    } catch (e) {
      AppLogger.error('Failed to move ${file.path} to trash: $e', 'TrashService');
      return Result.failure(UnknownError(message: 'Failed to move to trash: $e'));
    }
  }

  @override
  Future<Result<List<TrashItem>>> batchMoveToTrash(List<FileEntity> files) async {
    final trashedItems = <TrashItem>[];
    for (final file in files) {
      final res = await moveToTrash(file);
      if (res.isSuccess && res.dataOrNull != null) {
        trashedItems.add(res.dataOrNull!);
      }
    }
    return Result.success(trashedItems);
  }

  @override
  Future<Result<FileEntity>> restoreFromTrash(TrashItem item) async {
    final trashFile = File(item.trashPath);
    if (!await trashFile.exists()) {
      return Result.failure(FileNotFoundError(path: item.trashPath));
    }

    try {
      final originalParent = Directory(p.dirname(item.originalPath));
      if (!await originalParent.exists()) {
        await originalParent.create(recursive: true);
      }

      // Check for collision at original location
      var destinationPath = item.originalPath;
      if (await File(destinationPath).exists()) {
        final ext = p.extension(destinationPath);
        final base = p.basenameWithoutExtension(destinationPath);
        destinationPath = p.join(originalParent.path, '${base}_restored$ext');
      }

      await trashFile.rename(destinationPath);

      final manifest = await _readManifest();
      manifest.removeWhere((i) => i.id == item.id || i.trashPath == item.trashPath);
      await _writeManifest(manifest);

      final restoredEntity = await storageRepo.getFileDetails(destinationPath);
      AppLogger.info('Restored file from trash: ${item.trashPath} -> $destinationPath', 'TrashService');
      return Result.success(restoredEntity);
    } catch (e) {
      AppLogger.error('Failed to restore ${item.fileName} from trash: $e', 'TrashService');
      return Result.failure(UnknownError(message: 'Restore failed: $e'));
    }
  }

  @override
  Future<Result<List<FileEntity>>> batchRestoreFromTrash(List<TrashItem> items) async {
    final restoredFiles = <FileEntity>[];
    for (final item in items) {
      final res = await restoreFromTrash(item);
      if (res.isSuccess && res.dataOrNull != null) {
        restoredFiles.add(res.dataOrNull!);
      }
    }
    return Result.success(restoredFiles);
  }

  @override
  Future<List<TrashItem>> listTrash() async {
    final manifest = await _readManifest();
    final verified = <TrashItem>[];

    for (final item in manifest) {
      if (await File(item.trashPath).exists()) {
        verified.add(item);
      }
    }

    // Sort newest trashed first
    verified.sort((a, b) => b.trashedAt.compareTo(a.trashedAt));
    return verified;
  }

  @override
  Future<Result<void>> permanentlyDelete(TrashItem item) async {
    try {
      final file = File(item.trashPath);
      if (await file.exists()) {
        await file.delete();
      }

      final manifest = await _readManifest();
      manifest.removeWhere((i) => i.id == item.id || i.trashPath == item.trashPath);
      await _writeManifest(manifest);

      AppLogger.info('Permanently deleted trash item: ${item.trashPath}', 'TrashService');
      return Result.success(null);
    } catch (e) {
      AppLogger.error('Failed to permanently delete ${item.trashPath}: $e', 'TrashService');
      return Result.failure(UnknownError(message: 'Deletion failed: $e'));
    }
  }

  @override
  Future<Result<void>> batchPermanentlyDelete(List<TrashItem> items) async {
    for (final item in items) {
      await permanentlyDelete(item);
    }
    return Result.success(null);
  }

  @override
  Future<Result<void>> emptyTrash() async {
    try {
      final trashDir = await _getTrashDirectory();
      if (await trashDir.exists()) {
        final entities = trashDir.listSync();
        for (final entity in entities) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
      await _writeManifest([]);
      AppLogger.info('Recycle bin emptied', 'TrashService');
      return Result.success(null);
    } catch (e) {
      AppLogger.error('Failed to empty trash: $e', 'TrashService');
      return Result.failure(UnknownError(message: 'Failed to empty trash: $e'));
    }
  }

  @override
  Future<int> getTrashTotalSize() async {
    final items = await listTrash();
    return items.fold<int>(0, (sum, i) => sum + i.size);
  }
}
