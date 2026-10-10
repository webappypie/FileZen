import 'dart:io';

import 'package:filezen/core/error/app_error.dart';
import 'package:filezen/data/cloud/cloud_provider_repository.dart';
import 'package:filezen/domain/models/cloud_models.dart';
import 'package:filezen/domain/models/network_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late CloudProviderRepository repository;

  const account = CloudAccount(
    id: 'cld_test',
    provider: CloudProviderType.googleDrive,
    accountEmail: 'someone@example.com',
    displayName: 'Test Drive',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_cloud_test_');
    repository = CloudProviderRepository(customStoragePath: '${tempDir.path}/cloud.json');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('CloudProviderRepository (no provider is integrated)', () {
    test('never reports or seeds accounts, and persists nothing', () async {
      expect(CloudProviderRepository.isAvailable, isFalse);
      expect(await repository.getAccounts(), isEmpty);
      expect(await repository.watchAccounts().first, isEmpty);
      expect(File('${tempDir.path}/cloud.json').existsSync(), isFalse);
    });

    test('connecting an account fails for every provider instead of faking a connection', () async {
      for (final provider in CloudProviderType.values) {
        final result = await repository.connectAccount(
          provider,
          email: 'a@b.c',
          displayName: 'x',
        );
        expect(result.isFailure, isTrue, reason: provider.name);
        expect(result.errorOrNull, isA<ProviderUnavailableError>());
        expect(result.errorOrNull!.message, contains('not available'));
      }
      expect(await repository.getAccounts(), isEmpty);
    });

    test('listing, quota, download and upload all fail and fabricate nothing', () async {
      expect((await repository.listCloudFiles(account)).isFailure, isTrue);
      expect((await repository.refreshQuota(account)).isFailure, isTrue);

      final dest = File('${tempDir.path}/downloaded.bin');
      final download = await repository.downloadCloudFile(
        account,
        RemoteFileItem(
          id: '1',
          name: 'a.bin',
          remotePath: '/a.bin',
          size: 10,
          isDirectory: false,
          modifiedAt: DateTime(2026),
          sourceId: account.id,
          sourceType: 'googleDrive',
        ),
        dest.path,
      );
      expect(download.isFailure, isTrue);
      expect(dest.existsSync(), isFalse, reason: 'no placeholder file may be written');

      final local = File('${tempDir.path}/local.txt')..writeAsStringSync('hello');
      final upload = await repository.uploadCloudFile(account, local.path, 'root');
      expect(upload.isFailure, isTrue);
    });

    test('disconnecting is a harmless no-op', () async {
      expect((await repository.disconnectAccount('anything')).isSuccess, isTrue);
    });
  });
}
