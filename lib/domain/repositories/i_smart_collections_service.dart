import '../models/ai_models.dart';
import '../models/file_entity.dart';

/// Clean Architecture interface for virtual Smart Collections evaluation.
abstract class ISmartCollectionsService {
  /// Evaluates and returns all active smart collections with updated item counts and sizes.
  Future<List<SmartCollection>> getSmartCollections();

  /// Retrieves the list of files matching a specific smart collection.
  Future<List<FileEntity>> getFilesInCollection(String collectionId);
}
