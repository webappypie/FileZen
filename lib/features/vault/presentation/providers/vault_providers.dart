import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../../../data/vault/vault_auth_service.dart';
import '../../../../data/vault/vault_cipher.dart';
import '../../../../data/vault/vault_storage_service.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../../domain/models/vault_models.dart';
import '../../../../domain/repositories/i_vault_storage_service.dart';
import '../../../files/presentation/providers/storage_providers.dart';

/// Provider for VaultCipher.
final vaultCipherProvider = Provider<VaultCipher>((ref) => VaultCipher());

/// Provider for VaultAuthService.
final vaultAuthServiceProvider = Provider<VaultAuthService>((ref) {
  final cipher = ref.watch(vaultCipherProvider);
  return VaultAuthService(cipher: cipher);
});

/// Provider for VaultStorageService.
final vaultStorageServiceProvider = Provider<IVaultStorageService>((ref) {
  final authService = ref.watch(vaultAuthServiceProvider);
  final storageRepo = ref.watch(storageRepositoryProvider);
  final cipher = ref.watch(vaultCipherProvider);
  return VaultStorageService(
    authService: authService,
    storageRepo: storageRepo,
    cipher: cipher,
  );
});

/// Provider loading current Vault security configuration.
final vaultSecurityConfigProvider =
    FutureProvider<VaultSecurityConfig>((ref) async {
  final authService = ref.watch(vaultAuthServiceProvider);
  return await authService.getSecurityConfig();
});

/// Notifier tracking vault unlock state and active session.
class VaultSessionNotifier extends StateNotifier<bool> {
  final VaultAuthService authService;
  final Ref ref;

  VaultSessionNotifier(this.authService, this.ref)
      : super(authService.isUnlocked);

  Future<VaultAuthResult> unlockWithPin(String pin) async {
    final result = await authService.verifyPin(pin);
    if (result.success) {
      state = true;
      ref.invalidate(vaultItemsProvider);
    }
    return result;
  }

  Future<bool> setupInitialPin(String pin) async {
    final success = await authService.setupPin(pin);
    if (success) {
      state = true;
      ref.invalidate(vaultSecurityConfigProvider);
      ref.invalidate(vaultItemsProvider);
    }
    return success;
  }

  Future<VaultAuthResult> unlockWithBiometrics() async {
    final result = await authService.authenticateWithBiometrics();
    if (result.success) {
      state = true;
      ref.invalidate(vaultItemsProvider);
    }
    return result;
  }

  void lock() {
    authService.lock();
    state = false;
    ref.invalidate(vaultItemsProvider);
  }
}

final vaultSessionProvider =
    StateNotifierProvider<VaultSessionNotifier, bool>((ref) {
  final authService = ref.watch(vaultAuthServiceProvider);
  return VaultSessionNotifier(authService, ref);
});

/// Async notifier managing private Vault items.
class VaultItemsNotifier extends AsyncNotifier<List<VaultItem>> {
  @override
  Future<List<VaultItem>> build() async {
    final isUnlocked = ref.watch(vaultSessionProvider);
    if (!isUnlocked) return [];

    final storage = ref.watch(vaultStorageServiceProvider);
    return await storage.listVaultItems();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    final storage = ref.read(vaultStorageServiceProvider);
    state = AsyncValue.data(await storage.listVaultItems());
  }

  Future<Result<VaultItem>> importFile(String sourcePath, {bool deleteSource = true}) async {
    final storage = ref.read(vaultStorageServiceProvider);
    final result = await storage.importFileToVault(sourcePath, deleteSource: deleteSource);
    if (result.isSuccess) {
      await refresh();
    }
    return result;
  }

  Future<Result<FileEntity>> exportFile(VaultItem item, String destinationDir) async {
    final storage = ref.read(vaultStorageServiceProvider);
    final result = await storage.exportFileFromVault(item, destinationDir);
    if (result.isSuccess) {
      await refresh();
    }
    return result;
  }

  Future<Result<void>> deleteItem(VaultItem item) async {
    final storage = ref.read(vaultStorageServiceProvider);
    final result = await storage.deleteVaultItem(item);
    if (result.isSuccess) {
      await refresh();
    }
    return result;
  }
}

final vaultItemsProvider =
    AsyncNotifierProvider<VaultItemsNotifier, List<VaultItem>>(
  VaultItemsNotifier.new,
);
