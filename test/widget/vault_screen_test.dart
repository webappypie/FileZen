import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filezen/app/theme/app_theme.dart';
import 'package:filezen/core/error/app_error.dart';
import 'package:filezen/core/result/result.dart';
import 'package:filezen/data/vault/vault_auth_service.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:filezen/domain/models/vault_models.dart';
import 'package:filezen/domain/repositories/i_vault_storage_service.dart';
import 'package:filezen/features/vault/presentation/providers/vault_providers.dart';
import 'package:filezen/features/vault/presentation/screens/vault_preview_screen.dart';
import 'package:filezen/features/vault/presentation/screens/vault_screen.dart';
import 'package:filezen/features/vault/presentation/screens/vault_settings_screen.dart';
import 'package:filezen/features/vault/presentation/screens/vault_setup_screen.dart';
import 'package:filezen/features/vault/presentation/widgets/secure_share_dialog.dart';

import '../support/vault_test_doubles.dart';

class _FakeVaultStorageService implements IVaultStorageService {
  final List<VaultItem> items;
  final Uint8List? decryptedPayload;

  _FakeVaultStorageService({
    this.items = const [],
    this.decryptedPayload,
  });

  @override
  Future<List<VaultItem>> listVaultItems() async => items;

  @override
  Future<Result<Uint8List>> getDecryptedBytes(VaultItem item) async {
    return Result.success(
      decryptedPayload ?? Uint8List.fromList(utf8.encode('Confidential decrypted content')),
    );
  }

  @override
  Future<Result<VaultItem>> importFileToVault(String sourcePath, {bool deleteSource = true}) async {
    return Result.failure(UnknownError(message: 'Not used'));
  }

  @override
  Future<Result<FileEntity>> exportFileFromVault(VaultItem item, String destinationDirPath) async {
    return Result.failure(UnknownError(message: 'Not used'));
  }

  @override
  Future<Result<void>> deleteVaultItem(VaultItem item) async => Result.success(null);

  @override
  Future<Result<void>> emptyVault() async => Result.success(null);

  @override
  Future<int> getVaultTotalSizeBytes() async => 2048;
}

class _MockSessionNotifier extends StateNotifier<bool> implements VaultSessionNotifier {
  _MockSessionNotifier(super.initialState);

  @override
  late final VaultAuthService authService;

  @override
  late final Ref ref;

  @override
  void lock() {
    state = false;
  }

  @override
  Future<VaultAuthResult> unlockWithPin(String pin) async {
    if (pin == '1234') {
      state = true;
      return VaultAuthResult.success();
    }
    return VaultAuthResult.failure('Incorrect master PIN');
  }

  @override
  Future<bool> setupInitialPin(String pin) async {
    if (pin.length < 4) return false;
    state = true;
    return true;
  }

  @override
  Future<VaultAuthResult> unlockWithBiometrics() async {
    state = true;
    return VaultAuthResult.success();
  }
}

class _MockVaultItemsNotifier extends VaultItemsNotifier {
  final List<VaultItem> _mockItems;
  _MockVaultItemsNotifier(this._mockItems);

  @override
  Future<List<VaultItem>> build() async => _mockItems;
}

