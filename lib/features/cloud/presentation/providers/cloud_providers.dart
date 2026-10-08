import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../../../data/cloud/cloud_provider_repository.dart';
import '../../../../domain/models/cloud_models.dart';
import '../../../../domain/models/network_models.dart';
import '../../../../domain/repositories/i_cloud_provider_repository.dart';

/// Provider for the singleton instance of ICloudProviderRepository.
final cloudProviderRepositoryProvider =
    Provider<ICloudProviderRepository>((ref) {
  return CloudProviderRepository();
});

/// Reactive stream provider for registered cloud accounts.
final cloudAccountsStreamProvider =
    StreamProvider<List<CloudAccount>>((ref) {
  final repo = ref.watch(cloudProviderRepositoryProvider);
  return repo.watchAccounts();
});

/// Controller handling cloud operations: connecting, disconnecting, and syncing quotas.
class CloudController extends StateNotifier<AsyncValue<void>> {
  final ICloudProviderRepository _repo;

  CloudController(this._repo) : super(const AsyncValue.data(null));

  Future<Result<CloudAccount>> connectAccount(
    CloudProviderType provider, {
    required String email,
    required String displayName,
  }) async {
    state = const AsyncValue.loading();
    final result = await _repo.connectAccount(
      provider,
      email: email,
      displayName: displayName,
    );
    state = const AsyncValue.data(null);
    return result;
  }

  Future<Result<void>> disconnectAccount(String accountId) async {
    state = const AsyncValue.loading();
    final result = await _repo.disconnectAccount(accountId);
    state = const AsyncValue.data(null);
    return result;
  }

  Future<Result<List<RemoteFileItem>>> listFiles(
    CloudAccount account, {
    String folderId = 'root',
  }) async {
    return _repo.listCloudFiles(account, folderId: folderId);
  }

  Future<Result<String>> downloadFile(
    CloudAccount account,
    RemoteFileItem file,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    return _repo.downloadCloudFile(
      account,
      file,
      destinationPath,
      onProgress: onProgress,
    );
  }

  Future<Result<RemoteFileItem>> uploadFile(
    CloudAccount account,
    String localFilePath,
    String remoteFolderId, {
    void Function(int sent, int total)? onProgress,
  }) async {
    return _repo.uploadCloudFile(
      account,
      localFilePath,
      remoteFolderId,
      onProgress: onProgress,
    );
  }

  Future<Result<CloudAccount>> refreshQuota(CloudAccount account) async {
    return _repo.refreshQuota(account);
  }
}

final cloudControllerProvider =
    StateNotifierProvider<CloudController, AsyncValue<void>>((ref) {
  final repo = ref.watch(cloudProviderRepositoryProvider);
  return CloudController(repo);
});
