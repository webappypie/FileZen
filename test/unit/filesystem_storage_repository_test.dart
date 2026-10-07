import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_operation_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late FilesystemStorageRepository repository;
  late Directory tempDir;

  setUp(() {
    repository = FilesystemStorageRepository();
    tempDir = Directory.systemTemp.createTempSync('filezen_storage_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('FilesystemStorageRepository Operations', () {
    test('creates and lists folders and files', () async {
      // 1. Create a folder
      final folderRes = await repository.createFolder(tempDir.path, 'Documents');
      expect(folderRes.isSuccess, isTrue);
      final folderEntity = folderRes.dataOrNull!;
      expect(folderEntity.name, 'Documents');
      expect(folderEntity.isDirectory, isTrue);

      // 2. Create a file with contents
      final sampleBytes = utf8.encode('Hello FileZen! Testing storage access.');
      final fileRes = await repository.createFile(folderEntity.path, 'notes.txt', sampleBytes);
      expect(fileRes.isSuccess, isTrue);
      final fileEntity = fileRes.dataOrNull!;
      expect(fileEntity.name, 'notes.txt');
      expect(fileEntity.size, sampleBytes.length);
      expect(fileEntity.category, FileCategory.document);

      // 3. List directory
      final items = await repository.listDirectory(folderEntity.path);
      expect(items.length, 1);
      expect(items.first.name, 'notes.txt');
    });

    test('calculates accurate MD5 and SHA-256 checksums', () async {
      const content = 'Reliable checksum calculation stream';
      final fileRes = await repository.createFile(tempDir.path, 'checksum_test.txt', utf8.encode(content));
      expect(fileRes.isSuccess, isTrue);

      final expectedMd5 = md5.convert(utf8.encode(content)).toString();
      final calculatedMd5 = await repository.calculateChecksum(fileRes.dataOrNull!.path, algorithm: 'md5');
      expect(calculatedMd5, expectedMd5);

      final expectedSha = sha256.convert(utf8.encode(content)).toString();
      final calculatedSha = await repository.calculateChecksum(fileRes.dataOrNull!.path, algorithm: 'sha256');
      expect(calculatedSha, expectedSha);
    });

    test('renames files correctly and prevents empty or colliding names', () async {
      final fileRes = await repository.createFile(tempDir.path, 'initial.txt', utf8.encode('test'));
      expect(fileRes.isSuccess, isTrue);

      // Rename to valid new name
      final renameRes = await repository.rename(fileRes.dataOrNull!.path, 'renamed.txt');
      expect(renameRes.isSuccess, isTrue);
      expect(renameRes.dataOrNull!.name, 'renamed.txt');
      expect(File(p.join(tempDir.path, 'initial.txt')).existsSync(), isFalse);
      expect(File(p.join(tempDir.path, 'renamed.txt')).existsSync(), isTrue);

      // Empty name should fail
      final emptyRes = await repository.rename(renameRes.dataOrNull!.path, '   ');
      expect(emptyRes.isFailure, isTrue);
    });

    test('copies and moves files with streaming and conflict resolution', () async {
      final subDir = Directory(p.join(tempDir.path, 'Destination'))..createSync();

      // Create initial source file
      final fileRes = await repository.createFile(tempDir.path, 'photo.jpg', utf8.encode('image_data_bytes'));
      expect(fileRes.isSuccess, isTrue);

      // Copy to Destination
      final copyRes = await repository.copyFile(fileRes.dataOrNull!.path, subDir.path);
      expect(copyRes.isSuccess, isTrue);
      expect(File(fileRes.dataOrNull!.path).existsSync(), isTrue);
      expect(File(p.join(subDir.path, 'photo.jpg')).existsSync(), isTrue);

      // Copy again with renameNew conflict strategy
      final copyCollisionRes = await repository.copyFile(
        fileRes.dataOrNull!.path,
        subDir.path,
        conflictStrategy: FileConflictStrategy.renameNew,
      );
      expect(copyCollisionRes.isSuccess, isTrue);
      expect(copyCollisionRes.dataOrNull!.name, 'photo (1).jpg');
      expect(File(p.join(subDir.path, 'photo (1).jpg')).existsSync(), isTrue);

      // Move file
      final moveRes = await repository.moveFile(fileRes.dataOrNull!.path, subDir.path);
      expect(moveRes.isSuccess, isTrue);
      expect(File(fileRes.dataOrNull!.path).existsSync(), isFalse); // Source deleted
    });

    test('deletes files and directories safely', () async {
      final fileRes = await repository.createFile(tempDir.path, 'to_delete.tmp', [1, 2, 3]);
      expect(fileRes.isSuccess, isTrue);

      final deleteRes = await repository.delete(fileRes.dataOrNull!.path);
      expect(deleteRes.isSuccess, isTrue);
      expect(File(fileRes.dataOrNull!.path).existsSync(), isFalse);
    });

    test('batchDelete reports progress and deletes all target items', () async {
      final paths = <String>[];
      for (int i = 0; i < 3; i++) {
        final res = await repository.createFile(tempDir.path, 'batch_$i.tmp', [i]);
        paths.add(res.dataOrNull!.path);
      }

      int progressEvents = 0;
      final batchRes = await repository.batchDelete(
        paths,
        onProgress: (p) => progressEvents++,
      );

      expect(batchRes.isSuccess, isTrue);
      expect(progressEvents, greaterThanOrEqualTo(3));
      for (final p in paths) {
        expect(File(p).existsSync(), isFalse);
      }
    });
  });
}