VaultAuthService _authWithBiometrics(bool available) => VaultAuthService(
      backend: FakeVaultCryptoBackend(),
      biometricGate: FakeBiometricGate()..available = available,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleItem = VaultItem(
    id: 'vault_1',
    vaultPath: '/data/user/0/com.filezen/files/.filezen_vault/files/sample.zenvault',
    originalFileName: 'confidential_agreement.txt',
    originalPath: '/storage/emulated/0/Documents/confidential_agreement.txt',
    fileSize: 1024,
    encryptedSize: 1120,
    category: FileCategory.document,
    mimeType: 'text/plain',
    encryptedAt: DateTime(2026, 10, 8),
  );

  Widget buildTestableWidget(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: child,
      ),
    );
  }

  group('VaultScreen Widget Tests', () {
    testWidgets('unconfigured vault offers one setup flow, not a PIN field', (tester) async {
      const unconfiguredConfig = VaultSecurityConfig(isPinConfigured: false);

      await tester.pumpWidget(
        buildTestableWidget(
          const VaultScreen(),
          overrides: [
            vaultSecurityConfigProvider.overrideWith((ref) => Future.value(unconfiguredConfig)),
            vaultSessionProvider.overrideWith((ref) => _MockSessionNotifier(false)),
            vaultAuthServiceProvider.overrideWithValue(_authWithBiometrics(false)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vault is Locked'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Set Up Vault'));
      await tester.pumpAndSettle();
      expect(find.byType(VaultSetupScreen), findsOneWidget);
      expect(find.text('There is no recovery'), findsOneWidget);
    });

    testWidgets('setup validates PIN, confirmation and the recovery acknowledgement', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = _MockSessionNotifier(false);
      await tester.pumpWidget(
        buildTestableWidget(
          const VaultSetupScreen(),
          overrides: [
            vaultSessionProvider.overrideWith((ref) => session),
            vaultAuthServiceProvider.overrideWithValue(_authWithBiometrics(false)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final pin = find.widgetWithText(TextField, 'Create a 4–6 digit PIN');
      final confirm = find.widgetWithText(TextField, 'Confirm PIN');
      final create = find.text('Create Vault');

      await tester.enterText(pin, '12');
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.text('Use 4 to 6 digits.'), findsOneWidget);

      await tester.enterText(pin, '1234');
      await tester.enterText(confirm, '4321');
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.text('The PINs do not match.'), findsOneWidget);

      await tester.enterText(confirm, '1234');
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.text('Please confirm you understand how recovery works.'), findsOneWidget);
      expect(session.state, isFalse);

      // Biometrics are not offered on a device without them.
      expect(find.byType(SwitchListTile), findsNothing);

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(session.state, isTrue, reason: 'vault created and unlocked');
    });

    testWidgets('biometric unlock is offered only when it is enabled', (tester) async {
      for (final enabled in [true, false]) {
        await tester.pumpWidget(const SizedBox()); // fresh ProviderScope per case
        await tester.pumpWidget(
          buildTestableWidget(
            const VaultScreen(),
            overrides: [
              vaultSecurityConfigProvider.overrideWith(
                (ref) => Future.value(VaultSecurityConfig(isPinConfigured: true, isBiometricEnabled: enabled)),
              ),
              vaultSessionProvider.overrideWith((ref) => _MockSessionNotifier(false)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Vault is Locked'), findsOneWidget);
        expect(find.text('Unlock Vault'), findsOneWidget);
        expect(find.text('Enter your Vault PIN'), findsOneWidget);
        expect(find.text('Use fingerprint / face'), enabled ? findsOneWidget : findsNothing);
      }
    });

    testWidgets('shows error on incorrect PIN entry and unlocks on correct PIN', (tester) async {
      const configuredConfig = VaultSecurityConfig(
        isPinConfigured: true,
        isBiometricEnabled: false,
      );
      final sessionNotifier = _MockSessionNotifier(false);

      await tester.pumpWidget(
        buildTestableWidget(
          const VaultScreen(),
          overrides: [
            vaultSecurityConfigProvider.overrideWith((ref) => Future.value(configuredConfig)),
            vaultSessionProvider.overrideWith((ref) => sessionNotifier),
            vaultItemsProvider.overrideWith(() => _MockVaultItemsNotifier([sampleItem])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // An empty PIN never triggers anything else (e.g. a biometric prompt).
      await tester.tap(find.text('Unlock Vault'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(sessionNotifier.state, isFalse);

      // Enter wrong PIN
      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('Unlock Vault'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect master PIN'), findsOneWidget);

      // Enter correct PIN
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock Vault'));
      await tester.pumpAndSettle();

      // Vault dashboard should now be rendered
      expect(find.text('Private Files'), findsOneWidget);
      expect(find.text('confidential_agreement.txt'), findsOneWidget);
    });

    testWidgets('renders unlocked dashboard with stats, search, and items', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const VaultScreen(),
          overrides: [
            vaultSessionProvider.overrideWith((ref) => _MockSessionNotifier(true)),
            vaultItemsProvider.overrideWith(() => _MockVaultItemsNotifier([sampleItem])),
            vaultStorageServiceProvider.overrideWithValue(
              _FakeVaultStorageService(items: [sampleItem]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Private Files'), findsOneWidget);
      expect(find.text('Hardware-Backed Security Active'), findsOneWidget);
      expect(find.text('confidential_agreement.txt'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget); // Lock action
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget); // Settings action
      expect(find.text('Add Files to Vault'), findsOneWidget); // Import FAB
    });

    testWidgets('tapping lock button locks vault', (tester) async {
      final sessionNotifier = _MockSessionNotifier(true);
      final configuredConfig = const VaultSecurityConfig(isPinConfigured: true);

      await tester.pumpWidget(
        buildTestableWidget(
          const VaultScreen(),
          overrides: [
            vaultSecurityConfigProvider.overrideWith((ref) => Future.value(configuredConfig)),
            vaultSessionProvider.overrideWith((ref) => sessionNotifier),
            vaultItemsProvider.overrideWith(() => _MockVaultItemsNotifier([sampleItem])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Private Files'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.lock_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Vault is Locked'), findsOneWidget);
    });
  });

  group('VaultSettingsScreen Widget Tests', () {
    testWidgets('renders security policies: PIN change, biometrics, auto-lock, and screenshots', (tester) async {
      final config = const VaultSecurityConfig(
        isPinConfigured: true,
        isBiometricEnabled: true,
        screenshotProtectionEnabled: true,
        autoLockTimeout: Duration(seconds: 30),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          const VaultSettingsScreen(),
          overrides: [
            vaultSecurityConfigProvider.overrideWith((ref) => Future.value(config)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vault Security Settings'), findsOneWidget);
      expect(find.text('Authenticated Enclave'), findsOneWidget);
      expect(find.text('Change Master PIN'), findsOneWidget);
      expect(find.text('Biometric Unlock'), findsOneWidget);
      expect(find.text('Screenshot Protection'), findsOneWidget);
      expect(find.text('Auto-Lock Policy'), findsOneWidget);
      expect(find.text('After 30 seconds'), findsOneWidget);
    });
  });

  group('VaultPreviewScreen Widget Tests', () {
    testWidgets('decrypts and renders text content in memory', (tester) async {
      final fakeStorage = _FakeVaultStorageService(
        decryptedPayload: Uint8List.fromList(utf8.encode('Secret Document Text in Memory')),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          VaultPreviewScreen(item: sampleItem),
          overrides: [
            vaultStorageServiceProvider.overrideWithValue(fakeStorage),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('confidential_agreement.txt'), findsOneWidget);
      expect(find.text('Secret Document Text in Memory'), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
    });
  });

  group('SecureShareDialog Widget Tests', () {
    testWidgets('renders share warning dialog with explicit confirmation buttons', (tester) async {
      bool? shareConfirmed;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    shareConfirmed = await SecureShareDialog.show(ctx, sampleItem);
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Security Warning'), findsOneWidget);
      expect(find.textContaining('You are about to share a decrypted copy'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Proceed to Share'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(shareConfirmed, isFalse);
    });
  });
}
