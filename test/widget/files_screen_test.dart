import 'package:filezen/domain/models/storage_location.dart';
import 'package:filezen/domain/repositories/i_permission_service.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/files/presentation/screens/files_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FilesScreen displays PermissionView when storage access is denied', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePermissionStateProvider.overrideWith(
            () => _FakePermissionNotifier(StoragePermissionStatus.denied),
          ),
        ],
        child: const MaterialApp(
          home: FilesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Storage Access Required'), findsOneWidget);
    expect(find.text('Grant Storage Access'), findsOneWidget);
  });

  testWidgets('FilesScreen displays storage locations when permission is granted', (tester) async {
    const fakeLocation = StorageLocation(
      id: 'test_drive',
      name: 'Internal Storage',
      path: '/mock/storage/emulated/0',
      totalBytes: 128 * 1024 * 1024 * 1024,
      freeBytes: 64 * 1024 * 1024 * 1024,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePermissionStateProvider.overrideWith(
            () => _FakePermissionNotifier(StoragePermissionStatus.granted),
          ),
          storageLocationsProvider.overrideWith(
            (ref) => Future.value([fakeLocation]),
          ),
        ],
        child: const MaterialApp(
          home: FilesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Internal Storage'), findsOneWidget);
    expect(find.text('64 GB free'), findsOneWidget);
  });
}

class _FakePermissionNotifier extends StoragePermissionNotifier {
  final StoragePermissionStatus initialStatus;
  _FakePermissionNotifier(this.initialStatus);

  @override
  Future<StoragePermissionStatus> build() async => initialStatus;
}
