import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/vault_models.dart';
import '../../domain/repositories/i_storage_repository.dart';
import '../../domain/repositories/i_vault_storage_service.dart';
import 'vault_auth_service.dart';
import 'vault_cipher.dart';

/// Implementation of IVaultStorageService managing encrypted storage containers,
/// isolated import/export, and in-memory decryption.
class VaultStorageService implements IVaultStorageService {
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

  Future<Directory> _getVaultDirectory() async {
    if (customVaultDirectoryPath != null) {
      final dir = Directory(customVaultDirectoryPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, '.filezen_vault', 'files'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _getManifestFile(Directory vaultDir) {
    return File(p.join(vaultDir.parent.path, 'vault_manifest.json'));
  }

  Future<List<VaultItem>> _readManifest() async {
    try {
      final vaultDir = await _getVaultDirectory();
      final manifestFile = _getManifestFile(vaultDir);
      if (!await manifestFile.exists()) return [];

      final content = await manifestFile.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      return list
          .map((item) => VaultItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.warning('Failed to read vault manifest: $e', 'VaultStorage');
      return [];
    }
  }

  Future<void> _writeManifest(List<VaultItem> items) async {
    try {
      final vaultDir = await _getVaultDirectory();
      final manifestFile = _getManifestFile(vaultDir);
      await manifestFile.writeAsString(
        jsonEncode(items.map((i) => i.toJson()).toList()),
        flush: true,
      );
    } catch (e) {
      AppLogger.error('Failed to write vault manifest: $e', 'VaultStorage');
    }
  }

  @override
  Future<List<VaultItem>> listVaultItems() async {
    if (!authService.isUnlocked) return [];

    final manifest = await _readManifest();
    final verified = <VaultItem>[];

    for (final item in manifest) {
      if (await File(item.vaultPath).exists()) {
        verified.add(item);
      }
    }

    // Sort newest encrypted first
    verified.sort((a, b) => b.encryptedAt.compareTo(a.encryptedAt));
    return verified;
  }

  @override
  Future<Result<VaultItem>> importFileToVault(
    String sourcePath, {
    bool deleteSource = true,
  }) async {
    final pin = authService.activePin;
    if (pin == null || !authService.isUnlocked) {
      return Result.failure(AccessDeniedError(
        path: sourcePath,
        message: 'Vault is locked. Unlock with PIN before locking files.',
      ));
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return Result.failure(FileNotFoundError(path: sourcePath));
    }

    try {
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

      final encryptedContainer = cipher.encryptPayload(
        plaintext: plaintextBytes,
        metadata: metadata,
        pin: pin,
      );

      final vaultDir = await _getVaultDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeVaultName = '${timestamp}_${p.basenameWithoutExtension(entity.name)}.zenvault';
      final vaultFilePath = p.join(vaultDir.path, safeVaultName);

      final vaultFile = File(vaultFilePath);
      await vaultFile.writeAsBytes(encryptedContainer, flush: true);

      final vaultItem = VaultItem(
        id: entity.id,
        vaultPath: vaultFilePath,
        originalFileName: entity.name,
        originalPath: entity.path,
        fileSize: entity.size,
        encryptedSize: encryptedContainer.length,
        category: entity.category,
        mimeType: entity.mimeType,
        encryptedAt: DateTime.now(),
      );

      final manifest = await _readManifest();
      manifest.removeWhere((i) => i.id == vaultItem.id || i.vaultPath == vaultItem.vaultPath);
      manifest.add(vaultItem);
      await _writeManifest(manifest);

      // Securely delete unencrypted original file if requested
      if (deleteSource) {
        await storageRepo.delete(sourcePath);
      }

      AppLogger.info('Imported and encrypted file into Vault: ${entity.name}', 'VaultStorage');
      return Result.success(vaultItem);
    } catch (e) {
      AppLogger.error('Failed to import file into Vault: $e', 'VaultStorage');
      return Result.failure(UnknownError(message: 'Vault encryption failed: $e'));
    }
  }

  @override
  Future<Result<FileEntity>> exportFileFromVault(
    VaultItem item,
    String destinationDirPath,
  ) async {
    final pin = authService.activePin;
    if (pin == null || !authService.isUnlocked) {
      return Result.failure(AccessDeniedError(
        path: item.vaultPath,
        message: 'Vault is locked. Unlock before exporting files.',
      ));
    }

    final vaultFile = File(item.vaultPath);
    if (!await vaultFile.exists()) {
      return Result.failure(FileNotFoundError(path: item.vaultPath));
    }

    try {
      final containerBytes = await vaultFile.readAsBytes();
      final decrypted = cipher.decryptPayload(
        containerBytes: containerBytes,
        pin: pin,
      );

      final destDir = Directory(destinationDirPath);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      var targetPath = p.join(destDir.path, item.originalFileName);
      if (await File(targetPath).exists()) {
        final base = p.basenameWithoutExtension(item.originalFileName);
        final ext = p.extension(item.originalFileName);
        targetPath = p.join(destDir.path, '${base}_restored$ext');
      }

      final exportedFile = File(targetPath);
      await exportedFile.writeAsBytes(decrypted.plaintext, flush: true);

      // Delete the encrypted vault file upon successful export
      await vaultFile.delete();

      final manifest = await _readManifest();
      manifest.removeWhere((i) => i.id == item.id || i.vaultPath == item.vaultPath);
      await _writeManifest(manifest);

      final exportedDetails = await storageRepo.getFileDetails(targetPath);
      AppLogger.info('Decrypted and exported file from Vault: $targetPath', 'VaultStorage');
      return Result.success(exportedDetails);
    } catch (e) {
      AppLogger.error('Failed to export file from Vault: $e', 'VaultStorage');
      return Result.failure(UnknownError(message: 'Vault export failed: $e'));
    }
  }

  @override
  Future<Result<Uint8List>> getDecryptedBytes(VaultItem item) async {
    final pin = authService.activePin;
    if (pin == null || !authService.isUnlocked) {
      return Result.failure(AccessDeniedError(
        path: item.vaultPath,
        message: 'Vault is locked. Unlock before previewing files.',
      ));
    }

    final vaultFile = File(item.vaultPath);
    if (!await vaultFile.exists()) {
      return Result.failure(FileNotFoundError(path: item.vaultPath));
    }

    try {
      final containerBytes = await vaultFile.readAsBytes();
      final decrypted = cipher.decryptPayload(
        containerBytes: containerBytes,
        pin: pin,
      );
      return Result.success(decrypted.plaintext);
    } catch (e) {
      AppLogger.error('Failed to decrypt in-memory bytes for ${item.originalFileName}: $e', 'VaultStorage');
      return Result.failure(UnknownError(message: 'Decryption failed: $e'));
    }
  }

  @override
  Future<Result<void>> deleteVaultItem(VaultItem item) async {
    try {
      final vaultFile = File(item.vaultPath);
      if (await vaultFile.exists()) {
        await vaultFile.delete();
      }

      final manifest = await _readManifest();
      manifest.removeWhere((i) => i.id == item.id || i.vaultPath == item.vaultPath);
      await _writeManifest(manifest);

      AppLogger.info('Deleted encrypted vault item: ${item.originalFileName}', 'VaultStorage');
      return Result.success(null);
    } catch (e) {
      AppLogger.error('Failed to delete vault file: $e', 'VaultStorage');
      return Result.failure(UnknownError(message: 'Delete failed: $e'));
    }
  }

  @override
  Future<Result<void>> emptyVault() async {
    try {
      final vaultDir = await _getVaultDirectory();
      if (await vaultDir.exists()) {
        for (final entity in vaultDir.listSync()) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
      await _writeManifest([]);
      AppLogger.info('Emptied all vault items', 'VaultStorage');
      return Result.success(null);
    } catch (e) {
      AppLogger.error('Failed to empty vault: $e', 'VaultStorage');
      return Result.failure(UnknownError(message: 'Failed to empty vault: $e'));
    }
  }

  @override
  Future<int> getVaultTotalSizeBytes() async {
    final items = await listVaultItems();
    return items.fold<int>(0, (sum, i) => sum + i.encryptedSize);
  }
}
