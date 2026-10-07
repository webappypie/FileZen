import 'dart:io';
import 'package:drift/native.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/indexing/indexing_service.dart';
import 'package:filezen/data/search/search_repository.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/domain/models/file_operation_models.dart';
import 'package:filezen/domain/models/indexing_progress.dart';
import 'package:filezen/domain/models/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FilesystemStorageRepository storageRepo;
  late IndexingService indexingService;
  late SearchRepository searchRepo;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storageRepo = FilesystemStorageRepository();
    indexingService = IndexingService(db: db, storageRepo: storageRepo);
    searchRepo = SearchRepository(db);

    tempDir = await Directory.systemTemp.createTemp('filezen_indexing_test_');

    // Create test files
    final notes = File('${tempDir.path}/notes.txt');
    await notes.writeAsString('FileZen Architecture documentation and guidelines');

    final todo = File('${tempDir.path}/todo.md');
    await todo.writeAsString('Implement ML Kit OCR in Phase 07');

    final bin = File('${tempDir.path}/image.jpg');
    await bin.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('IndexingService Engine & Incremental Scanning', () {
    test('indexes newly discovered files into SQLite and FTS5', () async {
      final res = await indexingService.runIndexScan(targetPaths: [tempDir.path]);
      expect(res.isSuccess, isTrue);

      final progress = res.dataOrNull!;
      expect(progress.status, IndexingStatus.completed);
      expect(progress.totalFilesDiscovered, 3);
      expect(progress.indexedCount, 3);
      expect(progress.skippedCount, 0);

      // Verify files can be found via FTS5 search
      final searchRes = await searchRepo.search(const SearchQuery(text: 'guidelines'));
      expect(searchRes.isSuccess, isTrue);
      expect(searchRes.dataOrNull!.length, 1);
      expect(searchRes.dataOrNull!.first.file.name, 'notes.txt');
    });

    test('incremental scan skips unchanged files without re-indexing', () async {
      // 1st scan
      await indexingService.runIndexScan(targetPaths: [tempDir.path]);

      // 2nd scan without file changes
      final secondScan = await indexingService.runIndexScan(targetPaths: [tempDir.path]);
      expect(secondScan.isSuccess, isTrue);

      final progress = secondScan.dataOrNull!;
      expect(progress.indexedCount, 0);
      expect(progress.skippedCount, 3);
    });

    test('re-indexes only modified files during subsequent scans', () async {
      // 1st scan
      await indexingService.runIndexScan(targetPaths: [tempDir.path]);

      // Modify todo.md
      final todo = File('${tempDir.path}/todo.md');
      await todo.writeAsString('Updated task: Super fast on-device search engine');
      await todo.setLastModified(DateTime.now().add(const Duration(seconds: 5)));

      // 2nd scan
      final nextScan = await indexingService.runIndexScan(targetPaths: [tempDir.path]);
      expect(nextScan.isSuccess, isTrue);

      final progress = nextScan.dataOrNull!;
      expect(progress.indexedCount, 1);
      expect(progress.skippedCount, 2);

      // Verify updated content matches
      final searchUpdated = await searchRepo.search(const SearchQuery(text: 'engine'));
      expect(searchUpdated.dataOrNull!.length, 1);
      expect(searchUpdated.dataOrNull!.first.file.name, 'todo.md');
    });

    test('removes file from database and FTS5 index', () async {
      await indexingService.runIndexScan(targetPaths: [tempDir.path]);

      final before = await searchRepo.search(const SearchQuery(text: 'guidelines'));
      expect(before.dataOrNull!.length, 1);
      final fileId = before.dataOrNull!.first.file.id;

      await indexingService.removeFile(fileId);

      final after = await searchRepo.search(const SearchQuery(text: 'guidelines'));
      expect(after.dataOrNull!.isEmpty, isTrue);
    });

    test('cancels indexing scan cooperatively via CancellationToken', () async {
      final token = CancellationToken()..cancel();
      final res = await indexingService.runIndexScan(
        targetPaths: [tempDir.path],
        cancellationToken: token,
      );

      expect(res.isFailure, isTrue);
      expect(indexingService.currentProgress.status, IndexingStatus.cancelled);
    });
  });
}
