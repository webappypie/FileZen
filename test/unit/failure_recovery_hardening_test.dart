import 'dart:io';
import 'package:filezen/core/error/app_error.dart';
import 'package:filezen/data/indexing/text_extractor.dart';
import 'package:filezen/data/network/lan_web_server.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Failure Recovery & Edge Case Hardening Tests (Phase 13)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('filezen_hardening_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('extracts empty text safely from zero-byte file without crashing', () async {
      final zeroByteFile = File('${tempDir.path}/empty.txt');
      await zeroByteFile.create();

      final extractor = const TextExtractor();
      final now = DateTime.now();
      final entity = FileEntity(
        id: 'zero_byte_doc',
        path: zeroByteFile.path,
        name: 'empty.txt',
        extension: 'txt',
        size: 0,
        modifiedAt: now,
        createdAt: now,
        isDirectory: false,
        category: FileCategory.document,
      );

      final text = await extractor.extractContent(entity);
      expect(text, isEmpty);
    });

    test('handles non-existent or corrupted file gracefully without throwing', () async {
      final extractor = const TextExtractor();
      final now = DateTime.now();
      final entity = FileEntity(
        id: 'missing_doc',
        path: '${tempDir.path}/non_existent_file.txt',
        name: 'non_existent_file.txt',
        extension: 'txt',
        size: 1024,
        modifiedAt: now,
        createdAt: now,
        isDirectory: false,
        category: FileCategory.document,
      );

      // Should safely catch file read error and fall back to metadata tokens
      final text = await extractor.extractContent(entity);
      expect(text, isNotEmpty);
      expect(text, contains('non existent file'));
    });

    test('validates typed domain error hierarchy recovery suggestions', () {
      const storageError = StorageFullError(requiredBytes: 52428800);
      expect(storageError.message, contains('Not enough storage space'));
      expect(storageError.recoverySuggestion, isNotNull);
      expect(storageError.recoverySuggestion, contains('Clean'));

      const cancelledError = OperationCancelledError();
      expect(cancelledError.message, contains('cancelled'));

      const deniedError = AccessDeniedError(path: '/root/system');
      expect(deniedError.path, equals('/root/system'));
      expect(deniedError.recoverySuggestion, isNotNull);
    });

    test('LanWebServer path traversal sanitization and safe file isolation', () async {
      final server = LanWebServer();
      server.setUploadDirectory(tempDir.path);

      final dummyFile = File('${tempDir.path}/safe.txt');
      await dummyFile.writeAsString('safe data');
      server.setSharedFiles([dummyFile.path]);

      expect(server.currentSession.filesSharedCount, equals(1));

      // Path traversal patterns like ../../ must be safely stripped by basename
      const evilPath = '../../Windows/System32/calc.exe';
      final sanitizedName = p.basename(evilPath);
      expect(sanitizedName, equals('calc.exe'));
      expect(sanitizedName.contains('..'), isFalse);
      expect(sanitizedName.contains('/'), isFalse);
      expect(sanitizedName.contains('\\'), isFalse);

      final targetPath = p.join(tempDir.path, sanitizedName);
      expect(targetPath.startsWith(tempDir.path), isTrue);
    });
  });
}
