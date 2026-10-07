import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_clipboard.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:filezen/domain/models/storage_location.dart';
import 'package:filezen/domain/repositories/i_permission_service.dart';
import 'package:filezen/features/files/presentation/providers/file_management_providers.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/files/presentation/screens/files_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePermissionNotifier extends StoragePermissionNotifier {
  final StoragePermissionStatus _status;
  _FakePermissionNotifier(this._status);

  @override
  Future<StoragePermissionStatus> build() async => _status;
}

void main() {
  final fakeFiles = [
    FileEntity(
      id: 'f1',
      path: '/mock/storage/emulated/0/alpha.txt',
      name: 'alpha.txt',
      extension: '.txt',
      size: 1024 * 10,
      modifiedAt: DateTime(2026, 3, 1),
      createdAt: DateTime(2026, 3, 1),
      isDirectory: false,
      category: FileCategory.document,
    ),
    FileEntity(
      id: 'f2',
      path: '/mock/storage/emulated/0/beta.pdf',
      name: 'beta.pdf',
      extension: '.pdf',
      size: 1024 * 50,
      modifiedAt: DateTime(2026, 3, 2),
      createdAt: DateTime(2026, 3, 2),
      isDirectory: false,
      category: FileCategory.document,
    ),
  ];

  const fakeLocation = StorageLocation(
    id: 'internal',
    name: 'Internal Storage',
    path: '/mock/storage/emulated/0',
    totalBytes: 128 * 1024 * 1024 * 1024,
    freeBytes: 64 * 1024 * 1024 * 1024,
  );

  testWidgets('FilesScreen enters selection mode and shows batch action buttons', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePermissionStateProvider.overrideWith(
            () => _FakePermissionNotifier(StoragePermissionStatus.granted),
          ),
          storageLocationsProvider.overrideWith(
            (ref) => Future.value([fakeLocation]),
          ),
          currentDirectoryPathProvider.overrideWith(
            (ref) => '/mock/storage/emulated/0',
          ),
          directoryContentsProvider('/mock/storage/emulated/0').overrideWith(
            (ref) => Future.value(fakeFiles),
          ),
        ],
        child: const MaterialApp(
          home: FilesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify files rendered
    expect(find.text('alpha.txt'), findsOneWidget);
    expect(find.text('beta.pdf'), findsOneWidget);

    // Long press on alpha.txt to activate selection mode
    await tester.longPress(find.text('alpha.txt'));
    await tester.pumpAndSettle();

    // Verify Selection AppBar appears with "1 selected"
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byTooltip('Close selection'), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Move (Cut)'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
  });

  testWidgets('FilesScreen shows clipboard paste bar when clipboard has items', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePermissionStateProvider.overrideWith(
            () => _FakePermissionNotifier(StoragePermissionStatus.granted),
          ),
          storageLocationsProvider.overrideWith(
            (ref) => Future.value([fakeLocation]),
          ),
          currentDirectoryPathProvider.overrideWith(
            (ref) => '/mock/storage/emulated/0',
          ),
          directoryContentsProvider('/mock/storage/emulated/0').overrideWith(
            (ref) => Future.value(fakeFiles),
          ),
          fileClipboardProvider.overrideWith(
            (ref) => FileClipboard(
              mode: ClipboardMode.copy,
              items: [fakeFiles.first],
            ),
          ),
        ],
        child: const MaterialApp(
          home: FilesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify clipboard bar appears at bottom
    expect(find.text('Paste Here'), findsOneWidget);
    expect(find.textContaining('1 items (Copy)'), findsOneWidget);
  });

  testWidgets('FilesScreen opens sort modal when sort icon tapped', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePermissionStateProvider.overrideWith(
            () => _FakePermissionNotifier(StoragePermissionStatus.granted),
          ),
          storageLocationsProvider.overrideWith(
            (ref) => Future.value([fakeLocation]),
          ),
          currentDirectoryPathProvider.overrideWith(
            (ref) => '/mock/storage/emulated/0',
          ),
          directoryContentsProvider('/mock/storage/emulated/0').overrideWith(
            (ref) => Future.value(fakeFiles),
          ),
        ],
        child: const MaterialApp(
          home: FilesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap sort button in breadcrumb bar
    await tester.tap(find.byTooltip('Sort files'));
    await tester.pumpAndSettle();

    // Verify sort bottom sheet appears
    expect(find.text('Sort Files'), findsOneWidget);
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('DATE'), findsOneWidget);
    expect(find.text('SIZE'), findsOneWidget);
    expect(find.text('Keep Folders on Top'), findsOneWidget);
  });
}
