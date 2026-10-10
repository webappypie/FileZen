/// Status of the background indexing process.
enum IndexingStatus {
  idle,
  scanning,
  indexing,
  completed,
  paused,
  error,
  cancelled,
}

/// Progress telemetry of a background file indexing session.
class IndexingProgress {
  final IndexingStatus status;
  final int totalFilesDiscovered;
  final int indexedCount;
  final int skippedCount;
  final int errorCount;
  final String? currentPath;
  final Duration elapsedTime;
  final String? errorMessage;

  /// Images still waiting for on-device OCR (deferred to a later run when the
  /// device is on battery saver, low battery or thermally throttled).
  final int pendingOcrCount;

  /// Index entries removed because their files no longer exist.
  final int removedCount;

  const IndexingProgress({
    this.status = IndexingStatus.idle,
    this.totalFilesDiscovered = 0,
    this.indexedCount = 0,
    this.skippedCount = 0,
    this.errorCount = 0,
    this.currentPath,
    this.elapsedTime = Duration.zero,
    this.errorMessage,
    this.pendingOcrCount = 0,
    this.removedCount = 0,
  });

  /// A paused scan is still in progress (it resumes in place), so a second scan
  /// must not start alongside it.
  bool get isRunning =>
      status == IndexingStatus.scanning ||
      status == IndexingStatus.indexing ||
      status == IndexingStatus.paused;

  double get progressFraction {
    if (totalFilesDiscovered == 0) return 0.0;
    final processed = indexedCount + skippedCount;
    return (processed / totalFilesDiscovered).clamp(0.0, 1.0);
  }

  int get remainingFiles =>
      (totalFilesDiscovered - (indexedCount + skippedCount)).clamp(0, totalFilesDiscovered);

  bool get isUpToDate => status == IndexingStatus.completed && errorCount == 0;

  IndexingProgress copyWith({
    IndexingStatus? status,
    int? totalFilesDiscovered,
    int? indexedCount,
    int? skippedCount,
    int? errorCount,
    String? currentPath,
    Duration? elapsedTime,
    String? errorMessage,
    int? pendingOcrCount,
    int? removedCount,
  }) {
    return IndexingProgress(
      status: status ?? this.status,
      totalFilesDiscovered: totalFilesDiscovered ?? this.totalFilesDiscovered,
      indexedCount: indexedCount ?? this.indexedCount,
      skippedCount: skippedCount ?? this.skippedCount,
      errorCount: errorCount ?? this.errorCount,
      currentPath: currentPath ?? this.currentPath,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      errorMessage: errorMessage ?? this.errorMessage,
      pendingOcrCount: pendingOcrCount ?? this.pendingOcrCount,
      removedCount: removedCount ?? this.removedCount,
    );
  }

  @override
  String toString() =>
      'IndexingProgress(status: $status, indexed: $indexedCount, skipped: $skippedCount, total: $totalFilesDiscovered)';
}
