import 'dart:io';
import 'package:archive/archive.dart';
import 'package:filezen/core/error/app_error.dart';
import 'package:filezen/data/services/archive_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late ArchiveService archiveService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_archive_sec_test_');
    archiveService = ArchiveService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File createTestZip(List<ArchiveFile> files, String zipName) {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(f);
    }
    final encoded = ZipEncoder().encode(archive)!;
    final zipFile = File(p.join(tempDir.path, zipName));
    zipFile.writeAsBytesSync(encoded);
    return zipFile;
  }

  group('ArchiveService Security Hardening (P0-12)', () {
    test('blocks simple directory traversal (../evil.txt)', () async {
      final destDir = Directory(p.join(tempDir.path, 'extract_target'));
      await destDir.create();

      final zipFile = createTestZip([
        ArchiveFile('../escaped_file.txt', 12, 'pwned_payload'.codeUnits),
      ], 'traversal_simple.zip');

      final result = await archiveService.extractZipArchive(
        zipFilePath: zipFile.path,
        destinationDirectory: destDir.path,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<SecurityError>());
      expect(
        result.errorOrNull!.message,
        contains('directory traversal sequence'),
      );

      // Verify no escaped file was written outside target
      final escapedFile = File(p.join(tempDir.path, 'escaped_file.txt'));
      expect(await escapedFile.exists(), isFalse);
    });

    test('blocks multi-level directory traversal (../../../../evil.txt)', () async {
      final destDir = Directory(p.join(tempDir.path, 'nested', 'target'));
      await destDir.create(recursive: true);

      final zipFile = createTestZip([
        ArchiveFile('../../evil_payload.txt', 11, 'root_attack'.codeUnits),
      ], 'traversal_multi.zip');

      final result = await archiveService.extractZipArchive(
        zipFilePath: zipFile.path,
        destinationDirectory: destDir.path,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<SecurityError>());

      final escapedFile = File(p.join(tempDir.path, 'evil_payload.txt'));
      expect(await escapedFile.exists(), isFalse);
    });

    test('blocks absolute Unix root path (/tmp/evil.txt)', () async {
      final destDir = Directory(p.join(tempDir.path, 'extract_target'));
      await destDir.create();

      final zipFile = createTestZip([
        ArchiveFile('/tmp/malicious.txt', 12, 'system_attack'.codeUnits),
      ], 'absolute_unix.zip');

      final result = await archiveService.extractZipArchive(
        zipFilePath: zipFile.path,
        destinationDirectory: destDir.path,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<SecurityError>());
      expect(result.errorOrNull!.message, contains('absolute path'));
    });

    test('blocks absolute Windows drive path (C:\\evil.txt)', () async {
      final destDir = Directory(p.join(tempDir.path, 'extract_target'));
      await destDir.create();

      final zipFile = createTestZip([
        ArchiveFile('C:\\Windows\\System32\\evil.dll', 10, 'fake_dll_data'.codeUnits),
      ], 'absolute_windows.zip');

      final result = await archiveService.extractZipArchive(
        zipFilePath: zipFile.path,
        destinationDirectory: destDir.path,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<SecurityError>());
    });

    test('blocks path with null byte injection (safe.txt\\0evil.txt)', () async {
      final destDir = Directory(p.join(tempDir.path, 'extract_target'));
      await destDir.create();

      final zipFile = createTestZip([
        ArchiveFile('safe.txt\x00evil.txt', 9, 'null_test'.codeUnits),
      ], 'null_byte.zip');

      final result = await archiveService.extractZipArchive(
        zipFilePath: zipFile.path,
        destinationDirectory: destDir.path,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<SecurityError>());
      expect(result.errorOrNull!.message, contains('null characters'));
    });

    test('extracts valid nested directories safely', () async {
      final destDir = Directory(p.join(tempDir.path, 'extract_target'));
      await destDir.create();

      final zipFile = createTestZip([
        ArchiveFile('documents/notes.txt', 9, 'hello zen'.codeUnits),
        ArchiveFile('documents/subfolder/data.csv', 11, 'id,name\n1,a'.codeUnits),
      ], 'valid_archive.zip');

      final result = await archiveService.extractZipArchive(
        zipFilePath: zipFile.path,
        destinationDirectory: destDir.path,
      );

      expect(result.isSuccess, isTrue);

      final notesFile = File(p.join(destDir.path, 'documents', 'notes.txt'));
      final csvFile = File(p.join(destDir.path, 'documents', 'subfolder', 'data.csv'));

      expect(await notesFile.exists(), isTrue);
      expect(await csvFile.exists(), isTrue);
      expect(await notesFile.readAsString(), 'hello zen');
    });

    test('rolls back partially extracted files when a malicious entry is detected', () async {
      final destDir = Directory(p.join(tempDir.path, 'extract_target'));
      await destDir.create();

      final zipFile = createTestZip([
        ArchiveFile('valid1.txt', 10, 'clean data'.codeUnits),
        ArchiveFile('../malicious.txt', 9, 'bad stuff'.codeUnits),
      ], 'mixed_archive.zip');

      final result = await archiveService.extractZipArchive(
        zipFilePath: zipFile.path,
        destinationDirectory: destDir.path,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<SecurityError>());

      // Pre-validation blocks before writing any files
      final validFile = File(p.join(destDir.path, 'valid1.txt'));
      expect(await validFile.exists(), isFalse);
    });
  });
}
