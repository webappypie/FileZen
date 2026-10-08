import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/data/vault/vault_auth_service.dart';
import 'package:filezen/data/vault/vault_cipher.dart';
import 'package:filezen/data/vault/vault_storage_service.dart';
import 'package:filezen/domain/models/file_category.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VaultCipher (Authenticated CTR + PBKDF2-HMAC-SHA256)', () {
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

    test('encrypts and decrypts payload preserving plaintext and metadata', () {
      final plaintext = utf8.encode('Secret Document Confidential Contents 12345');
      final metadata = {
        'id': 'file-123',
        'name': 'confidential.pdf',
        'category': 'document',
      };
      const pin = '4321';

      final container = cipher.encryptPayload(
        plaintext: plaintext,
        metadata: metadata,
        pin: pin,
      );

      expect(container.isNotEmpty, isTrue);
      // Magic header check
      final magic = utf8.decode(container.sublist(0, 9));
      expect(magic, 'ZENVAULT\x01');

      final decrypted = cipher.decryptPayload(
        containerBytes: container,
        pin: pin,
      );

      expect(utf8.decode(decrypted.plaintext), 'Secret Document Confidential Contents 12345');
      expect(decrypted.metadata['id'], 'file-123');
      expect(decrypted.metadata['name'], 'confidential.pdf');
      expect(decrypted.metadata['category'], 'document');
    });

    test('fails decryption when PIN is incorrect', () {
      final plaintext = utf8.encode('Top Secret Financials');
      final metadata = {'name': 'taxes.xlsx'};

      final container = cipher.encryptPayload(
        plaintext: plaintext,
        metadata: metadata,
        pin: '1111',
      );

      expect(
        () => cipher.decryptPayload(containerBytes: container, pin: '2222'),
        throwsA(isA<FormatException>()),
      );
    });

    test('detects tampered ciphertext and rejects with FormatException', () {
      final plaintext = utf8.encode('Unmodified sensitive message');
      final metadata = {'name': 'message.txt'};

      final container = cipher.encryptPayload(
        plaintext: plaintext,
        metadata: metadata,
        pin: '9999',
      );

      // Mutate a byte in the encrypted content
      final tampered = Uint8List.fromList(container);
      final middleIdx = tampered.length - 40;
      tampered[middleIdx] = tampered[middleIdx] ^ 0xFF;

      expect(
        () => cipher.decryptPayload(containerBytes: tampered, pin: '9999'),
        throwsA(isA<FormatException>()),
      );
    });

    test('detects tampered authentication tag and rejects', () {
      final plaintext = utf8.encode('Data payload');
      final metadata = {'name': 'data.bin'};

      final container = cipher.encryptPayload(
        plaintext: plaintext,
        metadata: metadata,
        pin: '8888',
      );

      // Flip the last byte of the HMAC tag
      final tampered = Uint8List.fromList(container);
      tampered[tampered.length - 1] = tampered[tampered.length - 1] ^ 0x01;

      expect(
        () => cipher.decryptPayload(containerBytes: tampered, pin: '8888'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects truncated or malformed containers', () {
      final truncated = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () => cipher.decryptPayload(containerBytes: truncated, pin: '1234'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('VaultAuthService (Authentication & Lockout Protection)', () {
    late Directory tempDir;
    late VaultAuthService authService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vault_auth_test_');
      final configPath = p.join(tempDir.path, 'vault_auth.json');
      authService = VaultAuthService(customConfigPath: configPath);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('starts unconfigured and locked', () async {
      expect(await authService.isPinConfigured(), isFalse);
      expect(authService.isUnlocked, isFalse);
      expect(authService.activeSessionKey, isNull);
    });

    test('setupPin initializes configuration and unlocks session', () async {
      final success = await authService.setupPin('1234');
      expect(success, isTrue);
      expect(await authService.isPinConfigured(), isTrue);
      expect(authService.isUnlocked, isTrue);
      expect(authService.activePin, '1234');
      expect(authService.activeSessionKey, isNotNull);
    });

    test('setupPin rejects pins shorter than 4 digits', () async {
      final success = await authService.setupPin('12');
      expect(success, isFalse);
      expect(await authService.isPinConfigured(), isFalse);
    });

    test('lock securely clears session keys and locks vault', () async {
      await authService.setupPin('1234');
      expect(authService.isUnlocked, isTrue);

      authService.lock();
      expect(authService.isUnlocked, isFalse);
      expect(authService.activePin, isNull);
      expect(authService.activeSessionKey, isNull);
    });

    test('verifyPin succeeds with correct PIN and resets failed attempts', () async {
      await authService.setupPin('1234');
      authService.lock();

      // One bad attempt
      await authService.verifyPin('9999');
      final config1 = await authService.getSecurityConfig();
      expect(config1.failedAttempts, 1);

      // Correct attempt resets
      final result = await authService.verifyPin('1234');
      expect(result.success, isTrue);
      expect(authService.isUnlocked, isTrue);

      final config2 = await authService.getSecurityConfig();
      expect(config2.failedAttempts, 0);
    });

    test('locks out after 5 consecutive failed attempts', () async {
      await authService.setupPin('1234');
      authService.lock();

      for (int i = 0; i < 4; i++) {
        final res = await authService.verifyPin('0000');
        expect(res.success, isFalse);
        expect(res.isLockedOut, isFalse);
      }

      // 5th attempt triggers lockout
      final fifthRes = await authService.verifyPin('0000');
      expect(fifthRes.isLockedOut, isTrue);
      expect(fifthRes.cooldownRemainingSeconds, greaterThan(0));

      // Subsequent attempt is blocked even if correct PIN is entered during lockout
      final blockedRes = await authService.verifyPin('1234');
      expect(blockedRes.isLockedOut, isTrue);
    });

    test('changePin updates PIN after verifying old PIN', () async {
      await authService.setupPin('1234');
      authService.lock();

      // Wrong old PIN
      final failedChange = await authService.changePin('0000', '5678');
      expect(failedChange, isFalse);

      // Correct old PIN
      final successChange = await authService.changePin('1234', '5678');
      expect(successChange, isTrue);

      authService.lock();
      final verifyOld = await authService.verifyPin('1234');
      expect(verifyOld.success, isFalse);

      final verifyNew = await authService.verifyPin('5678');
      expect(verifyNew.success, isTrue);
    });

    test('biometric toggle and authentication', () async {
      await authService.setupPin('1234');
      expect(await authService.isBiometricAvailable(), isTrue);

      // Cannot auth biometrics when disabled
      authService.lock();
      final bioResDisabled = await authService.authenticateWithBiometrics();
      expect(bioResDisabled.success, isFalse);

      // Enable biometrics
      await authService.setBiometricEnabled(true);
      final config = await authService.getSecurityConfig();
      expect(config.isBiometricEnabled, isTrue);

      final bioResEnabled = await authService.authenticateWithBiometrics();
      expect(bioResEnabled.success, isTrue);
      expect(authService.isUnlocked, isTrue);
    });
  });

  group('VaultStorageService (Encrypted Files & Enclave Management)', () {
    late Directory tempDir;
    late FilesystemStorageRepository storageRepo;
    late VaultAuthService authService;
    late VaultStorageService storageService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vault_storage_test_');
      storageRepo = FilesystemStorageRepository();

      final authConfigPath = p.join(tempDir.path, 'vault_auth.json');
      authService = VaultAuthService(customConfigPath: authConfigPath);

      final vaultFilesPath = p.join(tempDir.path, 'vault_files');
      storageService = VaultStorageService(
        authService: authService,
        storageRepo: storageRepo,
        customVaultDirectoryPath: vaultFilesPath,
      );

      // Configure PIN and unlock
      await authService.setupPin('1234');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('prevents access when vault is locked', () async {
      final sample = File(p.join(tempDir.path, 'secret.txt'))..writeAsStringSync('data');
      authService.lock();

      final items = await storageService.listVaultItems();
      expect(items.isEmpty, isTrue);

      final importRes = await storageService.importFileToVault(sample.path);
      expect(importRes.isFailure, isTrue);
    });

    test('imports file, creates .zenvault container, and deletes unencrypted source', () async {
      final sampleFile = File(p.join(tempDir.path, 'statement.pdf'));
      await sampleFile.writeAsString('Bank Statement Confidential Transactions');

      final importRes = await storageService.importFileToVault(
        sampleFile.path,
        deleteSource: true,
      );

      expect(importRes.isSuccess, isTrue);
      final item = importRes.dataOrNull!;
      expect(item.originalFileName, 'statement.pdf');
      expect(item.category, FileCategory.document);
      expect(item.vaultPath.endsWith('.zenvault'), isTrue);

      // Verify unencrypted file was deleted
      expect(await sampleFile.exists(), isFalse);

      // Verify encrypted container exists
      final vaultFile = File(item.vaultPath);
      expect(await vaultFile.exists(), isTrue);
      expect(vaultFile.lengthSync(), greaterThan(0));

      // Verify item shows up in manifest
      final list = await storageService.listVaultItems();
      expect(list.length, 1);
      expect(list.first.id, item.id);
    });

    test('decrypts in-memory bytes without writing plaintext to disk', () async {
      final source = File(p.join(tempDir.path, 'passport.png'));
      await source.writeAsString('Passport Photo Binary Image Mock Bytes');

      final importRes = await storageService.importFileToVault(source.path, deleteSource: true);
      expect(importRes.isSuccess, isTrue);

      final bytesRes = await storageService.getDecryptedBytes(importRes.dataOrNull!);
      expect(bytesRes.isSuccess, isTrue);
      expect(
        utf8.decode(bytesRes.dataOrNull!),
        'Passport Photo Binary Image Mock Bytes',
      );
    });

    test('exports file from vault back to external directory', () async {
      final source = File(p.join(tempDir.path, 'notes.txt'));
      const text = 'Private diary notes entry';
      await source.writeAsString(text);

      final importRes = await storageService.importFileToVault(source.path, deleteSource: true);
      expect(importRes.isSuccess, isTrue);
      final item = importRes.dataOrNull!;

      final exportDir = Directory(p.join(tempDir.path, 'Exported'));
      final exportRes = await storageService.exportFileFromVault(item, exportDir.path);

      expect(exportRes.isSuccess, isTrue);
      final exportedEntity = exportRes.dataOrNull!;
      expect(exportedEntity.name, 'notes.txt');

      final exportedFile = File(exportedEntity.path);
      expect(await exportedFile.exists(), isTrue);
      expect(await exportedFile.readAsString(), text);

      // Encrypted file should be deleted upon export
      expect(await File(item.vaultPath).exists(), isFalse);

      // Manifest should be empty
      final list = await storageService.listVaultItems();
      expect(list.isEmpty, isTrue);
    });

    test('deletes individual vault item permanently', () async {
      final source = File(p.join(tempDir.path, 'old_secret.txt'))..writeAsStringSync('delete me');
      final importRes = await storageService.importFileToVault(source.path, deleteSource: true);
      final item = importRes.dataOrNull!;

      final delRes = await storageService.deleteVaultItem(item);
      expect(delRes.isSuccess, isTrue);
      expect(await File(item.vaultPath).exists(), isFalse);

      final list = await storageService.listVaultItems();
      expect(list.isEmpty, isTrue);
    });

    test('empties all vault items completely', () async {
      final f1 = File(p.join(tempDir.path, 'item1.txt'))..writeAsStringSync('1');
      final f2 = File(p.join(tempDir.path, 'item2.txt'))..writeAsStringSync('2');

      await storageService.importFileToVault(f1.path, deleteSource: true);
      await storageService.importFileToVault(f2.path, deleteSource: true);

      var list = await storageService.listVaultItems();
      expect(list.length, 2);

      final emptyRes = await storageService.emptyVault();
      expect(emptyRes.isSuccess, isTrue);

      list = await storageService.listVaultItems();
      expect(list.isEmpty, isTrue);
    });
  });
}
