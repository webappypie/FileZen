import 'dart:io';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FilesystemStorageRepository storageRepo;
  late Directory tempDir;

  setUp(() async {
    storageRepo = FilesystemStorageRepository();
    tempDir = await Directory.systemTemp.createTemp('filezen_batch_test_');

    // Create 3 test files
    for (int i = 1; i <= 3; i++) {
      final f = File('${tempDir.path}/item_$i.txt');
      await f.writeAsString('Item content $i');
    }
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FilesystemStorageRepository Batch & Duplicate Operations', () {
    test('batchCopy copies multiple files to destination directory', () async {
      final destDir = Directory('${tempDir.path}/Destination');
      await destDir.create();

      final sources = [
        '${tempDir.path}/item_1.txt',
        '${tempDir.path}/item_2.txt',
      ];

      final res = await storageRepo.batchCopy(sources, destDir.path);
      expect(res.isSuccess, isTrue);
      expect(res.dataOrNull!.length, 2);

      expect(File('${destDir.path}/item_1.txt').existsSync(), isTrue);
      expect(File('${destDir.path}/item_2.txt').existsSync(), isTrue);
      // Source files still exist after copy
      expect(File('${tempDir.path}/item_1.txt').existsSync(), isTrue);
    });

    test('batchMove moves multiple files and cleans up sources', () async {
      final destDir = Directory('${tempDir.path}/Moved');
      await destDir.create();

      final sources = [
        '${tempDir.path}/item_1.txt',
        '${tempDir.path}/item_2.txt',
      ];

      final res = await storageRepo.batchMove(sources, destDir.path);
      expect(res.isSuccess, isTrue);
      expect(res.dataOrNull!.length, 2);

      expect(File('${destDir.path}/item_1.txt').existsSync(), isTrue);
      expect(File('${destDir.path}/item_2.txt').existsSync(), isTrue);
      // Sources deleted after move
      expect(File('${tempDir.path}/item_1.txt').existsSync(), isFalse);
    });

    test('batchRename renames files to new target names', () async {
      final renameMap = {
        '${tempDir.path}/item_1.txt': 'renamed_one.txt',
        '${tempDir.path}/item_2.txt': 'renamed_two.txt',
      };

      final res = await storageRepo.batchRename(renameMap);
      expect(res.isSuccess, isTrue);
      expect(res.dataOrNull!.length, 2);

      expect(File('${tempDir.path}/renamed_one.txt').existsSync(), isTrue);
      expect(File('${tempDir.path}/renamed_two.txt').existsSync(), isTrue);
      expect(File('${tempDir.path}/item_1.txt').existsSync(), isFalse);
    });

    test('duplicate creates copy with incremented index', () async {
      final res = await storageRepo.duplicate('${tempDir.path}/item_3.txt');
      expect(res.isSuccess, isTrue);

      final duplicated = res.dataOrNull!;
      expect(duplicated.name, 'item_3 (1).txt');
      expect(File(duplicated.path).existsSync(), isTrue);
      expect(File('${tempDir.path}/item_3.txt').existsSync(), isTrue);
    });
  });
}
