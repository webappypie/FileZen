import 'package:filezen/app/navigation/navigation_shell.dart';
import 'package:filezen/app/theme/app_theme.dart';
import 'package:filezen/domain/models/storage_location.dart';
import 'package:filezen/domain/models/storage_intelligence_models.dart';
import 'package:filezen/domain/models/vault_models.dart';
import 'package:filezen/domain/repositories/i_permission_service.dart';
import 'package:filezen/features/ai/presentation/providers/ai_providers.dart';
import 'package:filezen/features/clean/presentation/providers/clean_providers.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/vault/presentation/providers/vault_providers.dart';
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
  const fakeLocation = StorageLocation(
    id: 'test_internal',
    name: 'Internal Storage',
    path: '/mock/storage/emulated/0',
    totalBytes: 128 * 1024 * 1024 * 1024,
    freeBytes: 64 * 1024 * 1024 * 1024,
  );

  final testOverrides = [
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
  ];

  group('Accessibility & Usability Hardening Tests (Phase 13)', () {
    testWidgets('NavigationShell provides screen reader tooltips and semantics labels', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: const MaterialApp(
            home: NavigationShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tooltips for top action bar buttons
      expect(find.byTooltip('Universal Search'), findsOneWidget);
      expect(find.byTooltip('Notifications Center'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);

      // Bottom navigation destination labels
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('Clean'), findsOneWidget);
      expect(find.text('Vault'), findsOneWidget);
    });

    testWidgets('NavigationShell renders without overflow under large accessibility font scales (1.5x)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(1.5),
              ),
              child: NavigationShell(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no layout overflow exceptions were caught
      expect(tester.takeException(), isNull);
    });
  });
}
