import '../models/cleanup_models.dart';
import '../models/deduplication_models.dart';
import '../models/file_entity.dart';
import '../models/file_operation_models.dart';

/// Contract for duplicate detection, similar media analysis, and cleanup candidate generation.
abstract class IDeduplicationService {
  /// Scans for bit-for-bit exact duplicates using 3-tier algorithm:
  /// 1. File size clustering
  /// 2. Cryptographic checksum comparison
  /// 3. Duplicate group synthesis with primary retention recommendation
  Future<List<DuplicateGroup>> scanExactDuplicates({
    List<String>? scanPaths,
    CancellationToken? cancellationToken,
    void Function(DuplicateScanProgress)? onProgress,
  });

  /// Scans for similar/burst photos based on timestamp proximity, dimension similarity, and naming patterns.
  Future<List<FileEntity>> scanSimilarPhotos({
    List<String>? scanPaths,
    Duration burstWindow = const Duration(seconds: 5),
  });

  /// Scans for blurry, corrupted, or extremely low-quality photos.
  Future<List<FileEntity>> scanBlurryPhotos({List<String>? scanPaths});

  /// Scans for files exceeding the specified threshold size (e.g. 50 MB).
  Future<List<FileEntity>> scanLargeFiles({
    List<String>? scanPaths,
    int minSizeBytes = 50 * 1024 * 1024,
  });

  /// Scans for Android application packages (.apk) lingering in storage.
  Future<List<FileEntity>> scanOldApks({
    List<String>? scanPaths,
    int daysOld = 7,
  });

  /// Scans for screenshots older than the threshold.
  Future<List<FileEntity>> scanOldScreenshots({
    List<String>? scanPaths,
    int daysOld = 14,
  });

  /// Scans for repeated downloads (e.g., file (1).pdf, file (2).pdf).
  Future<List<FileEntity>> scanRepeatedDownloads({List<String>? scanPaths});

  /// Scans for directories that contain no files or subdirectories.
  Future<List<String>> scanEmptyFolders({List<String>? scanPaths});

  /// Scans for dormant files that have not been modified or accessed for a prolonged period.
  Future<List<FileEntity>> scanDormantFiles({
    List<String>? scanPaths,
    int daysInactive = 90,
  });

  /// Scans for old voice recordings and audio clips.
  Future<List<FileEntity>> scanOldRecordings({
    List<String>? scanPaths,
    int daysOld = 30,
  });

  /// Aggregates all cleanup candidate groups across categories for dashboard review.
  Future<List<CleanupCandidateGroup>> scanAllCleanupOpportunities({
    List<String>? scanPaths,
  });

  /// Executes an explicit user-confirmed cleanup plan adhering to the Destructive-Action Contract.
  Future<CleanupExecutionResult> executeCleanup(CleanupExecutionPlan plan);

  /// Deletes verified empty folders.
  Future<int> deleteEmptyFolders(List<String> folderPaths);
}
