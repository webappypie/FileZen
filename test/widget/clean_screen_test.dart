import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filezen/app/theme/app_theme.dart';
import 'package:filezen/domain/models/cleanup_models.dart';
import 'package:filezen/domain/models/deduplication_models.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:filezen/domain/models/storage_intelligence_models.dart';
import 'package:filezen/domain/models/timeline_models.dart';
import 'package:filezen/domain/models/trash_item.dart';
import 'package:filezen/features/clean/presentation/providers/clean_providers.dart';
import 'package:filezen/features/clean/presentation/screens/clean_screen.dart';
import 'package:filezen/features/clean/presentation/screens/cleanup_category_screen.dart';
import 'package:filezen/features/clean/presentation/screens/duplicate_review_screen.dart';
import 'package:filezen/features/clean/presentation/screens/storage_analysis_screen.dart';
import 'package:filezen/features/clean/presentation/screens/timeline_screen.dart';
import 'package:filezen/features/clean/presentation/screens/trash_screen.dart';
import 'package:filezen/features/clean/presentation/widgets/destructive_action_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleOverview = StorageOverview(
    totalBytes: 128 * 1024 * 1024 * 1024,
    usedBytes: 46 * 1024 * 1024 * 1024,
    freeBytes: 82 * 1024 * 1024 * 1024,
    categorySizes: {
      FileCategory.image: 12 * 1024 * 1024 * 1024,
      FileCategory.video: 20 * 1024 * 1024 * 1024,
      FileCategory.document: 5 * 1024 * 1024 * 1024,
      FileCategory.audio: 3 * 1024 * 1024 * 1024,
      FileCategory.apk: 2 * 1024 * 1024 * 1024,
      FileCategory.archive: 2 * 1024 * 1024 * 1024,
      FileCategory.other: 2 * 1024 * 1024 * 1024,
    },
    categoryCounts: {
      FileCategory.image: 1250,
      FileCategory.video: 85,
      FileCategory.document: 340,
      FileCategory.audio: 120,
      FileCategory.apk: 14,
      FileCategory.archive: 22,
      FileCategory.other: 80,
    },
  );

  final sampleOrigFile = FileEntity(
    id: 'f_orig',
    path: '/storage/emulated/0/DCIM/photo.jpg',
    name: 'photo.jpg',
    extension: '.jpg',
    size: 2 * 1024 * 1024,
    modifiedAt: DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
    isDirectory: false,
    category: FileCategory.image,
  );

  final sampleDupeFile = FileEntity(
    id: 'f_dupe',
    path: '/storage/emulated/0/Downloads/photo_copy.jpg',
    name: 'photo_copy.jpg',
    extension: '.jpg',
    size: 2 * 1024 * 1024,
    modifiedAt: DateTime(2026, 1, 2),
    createdAt: DateTime(2026, 1, 2),
    isDirectory: false,
    category: FileCategory.image,
  );

  final sampleDuplicateGroups = [
    DuplicateGroup(
      checksum: 'e99a18c428cb38d5f260853678922e03',
      fileSize: 2 * 1024 * 1024,
      primaryFile: sampleOrigFile,
      duplicateFiles: [sampleDupeFile],
    ),
  ];

  final sampleOpportunities = [
    CleanupCandidateGroup(
      type: CleanupCategoryType.exactDuplicates,
      title: CleanupCategoryType.exactDuplicates.title,
      description: CleanupCategoryType.exactDuplicates.description,
      items: [sampleDupeFile],
      totalSize: 2 * 1024 * 1024,
    ),
    CleanupCandidateGroup(
      type: CleanupCategoryType.largeFiles,
      title: CleanupCategoryType.largeFiles.title,
      description: CleanupCategoryType.largeFiles.description,
      items: [sampleOrigFile],
      totalSize: 2 * 1024 * 1024,
    ),
  ];

  final sampleTrashItems = [
    TrashItem(
      id: 'trash_1',
      originalPath: '/storage/emulated/0/Downloads/old_contract.pdf',
      trashPath: '/storage/emulated/0/.filezen_trash/old_contract.pdf',
      fileName: 'old_contract.pdf',
      size: 500 * 1024,
      trashedAt: DateTime.now().subtract(const Duration(days: 2)),
      category: FileCategory.document,
    ),
  ];

  final sampleTimelineGroups = [
    TimelineGroup(
      bucket: TimelineBucket.today,
      label: 'Today',
      date: DateTime.now(),
      files: [sampleOrigFile],
      totalBytes: sampleOrigFile.size,
    ),
    TimelineGroup(
      bucket: TimelineBucket.yesterday,
      label: 'Yesterday',
      date: DateTime.now().subtract(const Duration(days: 1)),
      files: [sampleDupeFile],
      totalBytes: sampleDupeFile.size,
    ),
  ];

  Widget buildTestableWidget(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: child,
      ),
    );
  }

  testWidgets('CleanScreen renders safety banner, storage overview, shortcuts, and opportunities', (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        const CleanScreen(),
        overrides: [
          storageOverviewProvider.overrideWith((ref) => Future.value(sampleOverview)),
          cleanupOpportunitiesProvider.overrideWith((ref) => Future.value(sampleOpportunities)),
          exactDuplicatesProvider.overrideWith((ref) => Future.value(sampleDuplicateGroups)),
          trashItemsProvider.overrideWith(() => _MockTrashNotifier(sampleTrashItems)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Verify Safety Contract Banner
    expect(find.text('Zero Silent Deletions Contract'), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

    // Verify Storage Overview Card
    expect(find.text('Internal Storage Usage'), findsOneWidget);
    expect(find.text('35.9%'), findsOneWidget);
    expect(find.text('Deep Analysis →'), findsOneWidget);

    // Verify Hub Navigation Row
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Recycle Bin'), findsOneWidget);

    // Verify Exact Duplicates Banner
    expect(find.text('Exact Duplicate Files Engine'), findsOneWidget);

    // Verify Opportunities
    expect(find.text('Reviewable Cleanup Opportunities'), findsOneWidget);
    expect(find.text(CleanupCategoryType.exactDuplicates.title), findsOneWidget);
    expect(find.text(CleanupCategoryType.largeFiles.title), findsOneWidget);
  });

  testWidgets('DuplicateReviewScreen renders duplicate cluster with Keep Original badge and smart selection', (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        const DuplicateReviewScreen(),
        overrides: [
          exactDuplicatesProvider.overrideWith((ref) => Future.value(sampleDuplicateGroups)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Exact Duplicate Files'), findsOneWidget);
    expect(find.text('1 Duplicate Sets'), findsOneWidget);
    expect(find.text('KEEP ORIGINAL'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('photo_copy.jpg'), findsOneWidget);
    expect(find.text('Save 2.0 MB'), findsOneWidget);
    expect(find.text('Clean Selected'), findsOneWidget);
    expect(find.text('1 Copies Selected'), findsOneWidget);

    // Toggle Deselect All / Smart Select
    await tester.tap(find.text('Deselect All'));
    await tester.pumpAndSettle();
    expect(find.text('Smart Select Copies'), findsOneWidget);
    expect(find.text('Clean Selected'), findsNothing);
  });

  testWidgets('CleanupCategoryScreen renders items with selection and clean action', (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        CleanupCategoryScreen(candidateGroup: sampleOpportunities.first),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(CleanupCategoryType.exactDuplicates.title), findsOneWidget);
    expect(find.text('photo_copy.jpg'), findsOneWidget);
    expect(find.text('Clean Selected'), findsOneWidget);

    // Tap Deselect All
    await tester.tap(find.text('Deselect All'));
    await tester.pumpAndSettle();
    expect(find.text('Clean Selected'), findsNothing);
  });

  testWidgets('StorageAnalysisScreen renders category breakdown, trends, and top folders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      buildTestableWidget(
        const StorageAnalysisScreen(),
        overrides: [
          storageOverviewProvider.overrideWith((ref) => Future.value(sampleOverview)),
          storageTrendsProvider.overrideWith((ref) => Future.value([
                StorageTrendPoint(
                  timestamp: DateTime(2026, 10, 1),
                  usedBytes: 45 * 1024 * 1024 * 1024,
                  totalBytes: 128 * 1024 * 1024 * 1024,
                  changeDeltaBytes: 500 * 1024 * 1024,
                ),
              ])),
          topFoldersProvider.overrideWith((ref) => Future.value([
                const FolderStorageItem(
                  path: '/storage/emulated/0/DCIM',
                  name: 'DCIM',
                  sizeBytes: 15 * 1024 * 1024 * 1024,
                  fileCount: 450,
                  percentageOfTotal: 32.6,
                ),
              ])),
          largestFilesProvider.overrideWith((ref) => Future.value([sampleOrigFile])),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Storage Intelligence'), findsOneWidget);
    expect(find.text('Category Occupancy'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Usage Trends & History'), findsOneWidget);
    expect(find.text('Top Space-Consuming Folders'), findsOneWidget);
    expect(find.text('DCIM'), findsOneWidget);
  });

  testWidgets('TrashScreen renders recycle bin items and action controls', (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        const TrashScreen(),
        overrides: [
          trashItemsProvider.overrideWith(() => _MockTrashNotifier(sampleTrashItems)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recycle Bin (Trash)'), findsOneWidget);
    expect(find.text('old_contract.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.restore_rounded), findsWidgets);
    expect(find.byIcon(Icons.delete_forever_rounded), findsWidgets);
    expect(find.textContaining('Safe Recovery Active'), findsOneWidget);
  });

  testWidgets('TimelineScreen renders filter chips and chronological groups', (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        const TimelineScreen(),
        overrides: [
          timelineGroupsProvider(null).overrideWith((ref) => Future.value(sampleTimelineGroups)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Storage Timeline'), findsOneWidget);
    expect(find.text('All Files'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('photo_copy.jpg'), findsOneWidget);
  });

  testWidgets('DestructiveActionDialog enforces Destructive-Action Contract', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  DestructiveActionDialog.show(
                    context,
                    title: 'Clean Redundant Files',
                    candidates: [sampleDupeFile],
                    totalBytes: sampleDupeFile.size,
                    actionLabel: 'Confirm Clean',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Clean Redundant Files'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // Items Selected
    expect(find.text('2.0 MB'), findsNWidgets(2)); // Space Freed in summary and item preview
    expect(find.text('Candidate Preview (1 of 1):'), findsOneWidget);
    expect(find.text('Move to Recycle Bin (Safe & Recoverable)'), findsOneWidget);
    expect(find.text('Confirm Clean'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}

class _MockTrashNotifier extends TrashItemsNotifier {
  final List<TrashItem> _initial;
  _MockTrashNotifier(this._initial);

  @override
  Future<List<TrashItem>> build() async => _initial;
}
