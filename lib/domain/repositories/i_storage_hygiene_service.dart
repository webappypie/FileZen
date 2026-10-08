import '../models/file_entity.dart';
import '../models/storage_intelligence_models.dart';

/// Contract for calculating storage breakdown, folder treemaps, largest items, and usage trends.
abstract class IStorageHygieneService {
  /// Computes device storage overview across file categories.
  Future<StorageOverview> getStorageOverview({List<String>? targetPaths});

  /// Returns top directories consuming the most storage space.
  Future<List<FolderStorageItem>> getTopFolders({
    List<String>? targetPaths,
    int limit = 10,
  });

  /// Returns largest individual files occupying storage.
  Future<List<FileEntity>> getLargestFiles({
    List<String>? targetPaths,
    int limit = 20,
    int minSizeBytes = 50 * 1024 * 1024,
  });

  /// Returns historical storage trend points recorded over time.
  Future<List<StorageTrendPoint>> getStorageTrends();

  /// Captures and persists the current storage snapshot to the local trend history.
  Future<void> recordCurrentStorageSnapshot({List<String>? targetPaths});
}
