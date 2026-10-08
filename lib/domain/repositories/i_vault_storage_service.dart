import 'dart:typed_data';
import '../../core/result/result.dart';
import '../models/file_entity.dart';
import '../models/vault_models.dart';

/// Contract for encrypted vault storage, isolated import/export, and in-memory decryption.
abstract class IVaultStorageService {
  /// Lists all encrypted files currently residing in the Vault.
  Future<List<VaultItem>> listVaultItems();

  /// Encrypts and moves/imports an external file into the Vault.
  /// If [deleteSource] is true, the original unencrypted file is securely removed.
  Future<Result<VaultItem>> importFileToVault(
    String sourcePath, {
    bool deleteSource = true,
  });

  /// Decrypts a vault item back to plaintext at the given destination directory.
  Future<Result<FileEntity>> exportFileFromVault(
    VaultItem item,
    String destinationDirPath,
  );

  /// Decrypts a vault item directly into memory for private viewing with zero disk leakage.
  Future<Result<Uint8List>> getDecryptedBytes(VaultItem item);

  /// Permanently deletes an encrypted file from the Vault.
  Future<Result<void>> deleteVaultItem(VaultItem item);

  /// Permanently removes all items from the Vault.
  Future<Result<void>> emptyVault();

  /// Returns total bytes occupied by encrypted files in the Vault.
  Future<int> getVaultTotalSizeBytes();
}
