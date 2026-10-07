import 'dart:io';
import 'package:filezen/data/services/archive_service.dart';
import 'package:filezen/domain/models/file_operation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ArchiveService archiveService;
  late Directory tempDir;

  setUp(() async {
    archiveService = ArchiveService();
    tempDir = await Directory.systemTemp.createTemp('filezen_archive_test_');

    // Create sample files
    final file1 = File('${tempDir.path}/doc1.txt');
    await file1.writeAsString('Content of document 1');

    final subDir = Directory('${tempDir.path}/subfolder');
    await subDir.create();

    final file2 = File('${subDir.path}/doc2.txt');
    await file2.writeAsString('Content of document 2 in subfolder');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ArchiveService ZIP Operations', () {
    test('creates and extracts a ZIP archive successfully', () async {
      final zipPath = '${tempDir.path}/output_archive.zip';
      final extractDir = '${tempDir.path}/extracted_output';

      // 1. Create ZIP
      final zipRes = await archiveService.createZipArchive(
        sourcePaths: ['${tempDir.path}/doc1.txt', '${tempDir.path}/subfolder'],
        targetZipPath: zipPath,
      );

      expect(zipRes.isSuccess, isTrue);
      expect(File(zipPath).existsSync(), isTrue);
      expect(File(zipPath).lengthSync(), greaterThan(0));

      // 2. Extract ZIP
      final extractRes = await archiveService.extractZipArchive(
        zipFilePath: zipPath,
        destinationDirectory: extractDir,
      );

      expect(extractRes.isSuccess, isTrue);
      expect(Directory(extractDir).existsSync(), isTrue);

      final extractedFile1 = File('$extractDir/doc1.txt');
      expect(extractedFile1.existsSync(), isTrue);
      expect(extractedFile1.readAsStringSync(), 'Content of document 1');

      final extractedFile2 = File('$extractDir/subfolder/doc2.txt');
      expect(extractedFile2.existsSync(), isTrue);
      expect(extractedFile2.readAsStringSync(), 'Content of document 2 in subfolder');
    });

    test('cooperatively cancels ZIP archive creation', () async {
      final zipPath = '${tempDir.path}/cancelled_archive.zip';
      final token = CancellationToken()..cancel();

      final res = await archiveService.createZipArchive(
        sourcePaths: ['${tempDir.path}/doc1.txt'],
        targetZipPath: zipPath,
        cancellationToken: token,
      );

      expect(res.isFailure, isTrue);
    });
  });
}
