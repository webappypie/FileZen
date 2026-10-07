import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filezen/data/ai/auto_rename_service.dart';
import 'package:filezen/data/ai/ocr_service.dart';
import 'package:filezen/data/ai/query_interpreter_service.dart';
import 'package:filezen/data/ai/related_files_service.dart';
import 'package:filezen/data/ai/smart_collections_service.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/services/document_service.dart';
import 'package:filezen/data/indexing/indexing_service.dart';
import 'package:filezen/data/search/search_repository.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/domain/models/ai_models.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FilesystemStorageRepository storageRepo;
  late SearchRepository searchRepo;
  late IndexingService indexingService;
  late OcrService ocrService;
  late DocumentService docService;
  late AutoRenameService autoRenameService;
  late QueryInterpreterService queryInterpreterService;
  late SmartCollectionsService smartCollectionsService;
  late RelatedFilesService relatedFilesService;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storageRepo = FilesystemStorageRepository();
    searchRepo = SearchRepository(db);
    indexingService = IndexingService(db: db, storageRepo: storageRepo);
    ocrService = const OcrService();
    docService = const DocumentService();
    autoRenameService = AutoRenameService(
      storageRepository: storageRepo,
      documentService: docService,
      ocrService: ocrService,
    );
    queryInterpreterService = QueryInterpreterService(searchRepository: searchRepo);
    smartCollectionsService = SmartCollectionsService(searchRepository: searchRepo);
    relatedFilesService = RelatedFilesService(
      storageRepository: storageRepo,
      searchRepository: searchRepo,
    );

    tempDir = await Directory.systemTemp.createTemp('filezen_ai_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('OcrService (On-Device Text & Keyword Extraction)', () {
    test('isOcrAvailable returns true offline', () async {
      expect(await ocrService.isOcrAvailable(), isTrue);
    });

    test('extracts ASCII text and detects receipt tokens', () async {
      final imgFile = File('${tempDir.path}/test_receipt.png');
      // Write sample payload containing ASCII receipt tokens
      final content = 'INVOICE 10928 Store Receipt Total \$42.50 Paid verification code 9921';
      await imgFile.writeAsString(content);

      final result = await ocrService.extractTextFromImage(imgFile.path);
      expect(result.extractedText.toLowerCase(), contains('receipt'));
      expect(result.extractedText.toLowerCase(), contains('invoice'));
      expect(result.confidence, greaterThan(0.0));
    });

    test('handles empty or binary files gracefully', () async {
      final emptyFile = File('${tempDir.path}/empty.jpg');
      await emptyFile.writeAsBytes([]);

      final result = await ocrService.extractTextFromImage(emptyFile.path);
      expect(result.extractedText, isEmpty);
      expect(result.confidence, 0.0);
    });
  });

  group('QueryInterpreterService (Natural Language NLP Parser)', () {
    test('interprets resume query intent', () {
      final intent = queryInterpreterService.interpretQuery('find my resume for work');
      expect(intent.specialIntent, SpecialQueryIntent.resume);
      expect(intent.targetCategory, FileCategory.document);
      expect(intent.interpretedKeywords, contains('resume'));
      expect(intent.explanation, contains('resume'));
    });

    test('interprets otp screenshot query intent', () {
      final intent = queryInterpreterService.interpretQuery('show otp screenshots from today');
      expect(intent.specialIntent, SpecialQueryIntent.otpScreenshot);
      expect(intent.targetCategory, FileCategory.image);
      expect(intent.interpretedKeywords, contains('otp'));
    });

    test('interprets large video query intent with size filter', () {
      final intent = queryInterpreterService.interpretQuery('find videos larger than 100mb');
      expect(intent.specialIntent, SpecialQueryIntent.largeVideos);
      expect(intent.targetCategory, FileCategory.video);
      expect(intent.minSizeBytes, 100 * 1024 * 1024);
    });

    test('interprets receipts and invoices query intent', () {
      final intent = queryInterpreterService.interpretQuery('invoices and receipts');
      expect(intent.specialIntent, SpecialQueryIntent.receiptOrInvoice);
      expect(intent.interpretedKeywords.any((k) => k.contains('receipt') || k.contains('invoice')), isTrue);
    });

    test('interprets identity documents query intent', () {
      final intent = queryInterpreterService.interpretQuery('show my passport and driver license');
      expect(intent.specialIntent, SpecialQueryIntent.idCard);
      expect(intent.interpretedKeywords, contains('passport'));
      expect(intent.interpretedKeywords, contains('license'));
    });

    test('executes Ask Your Files against indexed storage', () async {
      // Create and index mock files
      final resumeFile = File('${tempDir.path}/Software_Engineer_Resume.pdf');
      await resumeFile.writeAsString('Senior Flutter Developer Curriculum Vitae Resume experience');

      final receiptFile = File('${tempDir.path}/Grocery_Receipt.txt');
      await receiptFile.writeAsString('Store Receipt Payment Details Tax total \$25.00');

      await indexingService.runIndexScan(targetPaths: [tempDir.path]);

      final results = await queryInterpreterService.executeAskYourFiles('find my resumes');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.file.name, contains('Resume'));
    });
  });

  group('AutoRenameService (Contextual Renaming & Collision Handling)', () {
    test('proposes clean name for camera photo', () async {
      final photo = File('${tempDir.path}/IMG_20261008_153022.jpg');
      await photo.writeAsBytes([1, 2, 3]);

      final entity = FileEntity(
        id: '1',
        name: 'IMG_20261008_153022.jpg',
        path: photo.path,
        size: 3,
        modifiedAt: DateTime(2026, 10, 8, 15, 30, 22),
        createdAt: DateTime(2026, 10, 8, 15, 30, 22),
        isDirectory: false,
        extension: '.jpg',
        category: FileCategory.image,
      );

      final suggestion = await autoRenameService.generateRenameSuggestion(entity);
      expect(suggestion.suggestedName, startsWith('Photo_2026-10-08'));
      expect(suggestion.hasCollision, isFalse);
    });

    test('extracts title heading from markdown/text document', () async {
      final doc = File('${tempDir.path}/untitled_notes.md');
      await doc.writeAsString('# Architectural Design Specifications\n\nDetailed system overview.');

      final entity = FileEntity(
        id: '2',
        name: 'untitled_notes.md',
        path: doc.path,
        size: 50,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        isDirectory: false,
        extension: '.md',
        category: FileCategory.document,
      );

      final suggestion = await autoRenameService.generateRenameSuggestion(entity);
      expect(suggestion.suggestedName, contains('Architectural_Design_Specifications'));
      expect(suggestion.confidence, greaterThanOrEqualTo(0.9));
    });

    test('handles filename collision by appending numeric suffix', () async {
      // Existing collision file
      final existing = File('${tempDir.path}/Photo_2026-10-08.jpg');
      await existing.writeAsString('Existing content');

      final photo = File('${tempDir.path}/IMG_20261008_153022.jpg');
      await photo.writeAsBytes([1, 2, 3]);

      final entity = FileEntity(
        id: '3',
        name: 'IMG_20261008_153022.jpg',
        path: photo.path,
        size: 3,
        modifiedAt: DateTime(2026, 10, 8, 15, 30, 22),
        createdAt: DateTime(2026, 10, 8, 15, 30, 22),
        isDirectory: false,
        extension: '.jpg',
        category: FileCategory.image,
      );

      final suggestion = await autoRenameService.generateRenameSuggestion(entity);
      expect(suggestion.hasCollision, isTrue);
      expect(suggestion.suggestedName, contains('_1.jpg'));
    });

    test('applies rename and enables safe undo', () async {
      final file = File('${tempDir.path}/ugly_file (1).txt');
      await file.writeAsString('content');

      final entity = FileEntity(
        id: '4',
        name: 'ugly_file (1).txt',
        path: file.path,
        size: 7,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        isDirectory: false,
        extension: '.txt',
        category: FileCategory.document,
      );

      final suggestion = await autoRenameService.generateRenameSuggestion(entity);
      final applied = await autoRenameService.applyRename(suggestion);
      expect(applied, isTrue);

      // Verify file renamed on disk
      expect(await File(suggestion.suggestedPath).exists(), isTrue);
      expect(await File(suggestion.originalPath).exists(), isFalse);

      final history = autoRenameService.getRenameHistory();
      expect(history.length, 1);

      // Undo rename
      final undone = await autoRenameService.undoRename(history.first);
      expect(undone, isTrue);
      expect(await File(suggestion.originalPath).exists(), isTrue);
      expect(await File(suggestion.suggestedPath).exists(), isFalse);
    });
  });

  group('SmartCollectionsService (Virtual Semantic Clusters)', () {
    test('returns 6 predefined collections with live file counts', () async {
      // Create receipt, archive, and code files
      final receipt = File('${tempDir.path}/invoice_payment.pdf');
      await receipt.writeAsString('Invoice Bill receipt payment tax document');

      final zip = File('${tempDir.path}/backup_archive.zip');
      await zip.writeAsBytes([0x50, 0x4B, 0x03, 0x04]);

      await indexingService.runIndexScan(targetPaths: [tempDir.path]);

      final collections = await smartCollectionsService.getSmartCollections();
      expect(collections.length, 6);

      final invoiceCol = collections.firstWhere((c) => c.id == 'invoices_receipts');
      expect(invoiceCol.fileCount, greaterThanOrEqualTo(1));

      final archiveCol = collections.firstWhere((c) => c.id == 'archives');
      expect(archiveCol.fileCount, greaterThanOrEqualTo(1));
    });
  });

  group('RelatedFilesService (Companion File Discovery)', () {
    test('discovers related companion files with matching prefix', () async {
      final specFile = File('${tempDir.path}/project_specification.docx');
      await specFile.writeAsString('spec');

      final signedSpec = File('${tempDir.path}/project_specification_signed.pdf');
      await signedSpec.writeAsString('signed');

      final unrelated = File('${tempDir.path}/unrelated_notes.txt');
      await unrelated.writeAsString('unrelated');

      final entity = FileEntity(
        id: 'spec_1',
        name: 'project_specification.docx',
        path: specFile.path,
        size: 4,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        isDirectory: false,
        extension: '.docx',
        category: FileCategory.document,
      );

      final related = await relatedFilesService.findRelatedFiles(entity);
      expect(related.isNotEmpty, isTrue);
      expect(
        related.any((r) => p.normalize(r.file.path).toLowerCase() == p.normalize(signedSpec.path).toLowerCase()),
        isTrue,
      );
      expect(
        related
            .firstWhere((r) => p.normalize(r.file.path).toLowerCase() == p.normalize(signedSpec.path).toLowerCase())
            .confidenceScore,
        greaterThanOrEqualTo(0.8),
      );
    });
  });
}
