import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filezen/domain/models/document_models.dart';
import 'package:filezen/domain/repositories/i_document_service.dart';
import 'package:filezen/domain/repositories/i_pdf_studio_service.dart';
import 'package:filezen/features/documents/presentation/providers/document_providers.dart';
import 'package:filezen/features/documents/presentation/screens/document_viewer_screen.dart';
import 'package:filezen/features/documents/presentation/screens/pdf_studio_screen.dart';

class FakeDocumentService implements IDocumentService {
  String savedContent = '';

  @override
  DocumentType resolveDocumentType(String filePath) {
    if (filePath.endsWith('.md')) return DocumentType.markdown;
    if (filePath.endsWith('.csv')) return DocumentType.csv;
    if (filePath.endsWith('.txt')) return DocumentType.plainText;
    return DocumentType.code;
  }

  @override
  Future<String> readDocumentText(String filePath, {int? maxBytes}) async {
    if (filePath.endsWith('.md')) {
      return '# FileZen Markdown\n\nThis is a sample markdown paragraph.';
    }
    if (filePath.endsWith('.csv')) {
      return 'Header1,Header2\nValue1,Value2';
    }
    return 'Line 1: Hello World\nLine 2: FileZen Text';
  }

  @override
  Future<DocumentMetadata> analyzeDocument(String filePath) async {
    return DocumentMetadata(
      filePath: filePath,
      type: resolveDocumentType(filePath),
      fileSize: 1024,
      lineCount: 2,
      wordCount: 8,
      characterCount: 45,
      encoding: 'UTF-8',
      isEditable: true,
    );
  }

  @override
  Future<bool> saveDocumentText(String filePath, String content) async {
    savedContent = content;
    return true;
  }

  @override
  Future<List<List<dynamic>>> parseCsv(String filePath) async {
    return [
      ['Product', 'Qty', 'Price'],
      ['Zen Keyboard', 5, 89.99],
      ['Zen Mouse', 12, 49.99],
    ];
  }
}

class FakePdfStudioService implements IPdfStudioService {
  @override
  Future<PdfDocumentInfo> getPdfInfo(String filePath) async {
    return PdfDocumentInfo(
      filePath: filePath,
      pageCount: 3,
      fileSize: 2048,
      title: 'Sample PDF',
    );
  }

  @override
  Future<PdfOperationResult> imagesToPdf(
    List<String> imagePaths,
    String outputPath, {
    String? title,
    String? author,
  }) async {
    return PdfOperationResult(
      success: true,
      outputPath: outputPath,
      pagesProcessed: imagePaths.length,
      outputSizeBytes: 1024,
    );
  }

  @override
  Future<PdfOperationResult> mergePdfs(List<String> pdfPaths, String outputPath) async {
    return PdfOperationResult(
      success: true,
      outputPath: outputPath,
      pagesProcessed: 4,
      outputSizeBytes: 4096,
    );
  }

  @override
  Future<PdfOperationResult> extractPages(
    String sourcePdfPath,
    List<int> pageNumbers,
    String outputPath,
  ) async {
    return PdfOperationResult(
      success: true,
      outputPath: outputPath,
      pagesProcessed: pageNumbers.length,
      outputSizeBytes: 2048,
    );
  }
}

