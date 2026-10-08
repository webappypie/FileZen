import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:filezen/data/cloud/cloud_provider_repository.dart';
import 'package:filezen/domain/models/cloud_models.dart';

void main() {
  late Directory tempDir;
  late String storagePath;
  late CloudProviderRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_cloud_test_');
    storagePath = '${tempDir.path}/test_cloud_accounts.json';
    repository = CloudProviderRepository(customStoragePath: storagePath);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CloudProviderRepository - Account Management', () {
    test('Pre-seeds default starter cloud accounts on fresh run', () async {
      final accounts = await repository.getAccounts();
      expect(accounts, isNotEmpty);
      expect(accounts.any((a) => a.provider == CloudProviderType.googleDrive), isTrue);
      expect(accounts.any((a) => a.provider == CloudProviderType.oneDrive), isTrue);
    });

    test('Connects a new Dropbox account and persists configuration', () async {
      final connectResult = await repository.connectAccount(
        CloudProviderType.dropbox,
        email: 'dropbox_user@example.com',
        displayName: 'My Dropbox',
      );

      expect(connectResult.isSuccess, isTrue);
      final account = connectResult.dataOrNull!;
      expect(account.provider, CloudProviderType.dropbox);
      expect(account.totalStorageBytes, 2 * 1024 * 1024 * 1024); // 2 GB Dropbox quota
      expect(account.isConnected, isTrue);

      final allAccounts = await repository.getAccounts();
      expect(allAccounts.any((a) => a.id == account.id), isTrue);

      // Verify persistence
      final restoredRepo = CloudProviderRepository(customStoragePath: storagePath);
      final restored = await restoredRepo.getAccounts();
      expect(restored.any((a) => a.id == account.id), isTrue);
    });

    test('Disconnects a cloud account cleanly', () async {
      final initial = await repository.getAccounts();
      final toRemove = initial.first.id;

      final discResult = await repository.disconnectAccount(toRemove);
      expect(discResult.isSuccess, isTrue);

      final updated = await repository.getAccounts();
      expect(updated.any((a) => a.id == toRemove), isFalse);
    });

    test('Refreshes account quota timestamp', () async {
      final initial = await repository.getAccounts();
      final account = initial.first;

      final refreshedResult = await repository.refreshQuota(account);
      expect(refreshedResult.isSuccess, isTrue);
      final refreshed = refreshedResult.dataOrNull!;
      expect(refreshed.lastSyncedAt, isNotNull);
    });
  });

  group('CloudProviderRepository - File Operations & On-Demand Transfer', () {
    test('Lists cloud files and directories', () async {
      final accounts = await repository.getAccounts();
      final account = accounts.first;

      final listResult = await repository.listCloudFiles(account);
      expect(listResult.isSuccess, isTrue);
      final items = listResult.dataOrNull!;
      expect(items, isNotEmpty);
      expect(items.any((i) => i.isDirectory), isTrue);
      expect(items.any((i) => !i.isDirectory), isTrue);
    });

    test('Downloads a cloud file to local destination path with progress', () async {
      final accounts = await repository.getAccounts();
      final account = accounts.first;
      final listResult = await repository.listCloudFiles(account);
      final cloudFile = listResult.dataOrNull!.firstWhere((i) => !i.isDirectory);

      final destPath = '${tempDir.path}/${cloudFile.name}';
      int progressCallCount = 0;

      final dlResult = await repository.downloadCloudFile(
        account,
        cloudFile,
        destPath,
        onProgress: (received, total) {
          progressCallCount++;
          expect(received, greaterThan(0));
          expect(total, greaterThan(0));
        },
      );

      expect(dlResult.isSuccess, isTrue);
      expect(File(destPath).existsSync(), isTrue);
      expect(progressCallCount, greaterThan(0));
    });

    test('Uploads local file to cloud on explicit request and updates usage', () async {
      final accounts = await repository.getAccounts();
      final account = accounts.first;
      final initialUsed = account.usedStorageBytes;

      final localFile = File('${tempDir.path}/upload_me.txt');
      await localFile.writeAsString('FileZen Cloud Upload Content');

      final uploadResult = await repository.uploadCloudFile(
        account,
        localFile.path,
        'root',
      );

      expect(uploadResult.isSuccess, isTrue);
      final remoteItem = uploadResult.dataOrNull!;
      expect(remoteItem.name, 'upload_me.txt');
      expect(remoteItem.size, localFile.lengthSync());

      final updatedAccounts = await repository.getAccounts();
      final updated = updatedAccounts.firstWhere((a) => a.id == account.id);
      expect(updated.usedStorageBytes, initialUsed + localFile.lengthSync());
    });
  });
}
