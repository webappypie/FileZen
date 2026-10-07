import '../models/ai_models.dart';
import '../models/file_entity.dart';

/// Clean Architecture interface for discovering related and companion files.
abstract class IRelatedFilesService {
  /// Analyzes local signals (naming, directory proximity, metadata, content)
  /// to find files closely related to the specified file.
  Future<List<RelatedFileItem>> findRelatedFiles(FileEntity file);
}
