import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/data/vault/vault_auth_service.dart';
import 'package:filezen/data/vault/vault_cipher.dart';
import 'package:filezen/data/vault/vault_container.dart';
import 'package:filezen/data/vault/vault_crypto_backend.dart';
import 'package:filezen/data/vault/vault_storage_service.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/vault_models.dart';

import '../support/vault_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VaultCipher (legacy v1 format, kept for migration)', () {
    late VaultCipher cipher;

    setUp(() {
      cipher = VaultCipher();
    });

    test('derives 32-byte encryption and authentication keys consistently', () {
      final salt = cipher.generateRandomBytes(32);
      final keys1 = cipher.deriveKeys('1234', salt);
      final keys2 = cipher.deriveKeys('1234', salt);

      expect(keys1.encKey.length, 32);
      expect(keys1.authKey.length, 32);
      expect(keys1.encKey, equals(keys2.encKey));
      expect(keys1.authKey, equals(keys2.authKey));
    });

    test('derives different keys for different PINs or salts', () {
      final salt = cipher.generateRandomBytes(32);
      final keysA = cipher.deriveKeys('1234', salt);
      final keysB = cipher.deriveKeys('5678', salt);

      expect(keysA.encKey, isNot(equals(keysB.encKey)));
      expect(keysA.authKey, isNot(equals(keysB.authKey)));
    });

    test('decrypts a v1 container it produced, including from a typed-data view', () {
      final container = cipher.encryptPayload(
        plaintext: utf8.encode('Secret Document Confidential Contents 12345'),
        metadata: {'id': 'file-123', 'name': 'confidential.pdf', 'category': 'document'},
        pin: '4321',
      );
      expect(utf8.decode(container.sublist(0, 9)), 'ZENVAULT\x01');

      final decrypted = cipher.decryptPayload(containerBytes: container, pin: '4321');
      expect(utf8.decode(decrypted.plaintext), 'Secret Document Confidential Contents 12345');
      expect(decrypted.metadata['name'], 'confidential.pdf');

      // A view with a non-zero offset must parse identically (regression: offset was ignored).
      final padded = Uint8List(container.length + 7)..setRange(7, container.length + 7, container);
      final view = Uint8List.sublistView(padded, 7);
      expect(cipher.decryptPayload(containerBytes: view, pin: '4321').metadata['id'], 'file-123');
    });

    test('rejects wrong PIN, tampering and truncated containers', () {
      final container = cipher.encryptPayload(
        plaintext: utf8.encode('Top Secret Financials'),
        metadata: {'name': 'taxes.xlsx'},
        pin: '1111',
      );
      expect(() => cipher.decryptPayload(containerBytes: container, pin: '2222'),
          throwsA(isA<FormatException>()));

      final tampered = Uint8List.fromList(container);
      tampered[tampered.length - 40] ^= 0xFF;
      expect(() => cipher.decryptPayload(containerBytes: tampered, pin: '1111'),
          throwsA(isA<FormatException>()));

      expect(() => cipher.decryptPayload(containerBytes: Uint8List.fromList([1, 2, 3]), pin: '1'),
          throwsA(isA<FormatException>()));
    });
  });

  group('VaultContainer v2 (AES-256-GCM container format)', () {
    late FakeVaultCryptoBackend backend;
    late Uint8List key;

    setUp(() {
      backend = FakeVaultCryptoBackend();
      key = VaultCipher().generateRandomBytes(32);
    });

    test('round-trips content and metadata', () async {
      final sealed = await VaultContainer.seal(
        backend,
        key: key,
        plaintext: Uint8List.fromList(utf8.encode('hello vault')),
        metadata: {'name': 'a.txt'},
      );
      expect(VaultContainer.isV2(sealed), isTrue);
      final opened = await VaultContainer.open(backend, key: key, container: sealed);
      expect(utf8.decode(opened.plaintext), 'hello vault');
      expect(opened.metadata['name'], 'a.txt');
    });

    test('metadata and content use independent nonces', () async {
      final sealed = await VaultContainer.seal(
        backend,
        key: key,
        plaintext: Uint8List.fromList(utf8.encode('x' * 64)),
        metadata: {'name': 'a.txt'},
      );
      final metaLen = ByteData.sublistView(sealed).getUint32(9);
      final metaNonce = sealed.sublist(13, 25);
      final contentNonce = sealed.sublist(13 + metaLen, 13 + metaLen + 12);
      expect(metaNonce, isNot(equals(contentNonce)));
    });

    test('does not leak plaintext or metadata names in the bytes', () async {
      final sealed = await VaultContainer.seal(
        backend,
        key: key,
        plaintext: Uint8List.fromList(utf8.encode('PLAINTEXT-MARKER-VALUE')),
        metadata: {'name': 'secret-passport.pdf', 'path': '/storage/emulated/0/DCIM'},
      );
      final text = latin1.decode(sealed);
      expect(text.contains('PLAINTEXT-MARKER-VALUE'), isFalse);
      expect(text.contains('secret-passport'), isFalse);
      expect(text.contains('/storage/emulated'), isFalse);
    });

    test('rejects wrong key, tampered content/metadata/length, and swapped halves', () async {
      final sealed = await VaultContainer.seal(
        backend,
        key: key,
        plaintext: Uint8List.fromList(utf8.encode('payload payload')),
        metadata: {'name': 'a.txt'},
      );

      final otherKey = Uint8List.fromList(key)..[0] ^= 1;
      await expectLater(
        VaultContainer.open(backend, key: otherKey, container: sealed),
        throwsA(isA<VaultCryptoException>()
            .having((e) => e.code, 'code', VaultCryptoException.authFailed)),
      );

      for (final index in [sealed.length - 1, sealed.length - 20, 40]) {
        final bad = Uint8List.fromList(sealed)..[index] ^= 0x01;
        await expectLater(
          VaultContainer.open(backend, key: key, container: bad),
          throwsA(isA<VaultCryptoException>()),
          reason: 'tamper at $index',
        );
      }

      final badLen = Uint8List.fromList(sealed);
      ByteData.sublistView(badLen).setUint32(9, 0xFFFFFFF0);
      await expectLater(
        VaultContainer.open(backend, key: key, container: badLen),
        throwsA(isA<FormatException>()),
      );

      // Content blob from another container cannot be spliced under this metadata.
      final other = await VaultContainer.seal(
        backend,
        key: key,
        plaintext: Uint8List.fromList(utf8.encode('OTHER payload!!')),
        metadata: {'name': 'b.txt'},
      );
      final metaLen = ByteData.sublistView(sealed).getUint32(9);
      final otherMetaLen = ByteData.sublistView(other).getUint32(9);
      final spliced = Uint8List.fromList([
        ...sealed.sublist(0, 13 + metaLen),
        ...other.sublist(13 + otherMetaLen),
      ]);
      await expectLater(
        VaultContainer.open(backend, key: key, container: spliced),
        throwsA(isA<VaultCryptoException>()),
      );
    });

    test('rejects truncated and foreign-format containers', () async {
      await expectLater(
        VaultContainer.open(backend, key: key, container: Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FormatException>()),
      );
      final v1 = VaultCipher().encryptPayload(
        plaintext: [1, 2, 3],
        metadata: {'a': 'b'},
        pin: '1234',
      );
      expect(VaultContainer.isLegacyV1(v1), isTrue);
      await expectLater(
        VaultContainer.open(backend, key: key, container: v1),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('VaultAuthService (key hierarchy, biometrics & lockout)', () {
    late Directory tempDir;
    late String configPath;
    late FakeVaultCryptoBackend backend;
    late FakeBiometricGate gate;
    late VaultAuthService authService;

    VaultAuthService newService() =>
        VaultAuthService(customConfigPath: configPath, backend: backend, biometricGate: gate);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vault_auth_test_');
      configPath = p.join(tempDir.path, 'vault_auth.json');
      backend = FakeVaultCryptoBackend();
      gate = FakeBiometricGate();
      authService = newService();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('starts unconfigured and locked', () async {
      expect(await authService.isPinConfigured(), isFalse);
      expect(authService.isUnlocked, isFalse);
      expect(authService.activeSessionKey, isNull);
    });

    test('setupPin creates a random 256-bit master key that is not derived from the PIN', () async {
      expect(await authService.setupPin('1234'), isTrue);
      expect(await authService.isPinConfigured(), isTrue);
      expect(authService.isUnlocked, isTrue);

      final key = authService.activeSessionKey!;
      expect(key.length, 32);
      expect(key, isNot(equals(utf8.encode('1234'))));
      expect(key.any((b) => b != 0), isTrue);
    });

    test('config file stores no PIN, PIN verifier, or key material in the clear', () async {
      await authService.setupPin('482913');
      final masterKey = Uint8List.fromList(authService.activeSessionKey!);
      final text = await File(configPath).readAsString();
      final json = jsonDecode(text) as Map<String, dynamic>;

      expect(json.containsKey('pinHash'), isFalse);
      expect(json.containsKey('biometricToken'), isFalse);
      expect(json.containsKey('saltHex'), isFalse);
      expect(text.contains('482913'), isFalse);
      expect(text.contains(base64Encode(masterKey)), isFalse);
      expect(text.contains(masterKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()), isFalse);
      expect(json['wrappedKey'], isNotNull);
      expect((json['kdf'] as Map)['iterations'], VaultAuthService.pinIterations);
    });

    test('setupPin rejects short PINs and refuses to overwrite an existing vault', () async {
      expect(await authService.setupPin('12'), isFalse);
      expect(await authService.isPinConfigured(), isFalse);

      expect(await authService.setupPin('1234'), isTrue);
      final before = await File(configPath).readAsString();
      authService.lock();
      expect(await authService.setupPin('9999'), isFalse);
      expect(await File(configPath).readAsString(), before);
      expect((await authService.verifyPin('1234')).success, isTrue);
    });

    test('lock zeroes the key material in place and clears the session', () async {
      await authService.setupPin('1234');
      final keyRef = authService.activeSessionKey!;
      expect(keyRef.any((b) => b != 0), isTrue);

      authService.lock();
      expect(authService.isUnlocked, isFalse);
      expect(authService.activeSessionKey, isNull);
      expect(keyRef.every((b) => b == 0), isTrue);
    });

    test('verifyPin restores the same master key and resets failed attempts', () async {
      await authService.setupPin('1234');
      final original = Uint8List.fromList(authService.activeSessionKey!);
      authService.lock();

      await authService.verifyPin('9999');
      expect((await authService.getSecurityConfig()).failedAttempts, 1);

      final result = await authService.verifyPin('1234');
      expect(result.success, isTrue);
      expect(authService.activeSessionKey, equals(original));
      expect((await authService.getSecurityConfig()).failedAttempts, 0);
    });

    test('a new service instance (app restart) unlocks with the PIN', () async {
      await authService.setupPin('1234');
      final original = Uint8List.fromList(authService.activeSessionKey!);

      final restarted = newService();
      expect(restarted.isUnlocked, isFalse);
      expect((await restarted.verifyPin('0000')).success, isFalse);
      expect((await restarted.verifyPin('1234')).success, isTrue);
      expect(restarted.activeSessionKey, equals(original));
    });

    test('locks out after 5 consecutive failures, even for the correct PIN', () async {
      await authService.setupPin('1234');
      authService.lock();

      for (var i = 0; i < 4; i++) {
        final res = await authService.verifyPin('0000');
        expect(res.success, isFalse);
        expect(res.isLockedOut, isFalse);
      }
      final fifth = await authService.verifyPin('0000');
      expect(fifth.isLockedOut, isTrue);
      expect(fifth.cooldownRemainingSeconds, greaterThan(0));

      final blocked = await authService.verifyPin('1234');
      expect(blocked.isLockedOut, isTrue);
      expect(authService.isUnlocked, isFalse);
    });

    test('Keystore trouble is reported but does not count as a wrong PIN', () async {
      await authService.setupPin('1234');
      authService.lock();

      backend.deviceKeyPresent = false;
      final res = await authService.verifyPin('1234');
      expect(res.success, isFalse);
      expect(res.errorMessage, contains('security key'));
      expect((await authService.getSecurityConfig()).failedAttempts, 0);
      expect(authService.isUnlocked, isFalse);
    });

    test('a vault copied without the device Keystore key cannot be opened with the PIN', () async {
      await authService.setupPin('1234');
      authService.lock();

      final otherDevice = FakeVaultCryptoBackend(); // same secrets in fake: simulate key loss instead
      otherDevice.deviceKeyPresent = false;
      final copy = VaultAuthService(
        customConfigPath: configPath,
        backend: otherDevice,
        biometricGate: gate,
      );
      expect((await copy.verifyPin('1234')).success, isFalse);
      expect(copy.isUnlocked, isFalse);
    });

    test('changePin re-wraps the master key without changing it', () async {
      await authService.setupPin('1234');
      final original = Uint8List.fromList(authService.activeSessionKey!);
      authService.lock();

      expect(await authService.changePin('0000', '5678'), isFalse);
      expect(await authService.changePin('1234', '12'), isFalse);
      expect(await authService.changePin('1234', '5678'), isTrue);

      authService.lock();
      expect((await authService.verifyPin('1234')).success, isFalse);
      authService.lock();
      final res = await authService.verifyPin('5678');
      expect(res.success, isTrue);
      expect(authService.activeSessionKey, equals(original));
    });

    test('a damaged config is never treated as "not configured"', () async {
      await authService.setupPin('1234');
      authService.lock();
      await File(configPath).writeAsString('{ this is not json');

      expect(await authService.isPinConfigured(), isTrue);
      expect(await authService.setupPin('9999'), isFalse);
      final res = await authService.verifyPin('1234');
      expect(res.success, isFalse);
      expect(res.errorMessage, contains('damaged'));
      expect(await File(configPath).readAsString(), '{ this is not json');
    });

    group('biometrics', () {
      test('cannot be used while disabled', () async {
        await authService.setupPin('1234');
        authService.lock();
        final res = await authService.authenticateWithBiometrics();
        expect(res.success, isFalse);
        expect(authService.isUnlocked, isFalse);
        expect(gate.authenticateCalls, 0);
      });

      test('cannot be enabled while the vault is locked or hardware is unavailable', () async {
        await authService.setupPin('1234');
        gate.available = false;
        expect(await authService.setBiometricEnabled(true), isFalse);
        gate.available = true;
        authService.lock();
        expect(await authService.setBiometricEnabled(true), isFalse);
        expect((await authService.getSecurityConfig()).isBiometricEnabled, isFalse);
      });

      test('enabling requires a successful prompt', () async {
        await authService.setupPin('1234');
        gate.result = false;
        expect(await authService.setBiometricEnabled(true), isFalse);
        expect((await authService.getSecurityConfig()).isBiometricEnabled, isFalse);
        expect(gate.authenticateCalls, 1);
      });

      test('unlocks with the same master key after a successful prompt', () async {
        await authService.setupPin('1234');
        final original = Uint8List.fromList(authService.activeSessionKey!);
        expect(await authService.setBiometricEnabled(true), isTrue);
        expect((await authService.getSecurityConfig()).isBiometricEnabled, isTrue);

        authService.lock();
        final res = await authService.authenticateWithBiometrics();
        expect(res.success, isTrue);
        expect(authService.isUnlocked, isTrue);
        expect(authService.activeSessionKey, equals(original));
      });

      test('failed, cancelled or throwing prompts never unlock', () async {
        await authService.setupPin('1234');
        await authService.setBiometricEnabled(true);
        authService.lock();

        gate.result = false;
        expect((await authService.authenticateWithBiometrics()).success, isFalse);
        expect(authService.isUnlocked, isFalse);

        gate
          ..result = true
          ..throwOnAuthenticate = true;
        expect((await authService.authenticateWithBiometrics()).success, isFalse);
        expect(authService.isUnlocked, isFalse);
        expect(authService.activeSessionKey, isNull);
      });

      test('unavailable hardware fails closed', () async {
        await authService.setupPin('1234');
        await authService.setBiometricEnabled(true);
        authService.lock();
        gate.available = false;
        expect((await authService.authenticateWithBiometrics()).success, isFalse);
        expect(authService.isUnlocked, isFalse);
      });

      test('Keystore refusal (no recent auth) keeps the vault locked', () async {
        await authService.setupPin('1234');
        await authService.setBiometricEnabled(true);
        authService.lock();
        backend.biometricRecentlyAuthenticated = false;
        final res = await authService.authenticateWithBiometrics();
        expect(res.success, isFalse);
        expect(authService.isUnlocked, isFalse);
      });

      test('invalidated biometric key disables biometrics and the PIN still works', () async {
        await authService.setupPin('1234');
        await authService.setBiometricEnabled(true);
        authService.lock();

        backend.biometricKeyInvalidated = true;
        final res = await authService.authenticateWithBiometrics();
        expect(res.success, isFalse);
        expect(res.errorMessage, contains('PIN'));
        expect((await authService.getSecurityConfig()).isBiometricEnabled, isFalse);

        expect((await authService.verifyPin('1234')).success, isTrue);
      });

      test('disabling removes the wrapped key', () async {
        await authService.setupPin('1234');
        await authService.setBiometricEnabled(true);
        await authService.setBiometricEnabled(false);

        final json = jsonDecode(await File(configPath).readAsString()) as Map<String, dynamic>;
        expect(json.containsKey('bioWrappedKey'), isFalse);
        expect(json['isBiometricEnabled'], isFalse);
        authService.lock();
        expect((await authService.authenticateWithBiometrics()).success, isFalse);
      });

      test('biometric unlock does not bypass lockout', () async {
        await authService.setupPin('1234');
        await authService.setBiometricEnabled(true);
        authService.lock();
        for (var i = 0; i < 5; i++) {
          await authService.verifyPin('0000');
        }
        final res = await authService.authenticateWithBiometrics();
        expect(res.success, isFalse);
        expect(res.isLockedOut, isTrue);
      });
    });
  });

  group('VaultStorageService (encrypted files, index & migration)', () {
    late Directory tempDir;
    late FilesystemStorageRepository storageRepo;
    late FakeVaultCryptoBackend backend;
    late FakeBiometricGate gate;
    late VaultAuthService authService;
    late VaultStorageService storageService;
    late String vaultFilesPath;

    VaultStorageService newStorage(VaultAuthService auth) => VaultStorageService(
          authService: auth,
          storageRepo: storageRepo,
          customVaultDirectoryPath: vaultFilesPath,
        );

    VaultAuthService newAuth() => VaultAuthService(
          customConfigPath: p.join(tempDir.path, 'vault_auth.json'),
          backend: backend,
          biometricGate: gate,
        );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vault_storage_test_');
      storageRepo = FilesystemStorageRepository();
      backend = FakeVaultCryptoBackend();
      gate = FakeBiometricGate();
      vaultFilesPath = p.join(tempDir.path, 'vault_files');
      authService = newAuth();
      storageService = newStorage(authService);
      await authService.setupPin('1234');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('prevents access when vault is locked', () async {
      final sample = File(p.join(tempDir.path, 'secret.txt'))..writeAsStringSync('data');
      authService.lock();

      expect(await storageService.listVaultItems(), isEmpty);
      expect((await storageService.importFileToVault(sample.path)).isFailure, isTrue);
      expect(await sample.exists(), isTrue);
    });

    test('imports into a randomly named .zenvault v2 container and deletes the source', () async {
      final sampleFile = File(p.join(tempDir.path, 'statement.pdf'));
      await sampleFile.writeAsString('Bank Statement Confidential Transactions');

      final importRes = await storageService.importFileToVault(sampleFile.path, deleteSource: true);
      expect(importRes.isSuccess, isTrue);
      final item = importRes.dataOrNull!;
      expect(item.originalFileName, 'statement.pdf');
      expect(item.category, FileCategory.document);
      expect(item.vaultPath.endsWith('.zenvault'), isTrue);
      expect(p.basename(item.vaultPath).contains('statement'), isFalse);
      expect(await sampleFile.exists(), isFalse);

      final bytes = await File(item.vaultPath).readAsBytes();
      expect(VaultContainer.isV2(bytes), isTrue);

      final list = await storageService.listVaultItems();
      expect(list.length, 1);
      expect(list.first.id, item.id);
    });

    test('nothing under the vault directory reveals names, paths or content', () async {
      final source = File(p.join(tempDir.path, 'passport_scan.png'));
      await source.writeAsString('SUPER-SECRET-PIXELS');
      await storageService.importFileToVault(source.path, deleteSource: true);

      final everything = StringBuffer();
      await for (final e in tempDir.list(recursive: true)) {
        everything.write(p.relative(e.path, from: tempDir.path));
        if (e is File) everything.write(latin1.decode(await e.readAsBytes()));
      }
      final blob = everything.toString();
      expect(blob.contains('passport_scan'), isFalse);
      expect(blob.contains('SUPER-SECRET-PIXELS'), isFalse);
      expect(blob.contains(tempDir.path.replaceAll('\\', '/')), isFalse);
      expect(File(p.join(tempDir.path, VaultStorageService.manifestFileName)).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, VaultStorageService.legacyManifestFileName)).existsSync(), isFalse);
    });

    test('index is unreadable while locked and returns after unlock', () async {
      final source = File(p.join(tempDir.path, 'a.txt'))..writeAsStringSync('A');
      await storageService.importFileToVault(source.path, deleteSource: true);

      authService.lock();
      expect(await storageService.listVaultItems(), isEmpty);

      await authService.verifyPin('1234');
      final items = await storageService.listVaultItems();
      expect(items.single.originalFileName, 'a.txt');
    });

    test('decrypts in-memory bytes without writing plaintext to disk', () async {
      final source = File(p.join(tempDir.path, 'passport.png'));
      await source.writeAsString('Passport Photo Binary Image Mock Bytes');

      final importRes = await storageService.importFileToVault(source.path, deleteSource: true);
      final bytesRes = await storageService.getDecryptedBytes(importRes.dataOrNull!);
      expect(bytesRes.isSuccess, isTrue);
      expect(utf8.decode(bytesRes.dataOrNull!), 'Passport Photo Binary Image Mock Bytes');
      expect(await source.exists(), isFalse);
    });

    test('rejects tampered containers instead of returning garbage', () async {
      final source = File(p.join(tempDir.path, 'doc.txt'))..writeAsStringSync('important content');
      final item = (await storageService.importFileToVault(source.path)).dataOrNull!;

      final file = File(item.vaultPath);
      final bytes = await file.readAsBytes();
      bytes[bytes.length - 20] ^= 0x01;
      await file.writeAsBytes(bytes);

      expect((await storageService.getDecryptedBytes(item)).isFailure, isTrue);
      expect((await storageService.exportFileFromVault(item, p.join(tempDir.path, 'out'))).isFailure,
          isTrue);
      expect(await file.exists(), isTrue, reason: 'failed export must keep the encrypted copy');
    });

    test('exports to a directory, removes the encrypted copy and the index entry', () async {
      final source = File(p.join(tempDir.path, 'notes.txt'));
      const text = 'Private diary notes entry';
      await source.writeAsString(text);
      final item = (await storageService.importFileToVault(source.path)).dataOrNull!;

      final exportDir = Directory(p.join(tempDir.path, 'Exported'));
      final exportRes = await storageService.exportFileFromVault(item, exportDir.path);
      expect(exportRes.isSuccess, isTrue);
      expect(exportRes.dataOrNull!.name, 'notes.txt');
      expect(await File(exportRes.dataOrNull!.path).readAsString(), text);
      expect(await File(item.vaultPath).exists(), isFalse);
      expect(await storageService.listVaultItems(), isEmpty);
    });

    test('export cannot escape the destination via a hostile stored name', () async {
      final source = File(p.join(tempDir.path, 'plain.txt'))..writeAsStringSync('payload');
      final item = (await storageService.importFileToVault(source.path)).dataOrNull!;
      final hostile = VaultItem(
        id: item.id,
        vaultPath: item.vaultPath,
        originalFileName: '../../escaped.txt',
        originalPath: item.originalPath,
        fileSize: item.fileSize,
        encryptedSize: item.encryptedSize,
        category: item.category,
        encryptedAt: item.encryptedAt,
      );

      final dest = Directory(p.join(tempDir.path, 'dest'));
      final res = await storageService.exportFileFromVault(hostile, dest.path);
      expect(res.isSuccess, isTrue);
      expect(p.isWithin(dest.path, res.dataOrNull!.path), isTrue);
      expect(File(p.join(tempDir.path, 'escaped.txt')).existsSync(), isFalse);
    });

    test('deletes an individual item permanently', () async {
      final source = File(p.join(tempDir.path, 'old_secret.txt'))..writeAsStringSync('delete me');
      final item = (await storageService.importFileToVault(source.path)).dataOrNull!;

      expect((await storageService.deleteVaultItem(item)).isSuccess, isTrue);
      expect(await File(item.vaultPath).exists(), isFalse);
      expect(await storageService.listVaultItems(), isEmpty);
    });

    test('destructive operations require an unlocked vault', () async {
      final source = File(p.join(tempDir.path, 'keep.txt'))..writeAsStringSync('keep');
      final item = (await storageService.importFileToVault(source.path)).dataOrNull!;
      authService.lock();

      expect((await storageService.deleteVaultItem(item)).isFailure, isTrue);
      expect((await storageService.emptyVault()).isFailure, isTrue);
      expect(await File(item.vaultPath).exists(), isTrue);
    });

    test('empties all vault items completely', () async {
      for (final n in ['item1.txt', 'item2.txt']) {
        final f = File(p.join(tempDir.path, n))..writeAsStringSync(n);
        await storageService.importFileToVault(f.path);
      }
      expect((await storageService.listVaultItems()).length, 2);

      expect((await storageService.emptyVault()).isSuccess, isTrue);
      expect(await storageService.listVaultItems(), isEmpty);
    });

    test('concurrent imports all land in the index (no lost updates)', () async {
      final files = [
        for (var i = 0; i < 6; i++) File(p.join(tempDir.path, 'f$i.txt'))..writeAsStringSync('c$i'),
      ];
      final results = await Future.wait(files.map((f) => storageService.importFileToVault(f.path)));
      expect(results.every((r) => r.isSuccess), isTrue);
      expect((await storageService.listVaultItems()).length, 6);
    });

    test('an unreadable index fails writes instead of silently replacing it', () async {
      final a = File(p.join(tempDir.path, 'a.txt'))..writeAsStringSync('A');
      await storageService.importFileToVault(a.path);

      final manifest = File(p.join(tempDir.path, VaultStorageService.manifestFileName));
      final good = await manifest.readAsBytes();
      final broken = Uint8List.fromList(good)..[good.length - 1] ^= 0xFF;
      await manifest.writeAsBytes(broken);

      final b = File(p.join(tempDir.path, 'b.txt'))..writeAsStringSync('B');
      final res = await storageService.importFileToVault(b.path);
      expect(res.isFailure, isTrue);
      expect(await b.exists(), isTrue, reason: 'source must survive a failed import');
      expect(await manifest.readAsBytes(), equals(broken), reason: 'index must not be overwritten');

      await manifest.writeAsBytes(good);
      expect((await storageService.listVaultItems()).length, 1);
    });

    test('files stay readable after a PIN change and after a restart', () async {
      final source = File(p.join(tempDir.path, 'persist.txt'))..writeAsStringSync('persist me');
      final item = (await storageService.importFileToVault(source.path)).dataOrNull!;

      expect(await authService.changePin('1234', '8642'), isTrue);
      authService.lock();

      final restartedAuth = newAuth();
      final restartedStorage = newStorage(restartedAuth);
      expect((await restartedAuth.verifyPin('8642')).success, isTrue);
      final bytes = await restartedStorage.getDecryptedBytes(item);
      expect(utf8.decode(bytes.dataOrNull!), 'persist me');
    });

    test('a failed import leaves the vault directory and the source untouched', () async {
      final source = File(p.join(tempDir.path, 'orphan.txt'))..writeAsStringSync('x');
      // Corrupt the index so the import must fail.
      final first = File(p.join(tempDir.path, 'first.txt'))..writeAsStringSync('1');
      await storageService.importFileToVault(first.path);
      final manifest = File(p.join(tempDir.path, VaultStorageService.manifestFileName));
      final good = await manifest.readAsBytes();
      await manifest.writeAsBytes(Uint8List.fromList(good)..[0] ^= 1);

      final before = Directory(vaultFilesPath).listSync().length;
      final res = await storageService.importFileToVault(source.path);
      expect(res.isFailure, isTrue);
      expect(Directory(vaultFilesPath).listSync().length, before);
      expect(await source.exists(), isTrue);
    });

    group('legacy (v1) migration', () {
      late VaultCipher legacyCipher;

      Future<void> writeLegacyVault(String pin, Map<String, String> files) async {
        legacyCipher = VaultCipher();
        final salt = legacyCipher.generateRandomBytes(32);
        final saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final pinHash = Hmac(sha256, salt).convert(utf8.encode(pin)).toString();
        final config = const VaultSecurityConfig(
          isPinConfigured: true,
          isBiometricEnabled: true,
        ).toJson()
          ..['pinHash'] = pinHash
          ..['saltHex'] = saltHex
          ..['biometricToken'] = 'deadbeef';
        await File(p.join(tempDir.path, 'vault_auth.json')).writeAsString(jsonEncode(config));

        final dir = Directory(vaultFilesPath)..createSync(recursive: true);
        final manifest = <Map<String, dynamic>>[];
        var n = 0;
        for (final entry in files.entries) {
          final id = 'legacy_${n++}';
          final container = legacyCipher.encryptPayload(
            plaintext: utf8.encode(entry.value),
            metadata: {
              'id': id,
              'name': entry.key,
              'path': '/storage/emulated/0/Documents/${entry.key}',
              'size': entry.value.length,
              'mimeType': 'text/plain',
              'category': 'document',
              'encryptedAt': DateTime(2026, 1, 2).toIso8601String(),
            },
            secretKey: utf8.encode(pin),
          );
          final path = p.join(dir.path, '17000000${n}_${p.basenameWithoutExtension(entry.key)}.zenvault');
          File(path).writeAsBytesSync(container);
          manifest.add(VaultItem(
            id: id,
            vaultPath: path,
            originalFileName: entry.key,
            originalPath: '/storage/emulated/0/Documents/${entry.key}',
            fileSize: entry.value.length,
            encryptedSize: container.length,
            category: FileCategory.document,
            encryptedAt: DateTime(2026, 1, 2),
          ).toJson());
        }
        await File(p.join(tempDir.path, VaultStorageService.legacyManifestFileName))
            .writeAsString(jsonEncode(manifest));
      }

      test('upgrades config, re-encrypts containers, hides names and removes the plaintext index',
          () async {
        // Fresh state: replace the setUp vault with a legacy one.
        authService.lock();
        await File(p.join(tempDir.path, 'vault_auth.json')).delete();
        await writeLegacyVault('2468', {'tax_return.txt': 'legacy tax data', 'photo_list.txt': 'legacy photos'});

        final auth = newAuth();
        final storage = newStorage(auth);

        // Wrong PIN against a legacy config still fails.
        expect((await auth.verifyPin('0000')).success, isFalse);
        expect((await auth.verifyPin('2468')).success, isTrue);

        final cfgText = await File(p.join(tempDir.path, 'vault_auth.json')).readAsString();
        final cfg = jsonDecode(cfgText) as Map<String, dynamic>;
        expect(cfg.containsKey('pinHash'), isFalse);
        expect(cfg.containsKey('biometricToken'), isFalse);
        expect(cfg.containsKey('saltHex'), isFalse);
        expect(cfg['wrappedKey'], isNotNull);
        expect(cfg['isBiometricEnabled'], isFalse);
        expect(cfg['legacyMigrationPending'], isTrue);

        final items = await storage.listVaultItems();
        expect(items.map((i) => i.originalFileName).toSet(), {'tax_return.txt', 'photo_list.txt'});

        for (final item in items) {
          final bytes = await File(item.vaultPath).readAsBytes();
          expect(VaultContainer.isV2(bytes), isTrue);
          expect(p.basename(item.vaultPath).contains('tax_return'), isFalse);
        }
        final tax = items.firstWhere((i) => i.originalFileName == 'tax_return.txt');
        expect(utf8.decode((await storage.getDecryptedBytes(tax)).dataOrNull!), 'legacy tax data');

        // Plaintext index and legacy files are gone; the pending flag is cleared.
        expect(File(p.join(tempDir.path, VaultStorageService.legacyManifestFileName)).existsSync(), isFalse);
        final remaining = Directory(vaultFilesPath).listSync().whereType<File>().toList();
        expect(remaining.length, 2);
        expect(remaining.every((f) => !f.path.contains('tax_return')), isTrue);
        final cfgAfter = jsonDecode(await File(p.join(tempDir.path, 'vault_auth.json')).readAsString())
            as Map<String, dynamic>;
        expect(cfgAfter.containsKey('legacyMigrationPending'), isFalse);
        expect(auth.pendingLegacyKey, isNull);

        // Subsequent restart uses only the v2 path.
        auth.lock();
        final auth2 = newAuth();
        expect((await auth2.verifyPin('2468')).success, isTrue);
        expect((await newStorage(auth2).listVaultItems()).length, 2);
      });

      test('an interrupted migration resumes on the next PIN unlock', () async {
        authService.lock();
        await File(p.join(tempDir.path, 'vault_auth.json')).delete();
        await writeLegacyVault('2468', {'resume.txt': 'resume me'});

        final auth = newAuth();
        expect((await auth.verifyPin('2468')).success, isTrue);
        // App dies before the storage layer migrates anything.
        auth.lock();

        final auth2 = newAuth();
        final storage2 = newStorage(auth2);
        expect((await auth2.verifyPin('2468')).success, isTrue);
        expect(auth2.pendingLegacyKey, isNotNull);

        final items = await storage2.listVaultItems();
        expect(items.single.originalFileName, 'resume.txt');
        expect(utf8.decode((await storage2.getDecryptedBytes(items.single)).dataOrNull!), 'resume me');
      });
    });
  });
}
