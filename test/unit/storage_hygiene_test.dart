import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:filezen/data/cleanup/deduplication_service.dart';
import 'package:filezen/data/cleanup/storage_hygiene_service.dart';
import 'package:filezen/data/cleanup/timeline_service.dart';
import 'package:filezen/data/cleanup/trash_recovery_service.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/domain/models/cleanup_models.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/timeline_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FilesystemStorageRepository storageRepo;
  late TrashRecoveryService trashService;
  late DeduplicationService dedupService;
  late StorageHygieneService hygieneService;
  late TimelineService timelineService;
  late Directory tempDir;
  late Directory trashDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storageRepo = FilesystemStorageRepository();
    tempDir = await Directory.systemTemp.createTemp('filezen_hygiene_test_');
    trashDir = Directory(p.join(tempDir.path, '.filezen_trash'));
    await trashDir.create(recursive: true);

    trashService = TrashRecoveryService(
      storageRepo: storageRepo,
      customTrashDirectoryPath: trashDir.path,
    );

    dedupService = DeduplicationService(
      db: db,
      storageRepo: storageRepo,
      trashService: trashService,
    );

    hygieneService = StorageHygieneService(
      db: db,
      storageRepo: storageRepo,
      customTrendFilePath: p.join(tempDir.path, 'trends.json'),
    );

    timelineService = TimelineService(
      db: db,
      storageRepo: storageRepo,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('TrashRecoveryService (Safe Recovery & Recycle Bin)', () {
    test('moves file to trash, creates manifest entry, and removes from original path', () async {
      final sampleFile = File(p.join(tempDir.path, 'document.pdf'));
      await sampleFile.writeAsString('Confidential agreement content');
      final entity = await storageRepo.getFileDetails(sampleFile.path);

      final trashRes = await trashService.moveToTrash(entity);
      expect(trashRes.isSuccess, isTrue);
      expect(await sampleFile.exists(), isFalse);

      final trashItem = trashRes.dataOrNull!;
      expect(trashItem.fileName, 'document.pdf');
      expect(trashItem.originalPath, sampleFile.path);
      expect(await File(trashItem.trashPath).exists(), isTrue);

      final trashList = await trashService.listTrash();
      expect(trashList.length, 1);
      expect(trashList.first.id, entity.id);
    });

    test('restores file back to original location and removes from manifest', () async {
      final sampleFile = File(p.join(tempDir.path, 'invoice.txt'));
      await sampleFile.writeAsString('Invoice #1029');
      final entity = await storageRepo.getFileDetails(sampleFile.path);

      final moveRes = await trashService.moveToTrash(entity);
      expect(moveRes.isSuccess, isTrue);
      expect(await sampleFile.exists(), isFalse);

      final restoreRes = await trashService.restoreFromTrash(moveRes.dataOrNull!);
      expect(restoreRes.isSuccess, isTrue);
      expect(await sampleFile.exists(), isTrue);
      expect(await sampleFile.readAsString(), 'Invoice #1029');

      final trashList = await trashService.listTrash();
      expect(trashList.isEmpty, isTrue);
    });

    test('resolves filename collision when restoring to occupied original path', () async {
      final sampleFile = File(p.join(tempDir.path, 'notes.txt'));
      await sampleFile.writeAsString('Original notes');
      final entity = await storageRepo.getFileDetails(sampleFile.path);

      final moveRes = await trashService.moveToTrash(entity);
      expect(moveRes.isSuccess, isTrue);

      // Recreate another file with the same name at original path
      await sampleFile.writeAsString('New file took previous name');

      final restoreRes = await trashService.restoreFromTrash(moveRes.dataOrNull!);
      expect(restoreRes.isSuccess, isTrue);
      expect(restoreRes.dataOrNull!.name, 'notes_restored.txt');
      expect(await File(p.join(tempDir.path, 'notes_restored.txt')).exists(), isTrue);
    });

    test('permanently deletes trash item and empties trash completely', () async {
      final f1 = File(p.join(tempDir.path, 'item1.dat'));
      final f2 = File(p.join(tempDir.path, 'item2.dat'));
      await f1.writeAsString('data 1');
      await f2.writeAsString('data 2');

      final e1 = await storageRepo.getFileDetails(f1.path);
      final e2 = await storageRepo.getFileDetails(f2.path);

      await trashService.batchMoveToTrash([e1, e2]);
      var list = await trashService.listTrash();
      expect(list.length, 2);

      // Permanently delete one
      final delRes = await trashService.permanentlyDelete(list.first);
      expect(delRes.isSuccess, isTrue);
      list = await trashService.listTrash();
      expect(list.length, 1);

      // Empty trash
      final emptyRes = await trashService.emptyTrash();
      expect(emptyRes.isSuccess, isTrue);
      list = await trashService.listTrash();
      expect(list.isEmpty, isTrue);
    });
  });

  group('DeduplicationService (3-Tier Exact Duplicate Detection)', () {
    test('identifies cryptographic duplicate files and designates oldest as primary', () async {
      final subDirA = Directory(p.join(tempDir.path, 'FolderA'))..createSync();
      final subDirB = Directory(p.join(tempDir.path, 'FolderB'))..createSync();

      final origFile = File(p.join(subDirA.path, 'report.docx'));
      final dupeFile1 = File(p.join(subDirB.path, 'report_copy.docx'));
      final uniqueFile = File(p.join(tempDir.path, 'other.docx'));

      const identicalBytes = 'File content identically matching between copies';
      await origFile.writeAsString(identicalBytes);
      // Give different modification timestamp
      await Future.delayed(const Duration(milliseconds: 50));
      await dupeFile1.writeAsString(identicalBytes);
      await uniqueFile.writeAsString('Different unique content length and text');

      final groups = await dedupService.scanExactDuplicates(scanPaths: [tempDir.path]);
      expect(groups.length, 1);

      final group = groups.first;
      expect(group.fileSize, identicalBytes.length);
      expect(group.totalCount, 2);
      expect(group.primaryFile.path, origFile.path);
      expect(group.duplicateFiles.length, 1);
      expect(group.duplicateFiles.first.path, dupeFile1.path);
      expect(group.recoverableSize, identicalBytes.length);
    });

    test('scans similar photos based on burst naming and timestamp proximity', () async {
      File(p.join(tempDir.path, 'IMG_20261008_120000_1.jpg')).writeAsStringSync('photobytes12345');
      File(p.join(tempDir.path, 'IMG_20261008_120000_2.jpg')).writeAsStringSync('photobytes12345');

      final similar = await dedupService.scanSimilarPhotos(
        scanPaths: [tempDir.path],
        burstWindow: const Duration(seconds: 10),
      );
      expect(similar.length, greaterThanOrEqualTo(2));
    });

    test('scans blurry or low-resolution photo candidates', () async {
      final blurry = File(p.join(tempDir.path, 'IMG_blurry_photo.jpg'))..writeAsStringSync('small');
      final normal = File(p.join(tempDir.path, 'normal.png'))..writeAsStringSync('regular bytes');

      final candidates = await dedupService.scanBlurryPhotos(scanPaths: [tempDir.path]);
      expect(candidates.any((f) => f.path == blurry.path), isTrue);
      expect(candidates.any((f) => f.path == normal.path), isFalse);
    });

    test('scans large files exceeding threshold', () async {
      final bigFile = File(p.join(tempDir.path, 'large_archive.zip'));
      // Write 1 KB file, test with minSizeBytes = 500
      await bigFile.writeAsBytes(List.filled(1024, 0));

      final results = await dedupService.scanLargeFiles(
        scanPaths: [tempDir.path],
        minSizeBytes: 500,
      );
      expect(results.length, 1);
      expect(results.first.path, bigFile.path);
    });

    test('scans old APK installers', () async {
      final apk = File(p.join(tempDir.path, 'app_v1.0.apk'))..writeAsStringSync('apk data');
      // Set modification date to 10 days ago
      await apk.setLastModified(DateTime.now().subtract(const Duration(days: 10)));

      final apks = await dedupService.scanOldApks(scanPaths: [tempDir.path], daysOld: 5);
      expect(apks.length, 1);
      expect(apks.first.name, 'app_v1.0.apk');
    });

    test('scans old screenshots', () async {
      final screenshot = File(p.join(tempDir.path, 'Screenshot_20260901.png'))..writeAsStringSync('screen');
      await screenshot.setLastModified(DateTime.now().subtract(const Duration(days: 20)));

      final screenshots = await dedupService.scanOldScreenshots(scanPaths: [tempDir.path], daysOld: 10);
      expect(screenshots.length, 1);
      expect(screenshots.first.name, 'Screenshot_20260901.png');
    });

    test('scans repeated downloads matching copy pattern', () async {
      File(p.join(tempDir.path, 'manual (1).pdf')).writeAsStringSync('download');
      File(p.join(tempDir.path, 'document_copy.pdf')).writeAsStringSync('download');

      final repeated = await dedupService.scanRepeatedDownloads(scanPaths: [tempDir.path]);
      expect(repeated.any((f) => f.name == 'manual (1).pdf'), isTrue);
      expect(repeated.any((f) => f.name == 'document_copy.pdf'), isTrue);
    });

    test('scans empty folders and deletes them safely', () async {
      final empty1 = Directory(p.join(tempDir.path, 'EmptyDir1'))..createSync();
      final nonEmpty = Directory(p.join(tempDir.path, 'FullDir'))..createSync();
      File(p.join(nonEmpty.path, 'file.txt')).writeAsStringSync('contents');

      final emptyList = await dedupService.scanEmptyFolders(scanPaths: [tempDir.path]);
      expect(emptyList.contains(empty1.path), isTrue);
      expect(emptyList.contains(nonEmpty.path), isFalse);

      final deleted = await dedupService.deleteEmptyFolders([empty1.path]);
      expect(deleted, 1);
      expect(await empty1.exists(), isFalse);
    });

    test('executes cleanup plan safely with Recycle Bin routing', () async {
      final f1 = File(p.join(tempDir.path, 'cleanup_candidate.txt'))..writeAsStringSync('trash me');
      final entity = await storageRepo.getFileDetails(f1.path);

      final plan = CleanupExecutionPlan(
        selectedFiles: [entity],
        totalBytesToFree: entity.size,
        moveToTrash: true,
      );

      final result = await dedupService.executeCleanup(plan);
      expect(result.success, isTrue);
      expect(result.itemsCleaned, 1);
      expect(result.movedToTrash, isTrue);
      expect(await f1.exists(), isFalse);

      final trashed = await trashService.listTrash();
      expect(trashed.length, 1);
    });
  });

  group('StorageHygieneService (Storage Intelligence & Trends)', () {
    test('computes storage overview across categories', () async {
      File(p.join(tempDir.path, 'photo.jpg')).writeAsStringSync('image bytes');
      File(p.join(tempDir.path, 'manual.pdf')).writeAsStringSync('doc bytes');

      final overview = await hygieneService.getStorageOverview(targetPaths: [tempDir.path]);
      expect(overview.totalBytes, greaterThan(0));
      expect(overview.sizeForCategory(FileCategory.image), greaterThan(0));
      expect(overview.sizeForCategory(FileCategory.document), greaterThan(0));
      expect(overview.usedRatio, greaterThanOrEqualTo(0.0));
    });

    test('computes top folders and largest files', () async {
      final sub = Directory(p.join(tempDir.path, 'SubFolder'))..createSync();
      File(p.join(sub.path, 'huge.dat')).writeAsBytesSync(List.filled(2048, 1));

      final topFolders = await hygieneService.getTopFolders(targetPaths: [tempDir.path]);
      expect(topFolders.isNotEmpty, isTrue);
      expect(topFolders.first.sizeBytes, greaterThanOrEqualTo(2048));

      final largest = await hygieneService.getLargestFiles(targetPaths: [tempDir.path], minSizeBytes: 1000);
      expect(largest.isNotEmpty, isTrue);
      expect(largest.first.name, 'huge.dat');
    });

    test('loads storage trends and records new snapshot point', () async {
      final trendsBefore = await hygieneService.getStorageTrends();
      expect(trendsBefore.isNotEmpty, isTrue);

      await hygieneService.recordCurrentStorageSnapshot(targetPaths: [tempDir.path]);
      final trendsAfter = await hygieneService.getStorageTrends();
      expect(trendsAfter.length, greaterThanOrEqualTo(trendsBefore.length));
    });
  });

  group('TimelineService (Chronological Timeline Feeds)', () {
    test('groups files into calendar timeline buckets', () async {
      File(p.join(tempDir.path, 'today.txt')).writeAsStringSync('today');
      final yesterdayFile = File(p.join(tempDir.path, 'yesterday.txt'))..writeAsStringSync('yesterday');
      await yesterdayFile.setLastModified(DateTime.now().subtract(const Duration(days: 1, hours: 2)));

      final pastYearFile = File(p.join(tempDir.path, 'old.txt'))..writeAsStringSync('old');
      await pastYearFile.setLastModified(DateTime(2024, 5, 1));

      final groups = await timelineService.getTimelineGroups(targetPaths: [tempDir.path]);
      expect(groups.isNotEmpty, isTrue);

      final hasToday = groups.any((g) => g.bucket == TimelineBucket.today);
      final hasYesterday = groups.any((g) => g.bucket == TimelineBucket.yesterday);
      final hasPastYears = groups.any((g) => g.bucket == TimelineBucket.pastYears);

      expect(hasToday, isTrue);
      expect(hasYesterday, isTrue);
      expect(hasPastYears, isTrue);
    });

    test('filters timeline groups by FileCategory', () async {
      File(p.join(tempDir.path, 'snap.jpg')).writeAsStringSync('img');
      File(p.join(tempDir.path, 'doc.pdf')).writeAsStringSync('pdf');

      final imgGroups = await timelineService.getTimelineGroups(
        categoryFilter: FileCategory.image,
        targetPaths: [tempDir.path],
      );

      for (final group in imgGroups) {
        for (final file in group.files) {
          expect(file.category, FileCategory.image);
        }
      }
    });
  });
}
