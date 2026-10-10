import 'package:drift/native.dart';
import 'package:filezen/core/result/result.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/database/database_provider.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:filezen/domain/models/search_query.dart';
import 'package:filezen/domain/models/search_result_item.dart';
import 'package:filezen/domain/repositories/i_search_repository.dart';
import 'package:filezen/features/search/presentation/providers/search_providers.dart';
import 'package:filezen/features/search/presentation/screens/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSearchRepository implements ISearchRepository {
  final List<SearchResultItem> items;
  _FakeSearchRepository(this.items);

  @override
  Future<Result<List<SearchResultItem>>> search(SearchQuery query) async {
    if (query.text == 'nonexistent') {
      return Result.success([]);
    }
    return Result.success(items);
  }

  @override
  Future<Result<int>> getIndexedDocumentCount() async => Result.success(items.length);

  @override
  Future<Result<void>> clearIndex() async => Result.success(null);
}

void main() {
  final mockItem = SearchResultItem(
    file: FileEntity(
      id: 'file_001',
      path: '/storage/emulated/0/Download/budget_2026.pdf',
      name: 'budget_2026.pdf',
      extension: '.pdf',
      size: 1024 * 300,
      modifiedAt: DateTime(2026, 3, 15),
      createdAt: DateTime(2026, 3, 1),
      isDirectory: false,
      category: FileCategory.document,
    ),
    snippet: 'Annual [match]budget[/match] report planning',
    rank: -12.5,
  );

  testWidgets('SearchScreen renders search bar, banner, chips, and recent searches', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Isolated in-memory database: never open the on-disk app database from tests.
          appDatabaseProvider.overrideWith((ref) {
            final db = AppDatabase(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          searchRepositoryProvider.overrideWithValue(_FakeSearchRepository([mockItem])),
          indexedCountProvider.overrideWith((ref) => Future.value(42)),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify search input field exists
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search files, OCR, documents...'), findsOneWidget);

    // Verify indexing banner
    expect(find.text('42 files indexed in catalog'), findsOneWidget);
    expect(find.text('Scan Storage'), findsOneWidget);

    // Verify category chips
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);

    // Verify recent searches section
    expect(find.text('Recent Searches'), findsOneWidget);
    expect(find.text('contract'), findsOneWidget);
  });

  testWidgets('SearchScreen renders search result card with snippet highlighting on query input', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Isolated in-memory database: never open the on-disk app database from tests.
          appDatabaseProvider.overrideWith((ref) {
            final db = AppDatabase(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          searchRepositoryProvider.overrideWithValue(_FakeSearchRepository([mockItem])),
          indexedCountProvider.overrideWith((ref) => Future.value(1)),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Type query
    await tester.enterText(find.byType(TextField), 'budget');
    await tester.pumpAndSettle();

    // Verify matching result
    expect(find.text('1 file found'), findsOneWidget);
    expect(find.text('budget_2026.pdf'), findsOneWidget);
    expect(find.text('Documents'), findsWidgets);
    expect(find.byTooltip('File actions'), findsOneWidget);
  });

  testWidgets('SearchScreen renders EmptyView when query yields no results', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Isolated in-memory database: never open the on-disk app database from tests.
          appDatabaseProvider.overrideWith((ref) {
            final db = AppDatabase(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          searchRepositoryProvider.overrideWithValue(_FakeSearchRepository([])),
          indexedCountProvider.overrideWith((ref) => Future.value(0)),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Type query that returns empty
    await tester.enterText(find.byType(TextField), 'nonexistent');
    await tester.pumpAndSettle();

    expect(find.text('No Matching Files Found'), findsOneWidget);
    expect(find.text('Index Storage'), findsOneWidget);
  });
}
