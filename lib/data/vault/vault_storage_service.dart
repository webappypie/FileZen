import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/vault_models.dart';
import '../../domain/repositories/i_storage_repository.dart';
import '../../domain/repositories/i_vault_storage_service.dart';
import 'vault_auth_service.dart';
import 'vault_cipher.dart';
import 'vault_container.dart';
import 'vault_crypto_backend.dart';
import 'vault_file_io.dart';

/// Encrypted vault storage.
///
///  * Every item is a v2 [VaultContainer] (AES-256-GCM) stored under a random
///    file name, so neither names nor original paths appear on disk.
///  * The item index (names, original paths, sizes) is itself AES-256-GCM
///    encrypted with the master key; the vault cannot be enumerated while locked.
///  * Legacy (pre-v2) containers and the plaintext manifest are migrated on the
///    first unlock after upgrade.
class VaultStorageService implements IVaultStorageService {
  /// Single-shot AEAD needs the whole item in memory (twice, plus native
  /// copies), so larger files are refused instead of risking an out-of-memory
  /// crash mid-encryption.
  static const int maxItemBytes = 100 * 1024 * 1024;

  static const String manifestFileName = 'vault_manifest.enc';
  static const String legacyManifestFileName = 'vault_manifest.json';

  static final Uint8List _manifestAad = Uint8List.fromList(utf8.encode('zenvault-manifest-v2'));

  final VaultAuthService authService;
  final IStorageRepository storageRepo;
  final VaultCipher cipher;
  final String? customVaultDirectoryPath;

  VaultStorageService({
    required this.authService,
    required this.storageRepo,
    VaultCipher? cipher,
    this.customVaultDirectoryPath,
  }) : cipher = cipher ?? VaultCipher();

  VaultCryptoBackend get _backend => authService.backend;

