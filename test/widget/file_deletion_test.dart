import 'dart:io';

import 'package:drift/native.dart';
import 'package:filezen/core/error/app_error.dart';
import 'package:filezen/core/result/result.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/database/database_provider.dart';
import 'package:filezen/data/indexing/indexing_service.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/files/presentation/services/file_deletion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Refuses to delete one path, like a file without write permission.
class _PartlyReadOnlyRepository extends FilesystemStorageRepository {
  _PartlyReadOnlyRepository(this.protectedPath);
  final String protectedPath;

  @override
  Future<Result<void>> delete(String path) async {
    if (path == protectedPath) {
      return Result.failure(AccessDeniedError(path: path));
    }
    return super.delete(path);
  }
}

void main() {
  testWidgets('only files that are really gone leave the index; failures are reported', (tester) async {
    late Directory dir;
    late AppDatabase db;
    late File gone;
    late File kept;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('filezen_delete_');
      db = AppDatabase.forTesting(NativeDatabase.memory());
      gone = File(p.join(dir.path, 'old_invoice.pdf'))..writeAsStringSync('%PDF');
      kept = File(p.join(dir.path, 'locked.pdf'))..writeAsStringSync('%PDF');
      await IndexingService(db: db, storageRepo: FilesystemStorageRepository())
          .runIndexScan(targetPaths: [dir.path]);
    });
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    late WidgetRef widgetRef;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        storageRepositoryProvider.overrideWithValue(_PartlyReadOnlyRepository(kept.path)),
      ],
      child: Consumer(builder: (_, ref, __) {
        widgetRef = ref;
        return const SizedBox();
      }),
    ));

    final repo = FilesystemStorageRepository();
    late FileDeletionResult result;
    late List<String> indexed;
    await tester.runAsync(() async {
      final entities = [await repo.getFileDetails(gone.path), await repo.getFileDetails(kept.path)];
      result = await FileDeletion.deleteFiles(widgetRef, entities);
      indexed = (await db.select(db.fileRecords).get()).map((r) => r.path).toList();
    });

    expect(result.deleted, [gone.path]);
    expect(result.failed, [kept.path]);
    expect(result.summary(), 'Deleted 1; 1 could not be deleted');
    expect(gone.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue);
    expect(indexed, [kept.path], reason: 'a file that still exists must stay searchable');
  });

  test('summary never over-claims', () {
    expect(const FileDeletionResult(['a', 'b'], []).summary(), 'Deleted 2 items');
    expect(const FileDeletionResult(['a'], []).summary(), 'Deleted 1 item');
    expect(const FileDeletionResult([], ['a']).summary(), startsWith('Could not delete 1 item'));
  });
}
