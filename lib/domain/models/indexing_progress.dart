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

  const IndexingProgress({
    this.status = IndexingStatus.idle,
    this.totalFilesDiscovered = 0,
    this.indexedCount = 0,
    this.skippedCount = 0,
    this.errorCount = 0,
    this.currentPath,
    this.elapsedTime = Duration.zero,
    this.errorMessage,
  });

  bool get isRunning =>
      status == IndexingStatus.scanning || status == IndexingStatus.indexing;

  double get progressFraction {
    if (totalFilesDiscovered == 0) return 0.0;
    final processed = indexedCount + skippedCount;
    return (processed / totalFilesDiscovered).clamp(0.0, 1.0);
  }

  IndexingProgress copyWith({
    IndexingStatus? status,
    int? totalFilesDiscovered,
    int? indexedCount,
    int? skippedCount,
    int? errorCount,
    String? currentPath,
    Duration? elapsedTime,
    String? errorMessage,
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
    );
  }

  @override
  String toString() =>
      'IndexingProgress(status: $status, indexed: $indexedCount, skipped: $skippedCount, total: $totalFilesDiscovered)';
}
