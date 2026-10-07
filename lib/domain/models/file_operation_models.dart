import '../../core/error/app_error.dart';

/// Type of file management operation.
enum FileOperationType {
  createFolder,
  createFile,
  rename,
  copy,
  move,
  delete,
  checksum,
  compress,
  extract,
}

/// Conflict resolution strategy when target file already exists.
enum FileConflictStrategy {
  overwrite,
  renameNew,
  skip,
}

/// Cooperative cancellation token for long-running operations.
class CancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

/// Progress reporting state for single and batch file operations.
class FileOperationProgress {
  final String operationId;
  final FileOperationType type;
  final int totalItems;
  final int processedItems;
  final int totalBytes;
  final int processedBytes;
  final String currentItemName;
  final bool isCompleted;
  final bool isCancelled;
  final AppError? error;

  const FileOperationProgress({
    required this.operationId,
    required this.type,
    this.totalItems = 1,
    this.processedItems = 0,
    this.totalBytes = 0,
    this.processedBytes = 0,
    this.currentItemName = '',
    this.isCompleted = false,
    this.isCancelled = false,
    this.error,
  });

  double get ratio {
    if (totalBytes > 0) {
      return (processedBytes / totalBytes).clamp(0.0, 1.0);
    }
    if (totalItems > 0) {
      return (processedItems / totalItems).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  FileOperationProgress copyWith({
    String? operationId,
    FileOperationType? type,
    int? totalItems,
    int? processedItems,
    int? totalBytes,
    int? processedBytes,
    String? currentItemName,
    bool? isCompleted,
    bool? isCancelled,
    AppError? error,
  }) {
    return FileOperationProgress(
      operationId: operationId ?? this.operationId,
      type: type ?? this.type,
      totalItems: totalItems ?? this.totalItems,
      processedItems: processedItems ?? this.processedItems,
      totalBytes: totalBytes ?? this.totalBytes,
      processedBytes: processedBytes ?? this.processedBytes,
      currentItemName: currentItemName ?? this.currentItemName,
      isCompleted: isCompleted ?? this.isCompleted,
      isCancelled: isCancelled ?? this.isCancelled,
      error: error ?? this.error,
    );
  }
}
