import 'package:drift/drift.dart';
import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/search_result_item.dart';
import '../../domain/repositories/i_search_repository.dart';
import '../database/app_database.dart';

class _FtsMatch {
  final String fileId;
  final String? snippet;
  final double rank;

  _FtsMatch({
    required this.fileId,
    this.snippet,
    required this.rank,
  });
}

/// Implementation of ISearchRepository using Drift and SQLite FTS5.
class SearchRepository implements ISearchRepository {
  final AppDatabase _db;

  SearchRepository(this._db);

  @override
  Future<Result<List<SearchResultItem>>> search(SearchQuery query) async {
    try {
      final text = query.text.trim();

      // Case 1: Text search via FTS5
      if (text.isNotEmpty) {
        final ftsQuery = _sanitizeFtsQuery(text);
        if (ftsQuery.isEmpty) {
          return Result.success([]);
        }

        final category = query.category?.displayName;
        final List<_FtsMatch> ftsResults;

        if (category != null) {
          final res = await _db.searchFtsWithCategory(ftsQuery, category).get();
          ftsResults = res
              .map((r) => _FtsMatch(fileId: r.fileId, snippet: r.snippet, rank: r.rank))
              .toList();
        } else {
          final res = await _db.searchFts(ftsQuery).get();
          ftsResults = res
              .map((r) => _FtsMatch(fileId: r.fileId, snippet: r.snippet, rank: r.rank))
              .toList();
        }

        if (ftsResults.isEmpty) {
          return Result.success([]);
        }

        // Batch fetch matching FileRecords
        final fileIds = ftsResults.map((r) => r.fileId).toList();
        final records = await (_db.select(_db.fileRecords)
              ..where((t) => t.id.isIn(fileIds)))
            .get();

        final recordMap = {for (final r in records) r.id: r};

        final items = <SearchResultItem>[];
        for (final match in ftsResults) {
          final record = recordMap[match.fileId];
          if (record == null) continue;

          // Apply secondary filters
          if (query.minSize != null && record.size < BigInt.from(query.minSize!)) continue;
          if (query.maxSize != null && record.size > BigInt.from(query.maxSize!)) continue;
          if (query.startDate != null && record.modifiedAt.isBefore(query.startDate!)) continue;
          if (query.endDate != null && record.modifiedAt.isAfter(query.endDate!)) continue;
          if (query.extension != null &&
              !record.extension.toLowerCase().endsWith(query.extension!.toLowerCase().replaceAll('.', ''))) {
            continue;
          }
          if (query.isFavoriteOnly == true && !record.isFavorite) continue;

          final entity = FileEntity(
            id: record.id,
            path: record.path,
            name: record.name,
            size: record.size.toInt(),
            modifiedAt: record.modifiedAt,
            createdAt: record.createdAt,
            isDirectory: false,
            mimeType: record.mimeType,
            extension: record.extension,
            category: FileCategory.fromExtension(record.extension, record.mimeType),
            metadata: {'isFavorite': record.isFavorite},
          );

          items.add(
            SearchResultItem(
              file: entity,
              snippet: match.snippet,
              rank: match.rank,
            ),
          );
        }

        // FTS5 bm25 rank: lower is more relevant
        items.sort((a, b) => a.rank.compareTo(b.rank));
        return Result.success(items);
      }

      // Case 2: Category filter with empty text query (browse by category)
      if (query.category != null) {
        final categoryName = query.category!.displayName;
        final records = await (_db.select(_db.fileRecords)
              ..where((t) => t.category.equals(categoryName))
              ..orderBy([(t) => OrderingTerm.desc(t.modifiedAt)]))
            .get();

        final items = records.map((record) {
          final entity = FileEntity(
            id: record.id,
            path: record.path,
            name: record.name,
            size: record.size.toInt(),
            modifiedAt: record.modifiedAt,
            createdAt: record.createdAt,
            isDirectory: false,
            mimeType: record.mimeType,
            extension: record.extension,
            category: FileCategory.fromExtension(record.extension, record.mimeType),
            metadata: {'isFavorite': record.isFavorite},
          );

          return SearchResultItem(
            file: entity,
            rank: 0.0,
          );
        }).toList();

        return Result.success(items);
      }

      return Result.success([]);
    } catch (e, stack) {
      AppLogger.error('Search query failed: $e', 'SearchRepo', stack);
      return Result.failure(UnknownError(message: 'Search failed: $e'));
    }
  }

  @override
  Future<Result<int>> getIndexedDocumentCount() async {
    try {
      final count = await _db.countSearchDocuments().getSingle();
      return Result.success(count);
    } catch (e) {
      AppLogger.error('Failed to get indexed count: $e', 'SearchRepo');
      return Result.failure(UnknownError(message: 'Failed count: $e'));
    }
  }

  @override
  Future<Result<void>> clearIndex() async {
    try {
      await _db.transaction(() async {
        await _db.clearSearchDocuments();
        await (_db.update(_db.fileRecords)).write(
          const FileRecordsCompanion(indexedAt: Value.absent()),
        );
      });
      AppLogger.info('Cleared FTS5 search index', 'SearchRepo');
      return Result.success(null);
    } catch (e) {
      AppLogger.error('Failed to clear search index: $e', 'SearchRepo');
      return Result.failure(UnknownError(message: 'Failed clear: $e'));
    }
  }

  /// Sanitizes text input and generates prefix match tokens for FTS5.
  String _sanitizeFtsQuery(String input) {
    // Strip characters with special FTS5 syntax meaning that might cause syntax errors
    final clean = input.replaceAll(RegExp(r'["\*\+\-\^\:\(\)\{\}]'), ' ').trim();
    if (clean.isEmpty) return '';

    final words = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    // Append wildcard * to every term for responsive search-as-you-type prefix matching
    return words.map((w) => '$w*').join(' ');
  }
}
