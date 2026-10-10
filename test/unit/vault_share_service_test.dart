import 'dart:io';
import 'dart:typed_data';

import 'package:filezen/core/error/app_error.dart';
import 'package:filezen/core/result/result.dart';
import 'package:filezen/data/vault/vault_share_service.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:filezen/domain/models/vault_models.dart';
import 'package:filezen/domain/repositories/i_vault_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Storage implements IVaultStorageService {
  final Result<Uint8List> result;
  _Storage(this.result);

  @override
  Future<Result<Uint8List>> getDecryptedBytes(VaultItem item) async => result;

  @override
  Future<List<VaultItem>> listVaultItems() async => [];

  @override
  Future<Result<VaultItem>> importFileToVault(String sourcePath, {bool deleteSource = true}) =>
      throw UnimplementedError();

  @override
  Future<Result<FileEntity>> exportFileFromVault(VaultItem item, String destinationDirPath) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> deleteVaultItem(VaultItem item) => throw UnimplementedError();

  @override
  Future<Result<void>> emptyVault() => throw UnimplementedError();

  @override
  Future<int> getVaultTotalSizeBytes() async => 0;
}

VaultItem _item(String name) => VaultItem(
      id: 'id',
      vaultPath: '/vault/abc.zenvault',
      originalFileName: name,
      originalPath: '/orig/$name',
      fileSize: 5,
      encryptedSize: 50,
      category: FileCategory.document,
      encryptedAt: DateTime(2026),
    );

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filezen_share_test_');
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  VaultShareService service(
    Result<Uint8List> result, {
    VaultFileOpener? opener,
    Duration cleanup = const Duration(milliseconds: 80),
  }) =>
      VaultShareService(
        storage: _Storage(result),
        cleanupDelay: cleanup,
        opener: opener ?? (_) async => VaultShareStatus.opened,
        tempDirectory: () async => temp,
      );

  test('hands the app a decrypted copy, then deletes it after the delay', () async {
    String? openedPath;
    String? contentAtOpen;
    final svc = service(
      Result.success(Uint8List.fromList('top secret'.codeUnits)),
      opener: (path) async {
        openedPath = path;
        contentAtOpen = File(path).readAsStringSync();
        return VaultShareStatus.opened;
      },
    );

    final outcome = await svc.shareDecrypted(_item('report.txt'));

    expect(outcome.status, VaultShareStatus.opened);
    expect(p.basename(openedPath!), 'report.txt');
    expect(contentAtOpen, 'top secret');
    expect(p.isWithin(p.join(temp.path, VaultShareService.folderName), openedPath!), isTrue);
    expect(File(openedPath!).existsSync(), isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(File(openedPath!).existsSync(), isFalse);
    expect(Directory(p.dirname(openedPath!)).existsSync(), isFalse);
  });

  test('a locked vault / decryption failure writes nothing', () async {
    final svc = service(Result.failure(AccessDeniedError(path: 'x', message: 'Vault is locked.')));
    final outcome = await svc.shareDecrypted(_item('a.txt'));

    expect(outcome.status, VaultShareStatus.failed);
    expect(outcome.message, contains('locked'));
    expect(Directory(p.join(temp.path, VaultShareService.folderName)).existsSync(), isFalse);
  });

  test('hostile stored names cannot escape the share folder', () async {
    String? openedPath;
    final svc = service(
      Result.success(Uint8List.fromList([1, 2, 3])),
      opener: (path) async {
        openedPath = path;
        return VaultShareStatus.opened;
      },
    );
    await svc.shareDecrypted(_item('../../../evil.sh'));

    expect(p.basename(openedPath!), 'evil.sh');
    expect(p.isWithin(p.join(temp.path, VaultShareService.folderName), openedPath!), isTrue);
  });

  test('reports when no app can open the file, and still cleans up', () async {
    String? openedPath;
    final svc = service(
      Result.success(Uint8List.fromList([9])),
      opener: (path) async {
        openedPath = path;
        return VaultShareStatus.noAppAvailable;
      },
    );
    final outcome = await svc.shareDecrypted(_item('x.bin'));

    expect(outcome.status, VaultShareStatus.noAppAvailable);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(File(openedPath!).existsSync(), isFalse);
  });

  test('an opener crash deletes the copy immediately', () async {
    String? openedPath;
    final svc = service(
      Result.success(Uint8List.fromList([9])),
      cleanup: const Duration(minutes: 5),
      opener: (path) async {
        openedPath = path;
        throw StateError('boom');
      },
    );
    final outcome = await svc.shareDecrypted(_item('x.bin'));

    expect(outcome.status, VaultShareStatus.failed);
    expect(File(openedPath!).existsSync(), isFalse);
  });

  test('sweepStale removes plaintext left by a previous run', () async {
    final leftover = File(p.join(temp.path, VaultShareService.folderName, '123', 'old.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('stale plaintext');

    await service(Result.success(Uint8List(0))).sweepStale();

    expect(leftover.existsSync(), isFalse);
    expect(Directory(p.join(temp.path, VaultShareService.folderName)).existsSync(), isFalse);
  });
}
