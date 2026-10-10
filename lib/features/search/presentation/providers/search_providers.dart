import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/database/database_provider.dart';
import '../../../../data/indexing/indexing_service.dart';
import '../../../../data/search/search_repository.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/file_operation_models.dart';
import '../../../../domain/models/indexing_progress.dart';
import '../../../../domain/models/search_query.dart';
import '../../../../domain/models/search_result_item.dart';
import '../../../../domain/repositories/i_indexing_service.dart';
import '../../../../domain/repositories/i_search_repository.dart';
import '../../../files/presentation/providers/storage_providers.dart';

/// Provider for ISearchRepository.
final searchRepositoryProvider = Provider<ISearchRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SearchRepository(db);
});

/// Provider for IIndexingService.
final indexingServiceProvider = Provider<IIndexingService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final storageRepo = ref.watch(storageRepositoryProvider);
  return IndexingService(db: db, storageRepo: storageRepo);
});

/// Active search text input.
final searchQueryTextProvider = StateProvider<String>((ref) => '');

/// Active category filter for search.
final searchCategoryFilterProvider = StateProvider<FileCategory?>((ref) => null);

/// Combined SearchQuery.
final currentSearchQueryProvider = Provider<SearchQuery>((ref) {
  final text = ref.watch(searchQueryTextProvider);
  final category = ref.watch(searchCategoryFilterProvider);
  return SearchQuery(text: text, category: category);
});

/// Provider delivering debounced search results.
final searchResultsProvider = FutureProvider<List<SearchResultItem>>((ref) async {
  final query = ref.watch(currentSearchQueryProvider);
  if (query.isEmpty) return const [];

  final repo = ref.watch(searchRepositoryProvider);
  final result = await repo.search(query);
  return result.when(
    success: (items) => items,
    failure: (error) => throw Exception(error.message),
  );
});

/// Provider tracking count of indexed documents in the database.
final indexedCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(searchRepositoryProvider);
  final result = await repo.getIndexedDocumentCount();
  return result.when(
    success: (count) => count,
    failure: (_) => 0,
  );
});

/// State notifier managing active background indexing tasks and progress.
final indexingProgressProvider =
    StateNotifierProvider<IndexingProgressNotifier, IndexingProgress>((ref) {
  final service = ref.watch(indexingServiceProvider);
  return IndexingProgressNotifier(service, ref);
});

class IndexingProgressNotifier extends StateNotifier<IndexingProgress> {
  final IIndexingService _service;
  final Ref _ref;
  CancellationToken? _cancellationToken;

  IndexingProgressNotifier(this._service, this._ref)
      : super(const IndexingProgress()) {
    _service.progressStream.listen((progress) {
      state = progress;
      if (progress.status == IndexingStatus.completed) {
        _ref.invalidate(indexedCountProvider);
        _ref.invalidate(searchResultsProvider);
      }
    });
  }

  Future<void> startIndexing([List<String>? targetPaths]) async {
    if (state.isRunning) return;

    _cancellationToken = CancellationToken();
    await _service.runIndexScan(
      targetPaths: targetPaths,
      cancellationToken: _cancellationToken,
    );
  }

  void cancelIndexing() {
    _cancellationToken?.cancel();
  }

  void pauseIndexing() {
    _service.pause();
  }

  void resumeIndexing() {
    _service.resume();
  }
}

/// Recent search history queries.
final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
  return SearchHistoryNotifier();
});

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier()
      : super(const [
          'contract',
          'invoice',
          'screenshot',
          'resume',
        ]);

  void addQuery(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;

    state = [
      clean,
      ...state.where((q) => q.toLowerCase() != clean.toLowerCase()),
    ].take(10).toList();
  }

  void removeQuery(String query) {
    state = state.where((q) => q != query).toList();
  }

  void clearHistory() {
    state = const [];
  }
}
