import '../../core/result/result.dart';
import '../models/file_entity.dart';
import '../models/trash_item.dart';

/// Domain contract for safe trash bin, recoverable deletions, and restoration.
abstract class ITrashRecoveryService {
  /// Safely moves a file to the FileZen Recycle Bin, preserving original location metadata.
  Future<Result<TrashItem>> moveToTrash(FileEntity file);

  /// Safely moves multiple files to the Recycle Bin.
  Future<Result<List<TrashItem>>> batchMoveToTrash(List<FileEntity> files);

  /// Restores a trashed file back to its original physical location.
  Future<Result<FileEntity>> restoreFromTrash(TrashItem item);

  /// Restores multiple trashed files back to their original physical locations.
  Future<Result<List<FileEntity>>> batchRestoreFromTrash(List<TrashItem> items);

  /// Returns all files currently held in the Recycle Bin.
  Future<List<TrashItem>> listTrash();

  /// Permanently and irreversibly deletes a single item from the Recycle Bin.
  Future<Result<void>> permanentlyDelete(TrashItem item);

  /// Permanently deletes multiple items from the Recycle Bin.
  Future<Result<void>> batchPermanentlyDelete(List<TrashItem> items);

  /// Irreversibly purges all items currently in the Recycle Bin.
  Future<Result<void>> emptyTrash();

  /// Calculates total bytes occupied by files currently residing in the Recycle Bin.
  Future<int> getTrashTotalSize();
}
