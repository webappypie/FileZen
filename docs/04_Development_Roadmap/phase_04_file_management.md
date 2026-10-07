# Phase 04 — Core File Management Operations

## Objective
Deliver robust, high-performance, and safe core file management operations: multi-selection action mode, clipboard management (copy/cut/paste), batch operations (copy, move, rename, delete, duplicate), ZIP archive compression and extraction with streaming progress and cooperative cancellation, interactive sorting and hidden file filtering, and synchronization with the Drift/FTS5 search catalog.

## Scope
- Domain Models & Enums:
  - `FileClipboard`: Encapsulates clipboard contents, source directory, and `ClipboardMode` (`copy` vs `cut`).
  - `FileSortCriteria`: Configurable file sorting by `FileSortField` (`name`, `dateModified`, `size`, `type`), `SortDirection` (`ascending`, `descending`), and `foldersFirst` ordering logic.
  - `FileOperationType`: Extended with `compress` and `extract` operation types.
  - `InvalidPathError`: Added to application error hierarchy for path safety validation.
- Archive Compression & Extraction Engine:
  - `IArchiveService` & `ArchiveService`: Clean Architecture contracts and implementation utilizing the `archive` package.
  - Streaming progress reporting (`OperationProgress` with current file, item index, total count, processed bytes, total bytes, and percentage).
  - Cooperative cancellation via `CancellationToken`.
  - Directory recursion, zip entry resolution, and secure path traversal prevention.
- Storage Repository Enhancements:
  - `IStorageRepository` & `FilesystemStorageRepository`:
    - `batchCopy`: Multi-file recursive copy with conflict resolution (`overwrite`, `skip`, `rename`).
    - `batchMove`: Multi-file atomic move across paths or directory trees.
    - `batchRename`: Pattern and prefix/suffix-based batch renaming with collision checks.
    - `duplicate`: In-place file duplication with automatic `_copy` numbering.
- Riverpod Presentation Architecture:
  - `file_management_providers.dart`:
    - `archiveServiceProvider`: Riverpod factory for ZIP operations.
    - `fileSortCriteriaProvider`: Configurable sort state (default: Name ASC, folders on top).
    - `showHiddenFilesProvider`: Toggle state for `.dotfiles` visibility.
    - `fileClipboardProvider`: Global state for copy/cut clipboard buffer.
    - `selectedFilePathsProvider`: State notifier tracking active selection set during multi-select mode.
    - `activeOperationProgressProvider`: Live telemetry stream for long-running batch and archive operations.
    - `sortedDirectoryContentsProvider`: Reactive sorting pipeline applying active criteria and hidden file filters.
- Enhanced File Browser Interface (`FilesScreen`):
  - **Multi-Selection Action Mode AppBar**: Shows selected items count, total calculated size, "Select All", Copy, Cut, Delete, ZIP Archive, and Batch Rename.
  - **Floating Clipboard Paste Bar**: Surfaces active clipboard count with one-tap "Paste here" or "Cancel" actions.
  - **Interactive Sorting Bottom Sheet**: Modal selector for Name, Date, Size, and Extension sorting, direction toggle, and folders-first switch.
  - **Item Context Menu (3-dots)**: Fast access to Properties, Rename, Duplicate, Copy, Move, Extract Archive, and Delete.
  - **Destructive Operation Safety Dialog**: Prompts confirmation for single/bulk deletions displaying item count, affected paths, and total bytes.
  - **Archive Compression & Extraction Dialogs**: Target filename input, destination selection, and progress monitoring.
  - **Reactive Catalog Synchronization**: Background index update and cache eviction on `AppDatabase` upon create, copy, move, rename, delete, and extract operations.
- Test Suite:
  - `test/unit/archive_service_test.dart`: ZIP creation, archive extraction, nested directory structures, and cooperative cancellation.
  - `test/unit/file_sort_criteria_test.dart`: Multi-field sorting verification (name, size, date, type) and folders-first precedence.
  - `test/unit/batch_operations_test.dart`: Batch copy, batch move, batch rename, in-place duplicate, and conflict handling.
  - `test/widget/file_management_test.dart`: Multi-selection mode activation, action bar actions, floating clipboard bar, and sort sheet interaction.

## Out of Scope
- Media viewers and Media3 playback (Phase 05).
- Document engine and PDF Studio (Phase 06).
- On-device ML Kit OCR models (Phase 07).
- Storage cleanup, duplicate analyzer, and large file detector (Phase 08).
- Secure Vault Keystore AES-256 encryption (Phase 09).
- Background notifications and WorkManager tasks (Phase 10).

## Dependencies
- `archive: ^3.6.1`
- `flutter_riverpod: ^2.6.1`
- `drift: ^2.24.2`
- `path: ^1.9.1`

## Modules & Files Created/Modified
- `pubspec.yaml` & `pubspec.lock` (Added `archive: ^3.6.1`)
- `lib/domain/models/file_clipboard.dart`
- `lib/domain/models/file_sort_criteria.dart`
- `lib/domain/models/file_operation_models.dart`
- `lib/core/error/app_error.dart`
- `lib/app/theme/app_colors.dart`
- `lib/domain/repositories/i_archive_service.dart`
- `lib/data/services/archive_service.dart`
- `lib/domain/repositories/i_storage_repository.dart`
- `lib/data/storage/filesystem_storage_repository.dart`
- `lib/features/files/presentation/providers/file_management_providers.dart`
- `lib/features/files/presentation/screens/files_screen.dart`
- `test/unit/archive_service_test.dart`
- `test/unit/file_sort_criteria_test.dart`
- `test/unit/batch_operations_test.dart`
- `test/widget/file_management_test.dart`
- `docs/04_Development_Roadmap/phase_04_file_management.md`

## Verification & Test Results
- `flutter analyze`: **0 issues** found (clean static analysis).
- `flutter test`: **53 tests passing** (100% success rate across core, WAP service, Drift SQLite database, FTS5 virtual table, search engine, indexing service, archive compression, sorting criteria, batch filesystem operations, and UI widget suites).
