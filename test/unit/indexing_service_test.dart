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

  group('Index maintenance keyed by path', () {
    Future<int> rowCount(String name) async =>
        (await db.select(db.fileRecords).get()).where((r) => r.name == name).length;

    test('removeFileByPath deletes the record and its full-text entry', () async {
      await indexingService.runIndexScan(targetPaths: [tempDir.path]);
      expect((await searchRepo.search(const SearchQuery(text: 'guidelines'))).dataOrNull!.length, 1);

      // Entity ids (md5 of path/size/mtime) differ from index row ids, so id-based
      // removal cannot work for callers that only hold a FileEntity.
      final entity = await storageRepo.getFileDetails('${tempDir.path}/notes.txt');
      await indexingService.removeFile(entity.id);
      expect(await rowCount('notes.txt'), 1, reason: 'entity id does not address index rows');

      final storedPath = (await db.select(db.fileRecords).get()).firstWhere((r) => r.name == 'notes.txt').path;
      final res = await indexingService.removeFileByPath(storedPath);
      expect(res.isSuccess, isTrue);
      expect(await rowCount('notes.txt'), 0);
      expect((await searchRepo.search(const SearchQuery(text: 'guidelines'))).dataOrNull, isEmpty);
      // Other files are untouched.
      expect(await rowCount('todo.md'), 1);
    });

    test('editing a file so its size changes replaces the old entry instead of duplicating it', () async {
      await indexingService.runIndexScan(targetPaths: [tempDir.path]);
      final notes = File('${tempDir.path}/notes.txt');
      await notes.writeAsString('completely different and much longer replacement text about gardening');
      // Make sure the modification is visible to the incremental check.
      await notes.setLastModified(DateTime.now().add(const Duration(seconds: 5)));

      final res = await indexingService.runIndexScan(targetPaths: [tempDir.path]);
      expect(res.isSuccess, isTrue);
      expect(res.dataOrNull!.errorCount, 0);
      expect(await rowCount('notes.txt'), 1);
      expect((await searchRepo.search(const SearchQuery(text: 'gardening'))).dataOrNull!.length, 1);
      expect((await searchRepo.search(const SearchQuery(text: 'guidelines'))).dataOrNull, isEmpty,
          reason: 'stale text from the previous version must be gone');

      // A further scan must not trip over duplicate rows.
      final again = await indexingService.runIndexScan(targetPaths: [tempDir.path]);
      expect(again.dataOrNull!.errorCount, 0);
      expect(again.dataOrNull!.skippedCount, 3);
    });

    test('a scan heals pre-existing duplicate rows for the same path', () async {
      await indexingService.runIndexScan(targetPaths: [tempDir.path]);
      final original = (await db.select(db.fileRecords).get()).firstWhere((r) => r.name == 'notes.txt');
      // Simulate the leftover from the old behaviour: a second row, same path.
      await db.into(db.fileRecords).insert(FileRecordsCompanion.insert(
            id: 'file_legacy_duplicate',
            path: original.path,
            name: original.name,
            extension: original.extension,
            size: BigInt.from(1),
            modifiedAt: original.modifiedAt,
            createdAt: original.createdAt,
          ));
      expect(await rowCount('notes.txt'), 2);

      final res = await indexingService.runIndexScan(targetPaths: [tempDir.path]);
      expect(res.dataOrNull!.errorCount, 0);
      expect(await rowCount('notes.txt'), 1);
    });
  });
}
