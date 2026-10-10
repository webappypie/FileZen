import 'dart:io';

import 'package:filezen/data/vault/secure_window.dart';
import 'package:filezen/data/vault/vault_auth_service.dart';
import 'package:filezen/data/vault/vault_crypto_backend.dart';
import 'package:filezen/domain/models/vault_models.dart';
import 'package:filezen/features/vault/presentation/providers/vault_lifecycle_guard.dart';
import 'package:filezen/features/vault/presentation/providers/vault_providers.dart';
import 'package:filezen/features/vault/presentation/widgets/secure_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/vault_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureSurface (FLAG_SECURE wiring)', () {
    late List<bool> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannelVaultCryptoBackend.channel,
        (call) async {
          if (call.method == 'setSecure') {
            calls.add((call.arguments as Map)['secure'] as bool);
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelVaultCryptoBackend.channel, null);
    });

    Widget host({required bool active, required bool protection}) => ProviderScope(
          overrides: [
            vaultSecurityConfigProvider.overrideWith(
              (ref) async => VaultSecurityConfig(
                isPinConfigured: true,
                screenshotProtectionEnabled: protection,
              ),
            ),
          ],
          child: MaterialApp(
            home: SecureSurface(active: active, child: const Text('private')),
          ),
        );

    testWidgets('applies the secure flag while visible and clears it on dispose', (tester) async {
      await tester.pumpWidget(host(active: true, protection: true));
      await tester.pumpAndSettle();
      expect(calls, [true]);
      expect(SecureWindow.holders, 1);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(calls, [true, false]);
      expect(SecureWindow.holders, 0);
    });

    testWidgets('respects the Screenshot Protection setting', (tester) async {
      await tester.pumpWidget(host(active: true, protection: false));
      await tester.pumpAndSettle();
      // Fails closed while the setting loads, then releases once it reads "off".
      expect(calls.last, isFalse);
      expect(SecureWindow.holders, 0);
    });

    testWidgets('does nothing when the surface is not active', (tester) async {
      await tester.pumpWidget(host(active: false, protection: true));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(SecureWindow.holders, 0);
    });

    testWidgets('overlapping surfaces do not clear each other', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SecureSurface(
              active: true,
              child: SecureSurface(active: true, child: const Text('x')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(SecureWindow.holders, 2);
      expect(calls, [true]);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(SecureWindow.holders, 0);
      expect(calls, [true, false]);
    });
  });

  group('VaultLifecycleGuard (auto-lock)', () {
    late Directory tempDir;
    late VaultAuthService auth;
    late ProviderContainer container;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vault_guard_test_');
      auth = VaultAuthService(
        customConfigPath: p.join(tempDir.path, 'vault_auth.json'),
        backend: FakeVaultCryptoBackend(),
        biometricGate: FakeBiometricGate(),
      );
      container = ProviderContainer(overrides: [vaultAuthServiceProvider.overrideWithValue(auth)]);
      addTearDown(container.dispose);
      container.read(vaultLifecycleGuardProvider);
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } on FileSystemException {
        // A late async read can still hold the temp file on Windows; harmless.
      }
    });

    Future<void> unlock() async {
      await auth.setupPin('1234');
      await container.read(vaultSessionProvider.notifier).unlockWithPin('1234');
      expect(container.read(vaultSessionProvider), isTrue);
    }

    testWidgets('locks immediately on background with the default (zero) timeout', (tester) async {
      await tester.runAsync(unlock);
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      expect(container.read(vaultSessionProvider), isFalse);
      expect(auth.isUnlocked, isFalse);
      expect(auth.activeSessionKey, isNull);
    });

    testWidgets('does not lock for inactive (biometric prompt, dialogs, shade)', (tester) async {
      await tester.runAsync(unlock);
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      expect(container.read(vaultSessionProvider), isTrue);
      expect(auth.isUnlocked, isTrue);
    });

    testWidgets('honors a non-zero timeout: stays unlocked on a quick return', (tester) async {
      await tester.runAsync(() async {
        await unlock();
        final cfg = await auth.getSecurityConfig();
        await auth.updateSecurityConfig(cfg.copyWith(autoLockTimeout: const Duration(seconds: 30)));
      });

      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(container.read(vaultSessionProvider), isTrue);

      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(container.read(vaultSessionProvider), isTrue);
    });

    testWidgets('locks on resume once the timeout has elapsed', (tester) async {
      await tester.runAsync(() async {
        await unlock();
        final cfg = await auth.getSecurityConfig();
        await auth.updateSecurityConfig(cfg.copyWith(autoLockTimeout: const Duration(seconds: 1)));
      });

      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      });
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      expect(container.read(vaultSessionProvider), isFalse);
      expect(auth.isUnlocked, isFalse);
    });

    testWidgets('locks while still in the background once the timeout elapses', (tester) async {
      await tester.runAsync(() async {
        await unlock();
        final cfg = await auth.getSecurityConfig();
        await auth.updateSecurityConfig(cfg.copyWith(autoLockTimeout: const Duration(seconds: 1)));
      });

      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      expect(auth.isUnlocked, isTrue, reason: 'within the timeout');

      // No resume: the key must not stay in memory past the timeout.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1200)));
      expect(container.read(vaultSessionProvider), isFalse);
      expect(auth.activeSessionKey, isNull);
    });
  });
}
