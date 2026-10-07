import '../models/ai_models.dart';
import '../models/search_result_item.dart';

/// Clean Architecture interface for parsing natural language queries and executing "Ask Your Files".
abstract class IQueryInterpreterService {
  /// Parses raw natural language text into a structured intent with filters.
  NaturalQueryIntent interpretQuery(String naturalQuery);

  /// Executes an "Ask Your Files" query and returns ranked, actionable results.
  Future<List<SearchResultItem>> executeAskYourFiles(String naturalQuery);
}
