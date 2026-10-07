# Phase 03 — Indexing Engine & SQLite/FTS5 Search

## Objective
Establish high-performance SQLite FTS5 full-text indexing, background incremental filesystem scanning with cooperative cancellation, multi-token text extraction, rich search ranking with BM25 and snippet highlights, and an interactive Universal Search interface.

## Scope
- SQLite FTS5 Virtual Table & Schema Configuration:
  - Configured `build.yaml` with `sql.options.modules: [fts5]`.
  - Created `search_documents.drift` defining `search_documents USING fts5(file_id UNINDEXED, name, path, content, tags, category, tokenize = 'unicode61')`.
  - Generated type-safe Drift queries for `searchFts`, `searchFtsWithCategory`, `insertSearchDocument`, `deleteSearchDocumentByFileId`, `clearSearchDocuments`, and `countSearchDocuments`.
  - Updated `AppDatabase` with schema version 2, migration strategy, and `indexedAt` timestamp column on `FileRecords`.
- Search & Indexing Domain Models:
  - `SearchQuery`: Text criteria, optional `FileCategory`, size bounds (`minSize`, `maxSize`), date ranges, extension, and favorites filter.
  - `SearchResultItem`: Encapsulates matched `FileEntity`, relevance rank (BM25 score), and extracted snippet with match delimiters.
  - `IndexingProgress` & `IndexingStatus`: Telemetry tracking discovered files, indexed count, skipped count, error count, elapsed duration, and cooperative cancellation state.
  - `ISearchRepository` & `IIndexingService`: Clean Architecture domain contracts.
- Indexing & Text Extraction Services:
  - `TextExtractor`: Safe chunked text extraction up to 64KB for 30+ plain-text, markdown, code, and config formats; fallback keyword/path tokenization for binary and media assets.
  - `IndexingService`:
    - Recursive filesystem crawler with hidden file and private directory filtering.
    - True incremental scanning: compares modified timestamps (second/millisecond tolerance across NTFS/FAT32/exFAT) and file size to skip unchanged files without redundant re-indexing.
    - Batched database transactions (25 items per batch) with micro-yields to guarantee zero UI thread blocking.
    - Full cooperative cancellation support using `CancellationToken`.
- Full-Text Search Repository:
  - `SearchRepository`:
    - Sanitizes input and generates prefix match tokens (`term*`) for responsive search-as-you-type UX.
    - Queries FTS5 with BM25 relevance ordering and snippet highlighting.
    - Batch joins FTS5 result IDs with `FileRecords` table to assemble rich `FileEntity` metadata.
    - Implements category browsing when query text is empty.
    - Implements secondary filtering (min/max size, modified date range, file extension, favorite status).
- Presentation & State Management:
  - Riverpod providers in `search_providers.dart`: `searchRepositoryProvider`, `indexingServiceProvider`, `searchQueryTextProvider`, `searchCategoryFilterProvider`, `currentSearchQueryProvider`, `searchResultsProvider`, `indexedCountProvider`, `indexingProgressProvider`, `searchHistoryProvider`.
  - Universal Search UI in `SearchScreen`:
    - Search text field with instant query updates, clear button, and search history persistence.
    - Background indexing banner with live progress indicators and cancel/trigger actions.
    - Horizontal category filter chips (`All`, `Documents`, `Images`, `Videos`, `Audio`, `Archives`, `APKs`).
    - Recent searches chip list with quick removal and clear-all action.
    - Result card list with category badges, file paths, formatted sizes, modified dates, and rich parsed `[match]` snippet highlights.
    - File details dialog inspector.
- Comprehensive Test Suite:
  - Unit tests: `test/unit/search_repository_test.dart` (FTS5 queries, prefix matching, category filtering, secondary filters, count, and clear).
  - Unit tests: `test/unit/indexing_service_test.dart` (initial scan, incremental skip, modification detection, file removal, cooperative cancellation).
  - Unit tests: `test/unit/database_test.dart` (Drift FTS5 integration with BM25 rank and snippet generation).
  - Widget tests: `test/widget/search_screen_test.dart` (search bar, indexing banner, category chips, recent searches, snippet card rendering, empty states).

## Out of Scope
- Advanced multi-selection toolbar, batch clipboard operations, and ZIP extraction (Phase 04).
- Media viewers and Media3 playback (Phase 05).
- Document engine and PDF Studio (Phase 06).
- On-device ML Kit OCR models (Phase 07).
- Cleanup algorithms and duplicate detection (Phase 08).
- Vault hardware Keystore encryption (Phase 09).

## Dependencies
- `drift: ^2.24.2`
- `drift_flutter: ^0.2.4`
- `sqlite3_flutter_libs: ^0.5.28`
- `flutter_riverpod: ^2.6.1`
- `path: ^1.9.1`

## Modules & Files Created/Modified
- `build.yaml` (Enabled FTS5 module for drift_dev)
- `lib/data/database/search_documents.drift`
- `lib/data/database/app_database.dart` & `app_database.g.dart`
- `lib/domain/models/search_query.dart`
- `lib/domain/models/search_result_item.dart`
- `lib/domain/models/indexing_progress.dart`
- `lib/domain/repositories/i_search_repository.dart`
- `lib/domain/repositories/i_indexing_service.dart`
- `lib/data/indexing/text_extractor.dart`
- `lib/data/indexing/indexing_service.dart`
- `lib/data/search/search_repository.dart`
- `lib/features/search/presentation/providers/search_providers.dart`
- `lib/features/search/presentation/screens/search_screen.dart`
- `test/unit/database_test.dart`
- `test/unit/search_repository_test.dart`
- `test/unit/indexing_service_test.dart`
- `test/widget/search_screen_test.dart`

## Verification & Test Results
- `flutter analyze`: **0 issues** found.
- `flutter test`: **41 tests passing** (100% success rate across core, WAP client, Drift database, FTS5 virtual table, storage repository, category resolution, search repository, indexing engine, and widget suites).
