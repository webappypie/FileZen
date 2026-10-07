import 'file_entity.dart';

/// Single match result from the universal search engine.
class SearchResultItem {
  final FileEntity file;
  final String? snippet;
  final double rank;
  final String? matchedField;

  const SearchResultItem({
    required this.file,
    this.snippet,
    required this.rank,
    this.matchedField,
  });

  @override
  String toString() => 'SearchResultItem(name: ${file.name}, rank: $rank, snippet: $snippet)';
}
