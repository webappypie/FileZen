# Phase 02 — Storage Access & File Abstraction

## Objective
Establish Android storage permissions handling, uniform file entity abstraction, high-performance streaming file operations, chunked checksum computation (MD5 & SHA-256), and an interactive storage browser UI following Clean Architecture and Riverpod state management.

## Scope
- Storage permission orchestration (`IPermissionService`, `PermissionService`, `permission_handler`) supporting Android 11+ (`MANAGE_EXTERNAL_STORAGE`), Android 13+ granular media permissions, and Android 10 legacy storage permissions with graceful settings redirection on permanent denial.
- Unified domain file abstractions:
  - `FileEntity`: Rich metadata entity covering files and directories (path, size, mimeType, category, timestamps, hidden status, extension).
  - `FileCategory`: Mime-type and extension classification engine with M3 colors and iconography.
  - `StorageLocation`: Mount/drive representation (internal, SD card, documents, temporary).
  - `FileOperationProgress` & `CancellationToken`: Real-time streaming operational telemetry and cooperative cancellation contracts.
  - `FileConflictStrategy`: Robust collision resolution (overwrite, skip, rename with automatic index generation).
- File operations repository (`IStorageRepository`, `FilesystemStorageRepository`):
  - Storage locations detection with safe fallback handling.
  - Asynchronous directory listing with hidden file filtering and folder-first alphabetical sorting.
  - File/folder creation and rename operations with boundary collision validation.
  - Safe deletion and batch deletion with cooperative cancellation and progress emission.
  - Chunked streaming copy/move pipelines with progress tracking and conflict resolution.
  - Chunked stream checksum computation (MD5 & SHA-256) preventing out-of-memory overhead on multi-gigabyte files.
- Filesystem presentation layer:
  - Riverpod providers (`storagePermissionStateProvider`, `storageLocationsProvider`, `currentDirectoryPathProvider`, `directoryContentsProvider`).
  - Interactive Storage Browser UI in `FilesScreen`:
    - Storage permission request & settings redirect view states.
    - Horizontal storage drive selector cards with capacity telemetry.
    - Path breadcrumb navigation bar with parent folder traversal and List/Grid toggle.
    - Folder creation dialog, item rename dialog, destructive delete confirmation modal, and detailed properties inspector with on-demand MD5 hashing.
- Comprehensive test suite:
  - Unit tests for `FileCategory` resolution across 20+ extensions and MIME formats.
  - Unit tests for `FilesystemStorageRepository` covering CRUD, streaming copy/move collision handling, chunked MD5/SHA256 checksums, and batch deletion progress.
  - Widget tests for `FilesScreen` permission states and storage location rendering.
  - Updated `NavigationShell` widget tests with Riverpod provider overrides.

## Out of Scope
- Full FTS5 search index and incremental background scanner (Phase 03).
- Advanced multi-selection toolbar, batch clipboard operations, and ZIP extraction (Phase 04).
- Media viewers and Media3 playback (Phase 05).
- Document engine and PDF Studio (Phase 06).
- On-device ML Kit OCR models (Phase 07).
- Cleanup algorithms and duplicate detection (Phase 08).
- Vault hardware Keystore encryption (Phase 09).

## Dependencies
- `permission_handler: ^13.0.2`
- `mime: ^2.1.0`
- `crypto: ^3.0.7`
- `path: ^1.9.1`

## Modules & Files Created/Modified
- `android/app/src/main/AndroidManifest.xml` (Storage and media permissions)
- `pubspec.yaml`
- `lib/domain/models/file_category.dart`
- `lib/domain/models/file_entity.dart`
- `lib/domain/models/storage_location.dart`
- `lib/domain/models/file_operation_models.dart`
- `lib/domain/repositories/i_permission_service.dart`
- `lib/data/services/permission_service.dart`
- `lib/domain/repositories/i_storage_repository.dart`
- `lib/data/storage/filesystem_storage_repository.dart`
- `lib/features/files/presentation/providers/storage_providers.dart`
- `lib/features/files/presentation/screens/files_screen.dart`
- `test/unit/file_category_test.dart`
- `test/unit/filesystem_storage_repository_test.dart`
- `test/widget/files_screen_test.dart`
- `test/widget/navigation_shell_test.dart`

## Verification & Test Results
- `flutter analyze`: **0 issues** found.
- `flutter test`: **26 tests passing** (100% success rate across core, WAP client, Drift database, storage repository, category resolution, and widget suites).