void main() {
  late FakeDocumentService fakeDocService;
  late FakePdfStudioService fakePdfService;

  setUp(() {
    fakeDocService = FakeDocumentService();
    fakePdfService = FakePdfStudioService();
  });

  Widget createSubject(Widget child) {
    return ProviderScope(
      overrides: [
        documentServiceProvider.overrideWithValue(fakeDocService),
        pdfStudioServiceProvider.overrideWithValue(fakePdfService),
        documentTextProvider('/docs/notes.md').overrideWith((ref) async => '# FileZen Markdown\n\nThis is a sample markdown paragraph.'),
        documentMetadataProvider('/docs/notes.md').overrideWith((ref) async => fakeDocService.analyzeDocument('/docs/notes.md')),
        documentTextProvider('/docs/data.csv').overrideWith((ref) async => 'Header1,Header2\nValue1,Value2'),
        documentMetadataProvider('/docs/data.csv').overrideWith((ref) async => fakeDocService.analyzeDocument('/docs/data.csv')),
        csvTableDataProvider('/docs/data.csv').overrideWith((ref) async => fakeDocService.parseCsv('/docs/data.csv')),
        documentTextProvider('/docs/plain.txt').overrideWith((ref) async => 'Line 1: Hello World\nLine 2: FileZen Text'),
        documentMetadataProvider('/docs/plain.txt').overrideWith((ref) async => fakeDocService.analyzeDocument('/docs/plain.txt')),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('DocumentViewerScreen Widget Tests', () {
    testWidgets('renders Markdown content and supports toggle between rendered & raw view', (tester) async {
      await tester.pumpWidget(createSubject(const DocumentViewerScreen(filePath: '/docs/notes.md')));
      await tester.pumpAndSettle();

      expect(find.text('notes.md'), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);
      expect(find.text('FileZen Markdown'), findsOneWidget);

      // Toggle to raw source mode
      final rawToggleBtn = find.byTooltip('Show Raw Source');
      expect(rawToggleBtn, findsOneWidget);
      await tester.tap(rawToggleBtn);
      await tester.pumpAndSettle();

      // Now raw mode displays text with line numbers
      expect(find.text('1'), findsOneWidget);
      expect(find.byTooltip('Show Rendered View'), findsOneWidget);
    });

    testWidgets('renders CSV table with columns and supports cell search filtering', (tester) async {
      await tester.pumpWidget(createSubject(const DocumentViewerScreen(filePath: '/docs/data.csv')));
      await tester.pumpAndSettle();

      expect(find.text('data.csv'), findsOneWidget);
      expect(find.text('Product'), findsOneWidget);
      expect(find.text('Zen Keyboard'), findsOneWidget);
      expect(find.text('Zen Mouse'), findsOneWidget);

      // Open search in document
      final searchIconBtn = find.byTooltip('Find in Document');
      await tester.tap(searchIconBtn);
      await tester.pumpAndSettle();

      // Search inside CSV table
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Keyboard');
      await tester.pumpAndSettle();

      expect(find.text('Zen Keyboard'), findsOneWidget);
      expect(find.text('Zen Mouse'), findsNothing);
    });

    testWidgets('supports live editing and saves updated text', (tester) async {
      await tester.pumpWidget(createSubject(const DocumentViewerScreen(filePath: '/docs/plain.txt')));
      await tester.pumpAndSettle();

      expect(find.text('plain.txt'), findsOneWidget);
      expect(find.textContaining('Hello World'), findsOneWidget);

      // Enter edit mode
      final editBtn = find.byTooltip('Edit Document');
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);

      // Modify content
      final editableField = find.byType(TextField);
      await tester.enterText(editableField, 'Brand new saved content');
      await tester.pumpAndSettle();

      // Tap Save
      final saveBtn = find.byTooltip('Save Changes');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(fakeDocService.savedContent, 'Brand new saved content');
      expect(find.text('Document saved successfully'), findsOneWidget);
    });

    testWidgets('displays document properties sheet on info tap', (tester) async {
      await tester.pumpWidget(createSubject(const DocumentViewerScreen(filePath: '/docs/notes.md')));
      await tester.pumpAndSettle();

      final infoBtn = find.byTooltip('Document Info');
      expect(infoBtn, findsOneWidget);
      await tester.tap(infoBtn);
      await tester.pumpAndSettle();

      expect(find.text('Lines'), findsOneWidget);
      expect(find.text('Words'), findsOneWidget);
      expect(find.text('Characters'), findsOneWidget);
      expect(find.text('Encoding'), findsOneWidget);
      expect(find.text('UTF-8'), findsAtLeastNWidgets(1));
    });
  });

  group('PdfStudioScreen Widget Tests', () {
    testWidgets('renders all three studio tabs and validates input requirements', (tester) async {
      await tester.pumpWidget(createSubject(const PdfStudioScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Images to PDF'), findsOneWidget);
      expect(find.text('Merge PDFs'), findsOneWidget);
      expect(find.text('Extract Pages'), findsOneWidget);

      // Empty images conversion shows validation snackbar
      final convertBtn = find.widgetWithText(FilledButton, 'Convert to PDF');
      expect(convertBtn, findsOneWidget);
      await tester.tap(convertBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter at least one image file path'), findsOneWidget);

      // Switch to Merge tab
      await tester.tap(find.widgetWithText(Tab, 'Merge PDFs'));
      await tester.pumpAndSettle();

      final mergeBtn = find.widgetWithText(FilledButton, 'Merge PDFs');
      expect(mergeBtn, findsOneWidget);
      await tester.tap(mergeBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter at least two PDF file paths to merge'), findsOneWidget);

      // Switch to Extract tab
      await tester.tap(find.widgetWithText(Tab, 'Extract Pages'));
      await tester.pumpAndSettle();

      final extractBtn = find.widgetWithText(FilledButton, 'Extract Pages');
      expect(extractBtn, findsOneWidget);
      await tester.tap(extractBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter a source PDF file path'), findsOneWidget);
    });
  });
}
