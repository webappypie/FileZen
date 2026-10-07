import '../../core/result/result.dart';
import '../models/search_query.dart';
import '../models/search_result_item.dart';

/// Contract for universal full-text file search.
abstract class ISearchRepository {
  /// Executes a full-text search with optional filters.
  Future<Result<List<SearchResultItem>>> search(SearchQuery query);

  /// Returns total number of indexed files in the database.
  Future<Result<int>> getIndexedDocumentCount();

  /// Clears the entire search index and document catalog.
  Future<Result<void>> clearIndex();
}
