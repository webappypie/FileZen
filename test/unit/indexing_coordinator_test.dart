import 'dart:io';

import 'package:drift/native.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/database/database_provider.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/domain/models/indexing_progress.dart';
import 'package:filezen/domain/models/storage_location.dart';
import 'package:filezen/domain/repositories/i_permission_service.dart';
import 'package:filezen/features/files/presentation/providers/category_files_providers.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/search/presentation/providers/indexing_coordinator.dart';
import 'package:filezen/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _TempRootRepository extends FilesystemStorageRepository {
  _TempRootRepository(this.root);
  final String root;

  @override
  Future<List<StorageLocation>> getStorageLocations() async => [
        StorageLocation(id: 'internal', name: 'Internal Storage', path: root, totalBytes: 0, freeBytes: 0),
        StorageLocation(id: 'downloads', name: 'Downloads', path: p.join(root, 'Download'), totalBytes: 0, freeBytes: 0),
      ];
}

class _Permission extends StoragePermissionNotifier {
  _Permission(this.status);
  StoragePermissionStatus status;

  @override
  Future<StoragePermissionStatus> build() async => status;

  @override
  Future<void> refresh() async => state = AsyncValue.data(status);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('indexes automatically once access is granted and refreshes Home counts', () async {
    final tempDir = await Directory.systemTemp.createTemp('filezen_coordinator_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    Directory(p.join(tempDir.path, 'Download')).createSync();
    File(p.join(tempDir.path, 'Download', 'invoice.pdf')).writeAsStringSync('%PDF-1.4');
    File(p.join(tempDir.path, 'clip.mp4')).writeAsBytesSync([0, 0, 0, 1]);

    final permission = _Permission(StoragePermissionStatus.denied);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      storageRepositoryProvider.overrideWithValue(_TempRootRepository(tempDir.path)),
      storagePermissionStateProvider.overrideWith(() => permission),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
      await tempDir.delete(recursive: true);
    });

    // Nothing happens without storage access.
    container.read(indexingCoordinatorProvider);
    await container.read(storagePermissionStateProvider.future);
    expect(await container.read(categoryFileCountsProvider.future), isNot(contains('Videos')));

    // Access granted (e.g. in system Settings) -> picked up on resume.
    permission.status = StoragePermissionStatus.granted;
    container.read(indexingCoordinatorProvider).didChangeAppLifecycleState(AppLifecycleState.resumed);

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    Map<String, int> counts = {};
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (container.read(indexingProgressProvider).status != IndexingStatus.completed) continue;
      counts = await container.read(categoryFileCountsProvider.future);
      if (counts.isNotEmpty) break;
    }

    expect(counts['Videos'], 1);
    expect(counts['Documents'], 1);
    expect(counts['Downloads'], 1);
    // Downloads (inside the root) was walked once.
    expect(container.read(indexingProgressProvider).totalFilesDiscovered, 2);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
