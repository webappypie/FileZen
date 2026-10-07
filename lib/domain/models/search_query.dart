import 'file_category.dart';

/// Specification of criteria for universal file search.
class SearchQuery {
  final String text;
  final FileCategory? category;
  final int? minSize;
  final int? maxSize;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? extension;
  final bool? isFavoriteOnly;

  const SearchQuery({
    required this.text,
    this.category,
    this.minSize,
    this.maxSize,
    this.startDate,
    this.endDate,
    this.extension,
    this.isFavoriteOnly,
  });

  bool get isEmpty => text.trim().isEmpty && category == null;

  SearchQuery copyWith({
    String? text,
    FileCategory? category,
    int? minSize,
    int? maxSize,
    DateTime? startDate,
    DateTime? endDate,
    String? extension,
    bool? isFavoriteOnly,
  }) {
    return SearchQuery(
      text: text ?? this.text,
      category: category ?? this.category,
      minSize: minSize ?? this.minSize,
      maxSize: maxSize ?? this.maxSize,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      extension: extension ?? this.extension,
      isFavoriteOnly: isFavoriteOnly ?? this.isFavoriteOnly,
    );
  }
}
