import 'package:filezen/app/bootstrap/app_bootstrap.dart';
import 'package:filezen/domain/models/storage_location.dart';
import 'package:filezen/domain/repositories/i_permission_service.dart';
import 'package:filezen/domain/models/storage_intelligence_models.dart';
import 'package:filezen/features/ai/presentation/providers/ai_providers.dart';
import 'package:filezen/features/clean/presentation/providers/clean_providers.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/domain/models/vault_models.dart';
import 'package:filezen/features/vault/presentation/providers/vault_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePermissionNotifier extends StoragePermissionNotifier {
  final StoragePermissionStatus _status;
  _FakePermissionNotifier(this._status);

  @override
  Future<StoragePermissionStatus> build() async => _status;
}

void main() {
  testWidgets('NavigationShell renders 5 tabs and allows tab navigation', (WidgetTester tester) async {
    const fakeLocation = StorageLocation(
      id: 'test_internal',
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
          smartCollectionsProvider.overrideWith(
            (ref) => Future.value([]),
          ),
          storageOverviewProvider.overrideWith(
            (ref) => Future.value(const StorageOverview(
              totalBytes: 128 * 1024 * 1024 * 1024,
              usedBytes: 46 * 1024 * 1024 * 1024,
              freeBytes: 82 * 1024 * 1024 * 1024,
              categorySizes: {},
              categoryCounts: {},
            )),
          ),
          cleanupOpportunitiesProvider.overrideWith(
            (ref) => Future.value([]),
          ),
          vaultSecurityConfigProvider.overrideWith(
            (ref) => Future.value(const VaultSecurityConfig(isPinConfigured: true)),
          ),
        ],
        child: const FileZenApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify App Bar Title starts at FileZen
    expect(find.text('FileZen'), findsOneWidget);

    // Verify all 5 navigation destinations exist
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('Clean'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);

    // Verify top action bar buttons
    expect(find.byTooltip('Universal Search'), findsOneWidget);
    expect(find.byTooltip('Notifications Center'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    // Switch to Files tab
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Select a Storage Location'), findsOneWidget);

    // Switch to AI tab
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('100% On-Device AI Processing'), findsOneWidget);

    // Switch to Clean tab
    await tester.tap(find.text('Clean'));
    await tester.pumpAndSettle();
    expect(find.text('Zero Silent Deletions Contract'), findsOneWidget);

    // Switch to Vault tab
    await tester.tap(find.text('Vault'));
    await tester.pumpAndSettle();
    expect(find.text('Vault is Locked'), findsOneWidget);

    // Switch back to Home tab
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Internal Storage'), findsOneWidget);
  });
}
