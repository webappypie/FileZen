import 'file_entity.dart';

/// A cluster of cryptographically identical files.
class DuplicateGroup {
  final String checksum;
  final int fileSize;
  final FileEntity primaryFile;
  final List<FileEntity> duplicateFiles;

  const DuplicateGroup({
    required this.checksum,
    required this.fileSize,
    required this.primaryFile,
    required this.duplicateFiles,
  });

  /// All files in this group (primary + duplicates).
  List<FileEntity> get allFiles => [primaryFile, ...duplicateFiles];

  /// Total files in this cluster.
  int get totalCount => 1 + duplicateFiles.length;

  /// Total storage consumed by all copies combined.
  int get totalGroupSize => fileSize * totalCount;

  /// Potential space saved if all redundant copies are removed.
  int get recoverableSize => fileSize * duplicateFiles.length;
}

/// Progress state emitted during duplicate scans.
class DuplicateScanProgress {
  final String phaseDescription;
  final int processedFiles;
  final int totalFiles;
  final int foundDuplicateGroups;
  final int potentialSavingsBytes;
  final bool isCompleted;

  const DuplicateScanProgress({
    this.phaseDescription = 'Initializing...',
    this.processedFiles = 0,
    this.totalFiles = 0,
    this.foundDuplicateGroups = 0,
    this.potentialSavingsBytes = 0,
    this.isCompleted = false,
  });

  double get progressRatio =>
      totalFiles > 0 ? (processedFiles / totalFiles).clamp(0.0, 1.0) : 0.0;

  DuplicateScanProgress copyWith({
    String? phaseDescription,
    int? processedFiles,
    int? totalFiles,
    int? foundDuplicateGroups,
    int? potentialSavingsBytes,
    bool? isCompleted,
  }) {
    return DuplicateScanProgress(
      phaseDescription: phaseDescription ?? this.phaseDescription,
      processedFiles: processedFiles ?? this.processedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      foundDuplicateGroups: foundDuplicateGroups ?? this.foundDuplicateGroups,
      potentialSavingsBytes: potentialSavingsBytes ?? this.potentialSavingsBytes,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
