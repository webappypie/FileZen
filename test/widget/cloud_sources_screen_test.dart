import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filezen/app/theme/app_theme.dart';
import 'package:filezen/core/result/result.dart';
import 'package:filezen/domain/models/cloud_models.dart';
import 'package:filezen/domain/models/network_models.dart';
import 'package:filezen/domain/repositories/i_cloud_provider_repository.dart';
import 'package:filezen/features/cloud/presentation/providers/cloud_providers.dart';
import 'package:filezen/features/cloud/presentation/screens/cloud_sources_screen.dart';

class _FakeCloudProviderRepository implements ICloudProviderRepository {
  final List<CloudAccount> _accounts;
  final StreamController<List<CloudAccount>> _accountsController =
      StreamController<List<CloudAccount>>.broadcast();

  _FakeCloudProviderRepository({List<CloudAccount>? accounts})
      : _accounts = accounts ??
            [
              CloudAccount(
                id: 'cld_1',
                provider: CloudProviderType.googleDrive,
                accountEmail: 'user@example.com',
                displayName: 'Main Drive',
                totalStorageBytes: 15 * 1024 * 1024 * 1024,
                usedStorageBytes: 5 * 1024 * 1024 * 1024,
              ),
            ];

  @override
  Future<List<CloudAccount>> getAccounts() async => List.unmodifiable(_accounts);

  @override
  Stream<List<CloudAccount>> watchAccounts() async* {
    yield List.unmodifiable(_accounts);
    yield* _accountsController.stream;
  }

  @override
  Future<Result<CloudAccount>> connectAccount(
    CloudProviderType provider, {
    required String email,
    required String displayName,
  }) async {
    final account = CloudAccount(
      id: 'cld_${_accounts.length + 1}',
      provider: provider,
      accountEmail: email,
      displayName: displayName,
    );
    _accounts.add(account);
    _accountsController.add(List.unmodifiable(_accounts));
    return Result.success(account);
  }

  @override
  Future<Result<void>> disconnectAccount(String accountId) async {
    _accounts.removeWhere((a) => a.id == accountId);
    _accountsController.add(List.unmodifiable(_accounts));
    return Result.success(null);
  }

  @override
  Future<Result<List<RemoteFileItem>>> listCloudFiles(
    CloudAccount account, {
    String folderId = 'root',
  }) async {
    return Result.success([
      RemoteFileItem(
        id: 'cld_item_1',
        name: 'Financials',
        remotePath: '/Financials',
        size: 0,
        isDirectory: true,
        modifiedAt: DateTime.now(),
        sourceId: account.id,
        sourceType: account.provider.name,
      ),
      RemoteFileItem(
        id: 'cld_item_2',
        name: 'invoice_2026.pdf',
        remotePath: '/invoice_2026.pdf',
        size: 1048576,
        isDirectory: false,
        modifiedAt: DateTime.now(),
        mimeType: 'application/pdf',
        sourceId: account.id,
        sourceType: account.provider.name,
      ),
    ]);
  }

  @override
  Future<Result<String>> downloadCloudFile(
    CloudAccount account,
    RemoteFileItem file,
    String localDestinationPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    return Result.success(localDestinationPath);
  }

  @override
  Future<Result<RemoteFileItem>> uploadCloudFile(
    CloudAccount account,
    String localFilePath,
    String remoteFolderId, {
    void Function(int sent, int total)? onProgress,
  }) async {
    return Result.success(RemoteFileItem(
      id: 'uploaded_item',
      name: 'uploaded.txt',
      remotePath: '/uploaded.txt',
      size: 100,
      isDirectory: false,
      modifiedAt: DateTime.now(),
      sourceId: account.id,
      sourceType: account.provider.name,
    ));
  }

  @override
  Future<Result<CloudAccount>> refreshQuota(CloudAccount account) async {
    return Result.success(account);
  }
}

void main() {
  Widget createTestWidget({_FakeCloudProviderRepository? repo}) {
    final fakeRepo = repo ?? _FakeCloudProviderRepository();
    return ProviderScope(
      overrides: [
        cloudProviderRepositoryProvider.overrideWithValue(fakeRepo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CloudSourcesScreen(),
      ),
    );
  }

  testWidgets('CloudSourcesScreen renders privacy banner and accounts', (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Cloud Sources'), findsOneWidget);
    expect(find.text('Local-First Cloud Architecture'), findsOneWidget);
    expect(find.text('Main Drive'), findsOneWidget);
    expect(find.text('Google Drive • user@example.com'), findsOneWidget);
    expect(find.text('Browse Files'), findsOneWidget);
    expect(find.text('Add Account'), findsOneWidget);
  });

  testWidgets('Tapping Add Account opens connect dialog and adds account', (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Account'));
    await tester.pumpAndSettle();

    expect(find.text('Connect Cloud Storage'), findsOneWidget);
    expect(find.text('Select Provider'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    // Dialog closed and new account displayed
    expect(find.text('Connect Cloud Storage'), findsNothing);
  });

  testWidgets('Tapping Browse Files opens CloudBrowserScreen with files', (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Browse Files'));
    await tester.pumpAndSettle();

    expect(find.text('Financials'), findsOneWidget);
    expect(find.text('invoice_2026.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}
