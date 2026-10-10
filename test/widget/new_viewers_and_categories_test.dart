import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:filezen/features/documents/presentation/screens/office_document_screen.dart';

void main() {
  Widget createSubject(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('OfficeDocumentScreen Widget Tests', () {
    testWidgets('renders office document details, badge, and open button', (tester) async {
      final docFile = FileEntity(
        id: 'docx-1',
        path: '/storage/emulated/0/Download/Quarterly_Report.docx',
        name: 'Quarterly_Report.docx',
        extension: 'docx',
        size: 2048576,
        modifiedAt: DateTime(2025, 1, 1),
        createdAt: DateTime(2025, 1, 1),
        isDirectory: false,
        category: FileCategory.document,
      );

      await tester.pumpWidget(createSubject(
        OfficeDocumentScreen(file: docFile),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Quarterly_Report.docx'), findsAtLeastNWidgets(1));
      expect(find.text('Microsoft Word Document'), findsOneWidget);
      expect(find.text('Open in Compatible App'), findsOneWidget);
    });

    testWidgets('identifies spreadsheet types appropriately', (tester) async {
      final sheetFile = FileEntity(
        id: 'xlsx-1',
        path: '/storage/emulated/0/Download/Financials.xlsx',
        name: 'Financials.xlsx',
        extension: 'xlsx',
        size: 1048576,
        modifiedAt: DateTime(2025, 1, 1),
        createdAt: DateTime(2025, 1, 1),
        isDirectory: false,
        category: FileCategory.document,
      );

      await tester.pumpWidget(createSubject(
        OfficeDocumentScreen(file: sheetFile),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Microsoft Excel Spreadsheet'), findsOneWidget);
      expect(find.text('Financials.xlsx'), findsAtLeastNWidgets(1));
    });
  });
}
