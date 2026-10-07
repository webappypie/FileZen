import 'package:filezen/domain/models/ai_models.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:filezen/domain/models/search_result_item.dart';
import 'package:filezen/features/ai/presentation/providers/ai_providers.dart';
import 'package:filezen/features/ai/presentation/screens/ai_screen.dart';
import 'package:filezen/features/ai/presentation/screens/auto_rename_screen.dart';
import 'package:filezen/features/ai/presentation/screens/collection_detail_screen.dart';
import 'package:filezen/features/ai/presentation/widgets/related_files_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sampleFile = FileEntity(
    id: 'f1',
    name: 'software_engineer_resume.pdf',
    path: '/storage/emulated/0/Download/software_engineer_resume.pdf',
    size: 1024 * 150,
    modifiedAt: DateTime(2026, 10, 8),
    createdAt: DateTime(2026, 10, 8),
    isDirectory: false,
    extension: '.pdf',
    category: FileCategory.document,
  );

  final sampleResultItem = SearchResultItem(
    file: sampleFile,
    snippet: 'Matched [match]resume[/match] keyword',
    rank: -10.0,
  );

  final sampleCollections = [
    const SmartCollection(
      id: 'invoices_receipts',
      title: 'Invoices & Receipts',
      description: 'Financial receipts and statements',
      ruleType: SmartCollectionRuleType.receiptsAndInvoices,
      iconCodePoint: 0xf00b8,
      colorHex: 0xFF10B981,
      fileCount: 4,
      totalSizeBytes: 1024 * 500,
    ),
    const SmartCollection(
      id: 'identity_documents',
      title: 'Identity & Cards',
      description: 'Passports, identity cards, licenses',
      ruleType: SmartCollectionRuleType.identityAndDocuments,
      iconCodePoint: 0xf58c,
      colorHex: 0xFF3B82F6,
      fileCount: 2,
      totalSizeBytes: 1024 * 1024 * 2,
    ),
  ];

  testWidgets('AiScreen renders privacy banner, Ask Your Files, prompt chips, and collections', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smartCollectionsProvider.overrideWith((ref) => Future.value(sampleCollections)),
          askYourFilesResultsProvider.overrideWith((ref) => Future.value([])),
        ],
        child: const MaterialApp(
          home: AiScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Privacy Guarantee Banner
    expect(find.text('100% On-Device AI Processing'), findsOneWidget);
    expect(find.textContaining('Zero cloud uploads'), findsOneWidget);

    // Verify Ask Your Files input
    expect(find.text('Ask Your Files'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Verify Quick Prompt Chips
    expect(find.text('📄 Latest resume'), findsOneWidget);
    expect(find.text('🎥 Large videos'), findsOneWidget);
    expect(find.text('🧾 Receipts & bills'), findsOneWidget);

    // Verify Smart Collections Section & Cards
    expect(find.text('Smart Collections'), findsOneWidget);
    expect(find.text('Invoices & Receipts'), findsOneWidget);
    expect(find.text('Identity & Cards'), findsOneWidget);
    expect(find.text('4 items'), findsOneWidget);

    // Verify AI Auto-Rename Studio banner
    expect(find.text('AI Auto-Rename Studio'), findsOneWidget);
  });

  testWidgets('AiScreen displays actionable search results upon query selection', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smartCollectionsProvider.overrideWith((ref) => Future.value(sampleCollections)),
          askYourFilesQueryTextProvider.overrideWith((ref) => 'latest resume'),
          askYourFilesResultsProvider.overrideWith((ref) => Future.value([sampleResultItem])),
        ],
        child: const MaterialApp(
          home: AiScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify AI Interpretation Banner
    expect(find.textContaining('AI Interpretation:'), findsOneWidget);

    // Verify actionable result card
    expect(find.text('software_engineer_resume.pdf'), findsOneWidget);
    expect(find.byTooltip('Open'), findsOneWidget);
    expect(find.byTooltip('AI Rename'), findsOneWidget);
  });

  testWidgets('AutoRenameScreen renders tabs, path field, and scan action', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AutoRenameScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI Auto-Rename Studio'), findsOneWidget);
    expect(find.textContaining('Proposals'), findsOneWidget);
    expect(find.textContaining('History'), findsOneWidget);
    expect(find.text('Scan & Propose Renames'), findsOneWidget);
  });

  testWidgets('CollectionDetailScreen renders collection title and file items', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionFilesProvider('invoices_receipts').overrideWith((ref) => Future.value([sampleFile])),
        ],
        child: MaterialApp(
          home: CollectionDetailScreen(collection: sampleCollections.first),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invoices & Receipts'), findsOneWidget);
    expect(find.text('software_engineer_resume.pdf'), findsOneWidget);
  });

  testWidgets('RelatedFilesSheet renders related companion files', (tester) async {
    final relatedItem = RelatedFileItem(
      file: sampleFile,
      relationship: 'Matching naming prefix in same folder',
      confidenceScore: 0.95,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relatedFilesProvider(sampleFile).overrideWith((ref) => Future.value([relatedItem])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RelatedFilesSheet(targetFile: sampleFile),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Related to ${sampleFile.name}'), findsOneWidget);
    expect(find.text('software_engineer_resume.pdf'), findsOneWidget);
    expect(find.text('Matching naming prefix in same folder'), findsOneWidget);
  });
}
