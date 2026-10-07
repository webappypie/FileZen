import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:filezen/data/services/document_service.dart';
import 'package:filezen/domain/models/document_models.dart';

void main() {
  late Directory tempDir;
  late DocumentService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_doc_test_');
    service = const DocumentService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DocumentService - Type Resolution', () {
    test('resolves extensions to expected DocumentType', () {
      expect(service.resolveDocumentType('notes.md'), DocumentType.markdown);
      expect(service.resolveDocumentType('data.csv'), DocumentType.csv);
      expect(service.resolveDocumentType('doc.txt'), DocumentType.plainText);
      expect(service.resolveDocumentType('schema.json'), DocumentType.json);
      expect(service.resolveDocumentType('manifest.xml'), DocumentType.xml);
      expect(service.resolveDocumentType('main.dart'), DocumentType.code);
      expect(service.resolveDocumentType('script.py'), DocumentType.code);
      expect(service.resolveDocumentType('page.html'), DocumentType.xml);
      expect(service.resolveDocumentType('manual.pdf'), DocumentType.pdf);
      expect(service.resolveDocumentType('archive.zip'), DocumentType.unsupported);
      expect(service.resolveDocumentType('blob.bin'), DocumentType.unsupported);
    });

    test('DocumentType getters report correct capabilities', () {
      expect(DocumentType.markdown.isMarkdown, isTrue);
      expect(DocumentType.plainText.isMarkdown, isFalse);
      expect(DocumentType.csv.isCsv, isTrue);
      expect(DocumentType.json.isCsv, isFalse);
      expect(DocumentType.pdf.isPdf, isTrue);
      expect(DocumentType.plainText.isPdf, isFalse);
    });
  });

  group('DocumentService - Read & Analyze', () {
    test('gracefully handles non-existent file', () async {
      final nonExistent = '${tempDir.path}/missing.txt';
      final text = await service.readDocumentText(nonExistent);
      expect(text, isEmpty);

      final meta = await service.analyzeDocument(nonExistent);
      expect(meta.lineCount, 0);
      expect(meta.wordCount, 0);
      expect(meta.characterCount, 0);
      expect(meta.fileSize, 0);
    });

    test('reads and analyzes multi-line markdown file accurately', () async {
      final docFile = File('${tempDir.path}/sample.md');
      const content = '# FileZen\n\nNext-gen local file manager for mobile devices.\nFast and secure.';
      await docFile.writeAsString(content);

      final text = await service.readDocumentText(docFile.path);
      expect(text, content);

      final meta = await service.analyzeDocument(docFile.path);
      expect(meta.type, DocumentType.markdown);
      expect(meta.lineCount, 4);
      expect(meta.wordCount, 12);
      expect(meta.characterCount, content.length);
      expect(meta.fileSize, greaterThan(0));
      expect(meta.isEditable, isTrue);
    });

    test('saves updated document content safely', () async {
      final file = File('${tempDir.path}/editable.txt');
      await file.writeAsString('Original content');

      final success = await service.saveDocumentText(file.path, 'Updated content with edits');
      expect(success, isTrue);

      final reloaded = await file.readAsString();
      expect(reloaded, 'Updated content with edits');
    });
  });

  group('DocumentService - CSV Parsing', () {
    test('parses comma-separated values into tabular data structure', () async {
      final csvFile = File('${tempDir.path}/data.csv');
      const csvContent = 'ID,Name,Role,Score\n1,Alice,Engineer,98.5\n2,Bob,Architect,92.0';
      await csvFile.writeAsString(csvContent);

      final table = await service.parseCsv(csvFile.path);
      expect(table.length, 3);
      expect(table[0], ['ID', 'Name', 'Role', 'Score']);
      expect(table[1][0], 1);
      expect(table[1][1], 'Alice');
      expect(table[1][3], 98.5);
      expect(table[2][0], 2);
      expect(table[2][1], 'Bob');
    });

    test('handles quoted strings with commas and escaped quotes', () async {
      final csvFile = File('${tempDir.path}/complex.csv');
      const csvContent = 'Title,Description,Price\nBook,"A great, fast read",19.99';
      await csvFile.writeAsString(csvContent);

      final table = await service.parseCsv(csvFile.path);
      expect(table.length, 2);
      expect(table[1][0], 'Book');
      expect(table[1][1], 'A great, fast read');
      expect(table[1][2], 19.99);
    });

    test('returns empty table for empty file or missing file', () async {
      final missing = await service.parseCsv('${tempDir.path}/missing.csv');
      expect(missing, isEmpty);

      final emptyFile = File('${tempDir.path}/empty.csv');
      await emptyFile.writeAsString('');
      final emptyResult = await service.parseCsv(emptyFile.path);
      expect(emptyResult, isEmpty);
    });
  });
}
