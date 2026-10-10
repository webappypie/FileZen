import 'dart:io';

import 'package:drift/native.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/database/database_provider.dart';
import 'package:filezen/data/search/search_repository.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/data/vault/vault_auth_service.dart';
import 'package:filezen/data/vault/vault_storage_service.dart';
import 'package:filezen/domain/models/search_query.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/search/presentation/providers/search_providers.dart';
import 'package:filezen/features/vault/presentation/providers/vault_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/vault_test_doubles.dart';

/// A file moved into the Vault must stop being discoverable through the normal
/// (public) search index: name, path and extracted text all have to go.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late AppDatabase db;
  late ProviderContainer container;
  late VaultAuthService auth;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filezen_vault_index_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = VaultAuthService(
      customConfigPath: p.join(temp.path, 'vault_auth.json'),
      backend: FakeVaultCryptoBackend(),
      biometricGate: FakeBiometricGate(),
    );
    final storage = VaultStorageService(
      authService: auth,
      storageRepo: FilesystemStorageRepository(),
      customVaultDirectoryPath: p.join(temp.path, 'vault', 'files'),
    );
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      vaultAuthServiceProvider.overrideWithValue(auth),
      vaultStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    });
  });

  test('importing into the Vault removes the file from search, but plain files stay indexed', () async {
    final secret = File(p.join(temp.path, 'passport_scan.txt'))
      ..writeAsStringSync('passport number X1234567 issued in 2026');
    final plain = File(p.join(temp.path, 'shopping_list.txt'))
      ..writeAsStringSync('milk eggs bread');

    final repo = container.read(storageRepositoryProvider);
    final indexer = container.read(indexingServiceProvider);
    await indexer.indexSingleFile(await repo.getFileDetails(secret.path));
    await indexer.indexSingleFile(await repo.getFileDetails(plain.path));

    final search = SearchRepository(db);
    Future<int> hits(String q) async => (await search.search(SearchQuery(text: q))).dataOrNull!.length;

    expect(await hits('passport'), 1, reason: 'indexed before the move');
    expect(await hits('shopping'), 1);

    await container.read(vaultSessionProvider.notifier).setupInitialPin('1234');
    final result = await container.read(vaultItemsProvider.notifier).importFile(secret.path);
    expect(result.isSuccess, isTrue);

    expect(await hits('passport'), 0, reason: 'name must not stay searchable');
    expect(await hits('X1234567'), 0, reason: 'extracted text must not stay searchable');
    expect(await db.select(db.fileRecords).get().then((r) => r.map((e) => e.name)), ['shopping_list.txt']);
    expect(await hits('shopping'), 1, reason: 'unrelated files are untouched');
  });

  test('a failed import (vault locked) leaves the index alone', () async {
    final file = File(p.join(temp.path, 'keep_me.txt'))..writeAsStringSync('keep searchable');
    final repo = container.read(storageRepositoryProvider);
    await container.read(indexingServiceProvider).indexSingleFile(await repo.getFileDetails(file.path));

    // Vault never unlocked ⇒ import must fail.
    final result = await container.read(vaultItemsProvider.notifier).importFile(file.path);
    expect(result.isFailure, isTrue);

    final hits = (await SearchRepository(db).search(const SearchQuery(text: 'keep'))).dataOrNull!;
    expect(hits.length, 1);
    expect(file.existsSync(), isTrue);
  });
}
