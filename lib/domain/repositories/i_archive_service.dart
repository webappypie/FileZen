import '../../core/result/result.dart';
import '../models/file_operation_models.dart';

/// Contract for ZIP archive compression and extraction.
abstract class IArchiveService {
  /// Compresses source files/directories into target ZIP file.
  Future<Result<String>> createZipArchive({
    required List<String> sourcePaths,
    required String targetZipPath,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  });

  /// Extracts contents of a ZIP file into a target directory.
  Future<Result<String>> extractZipArchive({
    required String zipFilePath,
    required String destinationDirectory,
    CancellationToken? cancellationToken,
    void Function(FileOperationProgress)? onProgress,
  });
}