  // Serialises manifest read-modify-write cycles and migration.
  Future<void> _queue = Future<void>.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<Directory> _getVaultDirectory() async {
    if (customVaultDirectoryPath != null) {
      final dir = Directory(customVaultDirectoryPath!);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, '.filezen_vault', 'files'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  File _manifestFile(Directory vaultDir) =>
      File(p.join(vaultDir.parent.path, manifestFileName));

  File _legacyManifestFile(Directory vaultDir) =>
      File(p.join(vaultDir.parent.path, legacyManifestFileName));

  /// Copies the current session key. Must be called immediately before the
  /// crypto call that uses it (no `await` in between) so a concurrent lock()
  /// can never leave a zeroed key in use.
  Uint8List? _sessionKeyCopy() {
    final key = authService.activeSessionKey;
    if (key == null || !authService.isUnlocked) return null;
    if (key.every((b) => b == 0)) return null;
    return Uint8List.fromList(key);
  }

  AccessDeniedError _locked(String path, String action) =>
      AccessDeniedError(path: path, message: 'Vault is locked. Unlock before $action.');

  String _randomContainerName() {
    final bytes = cipher.generateRandomBytes(16);
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$hex.zenvault';
  }

  // ---------------------------------------------------------------------------
  // Encrypted manifest
  // ---------------------------------------------------------------------------

  /// Reads and authenticates the manifest. Throws on any decryption/parse
  /// failure: callers must never treat an unreadable manifest as empty, or a
  /// later write would erase the index of every vaulted file.
  Future<List<VaultItem>> _loadManifest(Directory vaultDir) async {
    final file = _manifestFile(vaultDir);
    if (!await file.exists()) return <VaultItem>[];

    final key = _sessionKeyCopy();
    if (key == null) throw StateError('Vault is locked');
    final blob = await file.readAsBytes();
    final plain = await _backend.gcmDecrypt(key: key, data: blob, aad: _manifestAad);
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! List) throw const FormatException('Vault manifest is malformed');
    return decoded
        .map((e) => VaultItem.fromJson(e as Map<String, dynamic>))
        .toList(growable: true);
  }

  Future<void> _saveManifest(Directory vaultDir, List<VaultItem> items) async {
    final key = _sessionKeyCopy();
    if (key == null) throw StateError('Vault is locked');
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(items.map((i) => i.toJson()).toList())));
    final blob = await _backend.gcmEncrypt(key: key, data: plain, aad: _manifestAad);
    await atomicWriteBytes(_manifestFile(vaultDir), blob);
  }

  // ---------------------------------------------------------------------------
  // Legacy migration
  // ---------------------------------------------------------------------------

  /// Re-encrypts pre-v2 containers (PIN-derived HMAC-CTR) into v2 containers
  /// with random names, rebuilds the manifest encrypted, and deletes the
  /// plaintext manifest. Runs only while the legacy key is available (i.e. right
  /// after a PIN unlock) and is idempotent: interrupted runs resume next unlock.
  Future<void> _migrateLegacyIfNeeded(Directory vaultDir) async {
    final legacyKey = authService.pendingLegacyKey;
    final legacyManifest = _legacyManifestFile(vaultDir);
    if (legacyKey == null && !await legacyManifest.exists()) return;

    final items = await _loadManifest(vaultDir);
    var failures = 0;

    if (legacyKey != null) {
      final knownPaths = items.map((i) => p.basename(i.vaultPath)).toSet();
      await for (final entity in vaultDir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.zenvault')) continue;
        if (knownPaths.contains(p.basename(entity.path))) continue;

        try {
          final bytes = await entity.readAsBytes();
          if (!VaultContainer.isLegacyV1(bytes)) continue;

          final legacy = cipher.decryptPayload(containerBytes: bytes, secretKey: legacyKey);
          final meta = legacy.metadata;
          final newKey = _sessionKeyCopy();
          if (newKey == null) throw StateError('Vault locked during migration');
          final sealed = await VaultContainer.seal(
            _backend,
            key: newKey,
            plaintext: legacy.plaintext,
            metadata: meta,
          );

          final newFile = File(p.join(vaultDir.path, _randomContainerName()));
          await atomicWriteBytes(newFile, sealed);
          items.add(VaultItem(
            id: (meta['id'] as String?) ?? p.basenameWithoutExtension(newFile.path),
            vaultPath: newFile.path,
            originalFileName: (meta['name'] as String?) ?? 'Recovered file',
            originalPath: (meta['path'] as String?) ?? '',
            fileSize: (meta['size'] as int?) ?? legacy.plaintext.length,
            encryptedSize: sealed.length,
            category: FileCategory.values.firstWhere(
              (c) => c.name == meta['category'],
              orElse: () => FileCategory.other,
            ),
            mimeType: meta['mimeType'] as String?,
            encryptedAt: DateTime.tryParse((meta['encryptedAt'] as String?) ?? '') ?? DateTime.now(),
          ));
          // Persist the index before removing the only other copy.
          await _saveManifest(vaultDir, items);
          await entity.delete();
        } catch (e) {
          failures++;
          AppLogger.error('Could not migrate a legacy vault container: ${e.runtimeType}', 'VaultStorage');
        }
      }
    }

    await _saveManifest(vaultDir, items);
    if (await legacyManifest.exists()) {
      // The plaintext index leaks names and original paths; remove it for good.
      await legacyManifest.delete();
    }
    if (legacyKey != null) {
      await authService.completeLegacyMigration();
      if (failures > 0) {
        AppLogger.warning('$failures legacy vault file(s) could not be migrated', 'VaultStorage');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // IVaultStorageService
  // ---------------------------------------------------------------------------

  @override
  Future<List<VaultItem>> listVaultItems() async {
    if (!authService.isUnlocked) return [];

    return _synchronized(() async {
      try {
        final vaultDir = await _getVaultDirectory();
        await _migrateLegacyIfNeeded(vaultDir);
        final manifest = await _loadManifest(vaultDir);

        final verified = <VaultItem>[];
        for (final item in manifest) {
          if (await File(item.vaultPath).exists()) verified.add(item);
        }
        verified.sort((a, b) => b.encryptedAt.compareTo(a.encryptedAt));
        return verified;
      } catch (e) {
        AppLogger.error('Failed to read vault index: ${e.runtimeType}', 'VaultStorage');
        return <VaultItem>[];
      }
    });
  }

  @override
  Future<Result<VaultItem>> importFileToVault(
    String sourcePath, {
    bool deleteSource = true,
  }) {
    return _synchronized(() async {
      if (!authService.isUnlocked) {
        return Result<VaultItem>.failure(_locked(sourcePath, 'locking files'));
      }

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return Result<VaultItem>.failure(FileNotFoundError(path: sourcePath));
      }

      File? createdContainer;
      try {
        final length = await sourceFile.length();
        if (length > maxItemBytes) {
          return Result<VaultItem>.failure(UnknownError(
            message: 'File is too large for the Vault '
                '(limit ${maxItemBytes ~/ (1024 * 1024)} MB).',
          ));
        }

        final vaultDir = await _getVaultDirectory();
        await _migrateLegacyIfNeeded(vaultDir);
        final manifest = await _loadManifest(vaultDir);

        final plaintextBytes = await sourceFile.readAsBytes();
        final entity = await storageRepo.getFileDetails(sourcePath);

        final metadata = {
          'id': entity.id,
          'name': entity.name,
          'path': entity.path,
          'size': entity.size,
          'mimeType': entity.mimeType,
          'category': entity.category.name,
          'encryptedAt': DateTime.now().toIso8601String(),
        };

        final key = _sessionKeyCopy();
        if (key == null) {
          return Result<VaultItem>.failure(_locked(sourcePath, 'locking files'));
        }
        final container = await VaultContainer.seal(
          _backend,
          key: key,
          plaintext: plaintextBytes,
          metadata: metadata,
        );

        final vaultFile = File(p.join(vaultDir.path, _randomContainerName()));
        await atomicWriteBytes(vaultFile, container);
        createdContainer = vaultFile;

        // Prove the container decrypts to the original before the source is touched.
        final verifyKey = _sessionKeyCopy();
        if (verifyKey == null) {
          throw StateError('Vault locked during encryption');
        }
        final check = await VaultContainer.open(
          _backend,
          key: verifyKey,
          container: await vaultFile.readAsBytes(),
        );
        if (check.plaintext.length != plaintextBytes.length) {
          throw const FormatException('Encrypted copy failed verification');
        }

        final vaultItem = VaultItem(
          id: entity.id,
          vaultPath: vaultFile.path,
          originalFileName: entity.name,
          originalPath: entity.path,
          fileSize: entity.size,
          encryptedSize: container.length,
          category: entity.category,
          mimeType: entity.mimeType,
          encryptedAt: DateTime.now(),
        );

        // Replacing an item with the same id: remember the superseded container.
        final replaced = manifest.where((i) => i.id == vaultItem.id).toList();
        manifest.removeWhere((i) => i.id == vaultItem.id);
        manifest.add(vaultItem);
        await _saveManifest(vaultDir, manifest);
        createdContainer = null; // now referenced by the manifest

        for (final old in replaced) {
          try {
            final f = File(old.vaultPath);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }

        if (deleteSource) {
          await storageRepo.delete(sourcePath);
        }

        AppLogger.info('Imported and encrypted a file into the Vault', 'VaultStorage');
        return Result<VaultItem>.success(vaultItem);
      } catch (e) {
        AppLogger.error('Failed to import file into Vault: ${e.runtimeType}', 'VaultStorage');
        // Never leave an unreferenced container behind; the source is untouched.
        try {
          if (createdContainer != null && await createdContainer.exists()) {
            await createdContainer.delete();
          }
        } catch (_) {}
        return Result<VaultItem>.failure(UnknownError(message: 'Vault encryption failed: $e'));
      }
    });
  }

  @override
  Future<Result<FileEntity>> exportFileFromVault(
    VaultItem item,
    String destinationDirPath,
  ) {
    return _synchronized(() async {
      if (!authService.isUnlocked) {
        return Result<FileEntity>.failure(_locked(item.vaultPath, 'exporting files'));
      }

      final vaultFile = File(item.vaultPath);
      if (!await vaultFile.exists()) {
        return Result<FileEntity>.failure(FileNotFoundError(path: item.vaultPath));
      }

      try {
        final key = _sessionKeyCopy();
        if (key == null) {
          return Result<FileEntity>.failure(_locked(item.vaultPath, 'exporting files'));
        }
        final decrypted = await VaultContainer.open(
          _backend,
          key: key,
          container: await vaultFile.readAsBytes(),
        );

        final destDir = Directory(destinationDirPath);
        if (!await destDir.exists()) await destDir.create(recursive: true);

        // basename(): never let a stored name escape the destination directory.
        final safeName = p.basename(item.originalFileName);
        var targetPath = p.join(destDir.path, safeName);
        if (await File(targetPath).exists()) {
          final base = p.basenameWithoutExtension(safeName);
          final ext = p.extension(safeName);
          targetPath = p.join(destDir.path, '${base}_restored$ext');
        }

        final exportedFile = File(targetPath);
        await exportedFile.writeAsBytes(decrypted.plaintext, flush: true);
        if (await exportedFile.length() != decrypted.plaintext.length) {
          throw const FileSystemException('Exported file is incomplete');
        }

        // Read the index first so a failure here leaves the encrypted copy intact;
        // delete it only after the export is verified.
        final vaultDir = await _getVaultDirectory();
        final manifest = await _loadManifest(vaultDir);
        await vaultFile.delete();
        manifest.removeWhere((i) => i.id == item.id || i.vaultPath == item.vaultPath);
        await _saveManifest(vaultDir, manifest);

        final exportedDetails = await storageRepo.getFileDetails(targetPath);
        AppLogger.info('Decrypted and exported a file from the Vault', 'VaultStorage');
        return Result<FileEntity>.success(exportedDetails);
      } catch (e) {
        AppLogger.error('Failed to export file from Vault: ${e.runtimeType}', 'VaultStorage');
        return Result<FileEntity>.failure(UnknownError(message: 'Vault export failed: $e'));
      }
    });
  }

  @override
  Future<Result<Uint8List>> getDecryptedBytes(VaultItem item) async {
    final key = _sessionKeyCopy();
    if (key == null) {
      return Result.failure(_locked(item.vaultPath, 'previewing files'));
    }

    final vaultFile = File(item.vaultPath);
    if (!await vaultFile.exists()) {
      return Result.failure(FileNotFoundError(path: item.vaultPath));
    }

    try {
      final containerBytes = await vaultFile.readAsBytes();
      // Re-copy: the session may have been locked while the file was read.
      final useKey = _sessionKeyCopy();
      if (useKey == null) {
        return Result.failure(_locked(item.vaultPath, 'previewing files'));
      }
      final decrypted = await VaultContainer.open(
        _backend,
        key: useKey,
        container: containerBytes,
      );
      return Result.success(decrypted.plaintext);
    } catch (e) {
      AppLogger.error('Failed to decrypt vault item in memory: ${e.runtimeType}', 'VaultStorage');
      return Result.failure(UnknownError(message: 'Decryption failed: $e'));
    }
  }

  @override
  Future<Result<void>> deleteVaultItem(VaultItem item) {
    return _synchronized(() async {
      if (!authService.isUnlocked) {
        return Result<void>.failure(_locked(item.vaultPath, 'deleting files'));
      }
      try {
        final vaultDir = await _getVaultDirectory();
        final manifest = await _loadManifest(vaultDir);
        manifest.removeWhere((i) => i.id == item.id || i.vaultPath == item.vaultPath);
        await _saveManifest(vaultDir, manifest);

        final vaultFile = File(item.vaultPath);
        if (await vaultFile.exists()) await vaultFile.delete();

        AppLogger.info('Deleted an encrypted vault item', 'VaultStorage');
        return Result<void>.success(null);
      } catch (e) {
        AppLogger.error('Failed to delete vault file: ${e.runtimeType}', 'VaultStorage');
        return Result<void>.failure(UnknownError(message: 'Delete failed: $e'));
      }
    });
  }

  @override
  Future<Result<void>> emptyVault() {
    return _synchronized(() async {
      if (!authService.isUnlocked) {
        return Result<void>.failure(_locked('vault', 'emptying the Vault'));
      }
      try {
        final vaultDir = await _getVaultDirectory();
        if (await vaultDir.exists()) {
          await for (final entity in vaultDir.list(followLinks: false)) {
            try {
              await entity.delete(recursive: true);
            } catch (_) {}
          }
        }
        await _saveManifest(vaultDir, <VaultItem>[]);
        AppLogger.info('Emptied all vault items', 'VaultStorage');
        return Result<void>.success(null);
      } catch (e) {
        AppLogger.error('Failed to empty vault: ${e.runtimeType}', 'VaultStorage');
        return Result<void>.failure(UnknownError(message: 'Failed to empty vault: $e'));
      }
    });
  }

  @override
  Future<int> getVaultTotalSizeBytes() async {
    final items = await listVaultItems();
    return items.fold<int>(0, (sum, i) => sum + i.encryptedSize);
  }
}
