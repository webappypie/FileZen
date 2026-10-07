import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:filezen/data/services/pdf_studio_service.dart';

void main() {
  late Directory tempDir;
  late PdfStudioService service;

  // Minimal 1x1 valid PNG (base64)
  const tinyPngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_pdf_test_');
    service = const PdfStudioService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PdfStudioService - Guard Validation', () {
    test('returns error when imagesToPdf is called with empty images list', () async {
      final res = await service.imagesToPdf([], '${tempDir.path}/out.pdf');
      expect(res.success, isFalse);
      expect(res.errorMessage, contains('No images provided'));
    });

    test('returns error when mergePdfs is called with fewer than 2 documents', () async {
      final res = await service.mergePdfs(['/doc1.pdf'], '${tempDir.path}/out.pdf');
      expect(res.success, isFalse);
      expect(res.errorMessage, contains('At least 2 PDF documents'));
    });

    test('returns error when extractPages is called with empty pages list', () async {
      final res = await service.extractPages('/doc.pdf', [], '${tempDir.path}/out.pdf');
      expect(res.success, isFalse);
      expect(res.errorMessage, contains('No page numbers provided'));
    });

    test('getPdfInfo returns empty metadata gracefully for non-existent file', () async {
      final info = await service.getPdfInfo('${tempDir.path}/non_existent.pdf');
      expect(info.pageCount, 0);
      expect(info.fileSize, 0);
      expect(info.isEncrypted, isFalse);
    });
  });

  group('PdfStudioService - Generation and Metadata Inspection', () {
    test('successfully generates PDF from image files and reads PDF info', () async {
      final img1 = File('${tempDir.path}/image1.png');
      final img2 = File('${tempDir.path}/image2.png');
      final pngBytes = base64Decode(tinyPngBase64);

      await img1.writeAsBytes(pngBytes);
      await img2.writeAsBytes(pngBytes);

      final outputPath = '${tempDir.path}/compiled_gallery.pdf';
      final result = await service.imagesToPdf(
        [img1.path, img2.path],
        outputPath,
        title: 'Gallery Compilation',
        author: 'FileZen User',
      );

      expect(result.success, isTrue);
      expect(result.pagesProcessed, 2);
      expect(result.outputSizeBytes, greaterThan(0));
      expect(File(outputPath).existsSync(), isTrue);

      // Inspect metadata via binary scanner in getPdfInfo
      final info = await service.getPdfInfo(outputPath);
      expect(info.filePath, outputPath);
      expect(info.fileSize, result.outputSizeBytes);
      expect(info.pageCount, 2);
      expect(info.title, 'Gallery Compilation');
      expect(info.author, 'FileZen User');
    });

    test('handles non-existent image paths gracefully during conversion', () async {
      final result = await service.imagesToPdf(
        ['${tempDir.path}/ghost1.jpg', '${tempDir.path}/ghost2.jpg'],
        '${tempDir.path}/never_written.pdf',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('None of the provided image files could be read'));
    });
  });
}
