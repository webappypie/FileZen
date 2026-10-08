import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../../../data/network/network_transfer_repository.dart';
import '../../../../domain/models/network_models.dart';
import '../../../../domain/repositories/i_network_transfer_repository.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';

/// Provider for the singleton instance of INetworkTransferRepository.
final networkTransferRepositoryProvider =
    Provider<INetworkTransferRepository>((ref) {
  final notificationRepo = ref.watch(notificationRepositoryProvider);
  return NetworkTransferRepository(notificationRepository: notificationRepo);
});

/// Reactive stream provider for configured network servers.
final networkServersStreamProvider =
    StreamProvider<List<NetworkServerConfig>>((ref) {
  final repo = ref.watch(networkTransferRepositoryProvider);
  return repo.watchServers();
});

/// Reactive stream provider for the local Wi-Fi / LAN web sharing session.
final lanSessionStreamProvider = StreamProvider<LanTransferSession>((ref) {
  final repo = ref.watch(networkTransferRepositoryProvider);
  return repo.watchLanSession();
});

/// Reactive stream provider for active and queued file transfers.
final transfersStreamProvider =
    StreamProvider<List<NetworkTransferTask>>((ref) {
  final repo = ref.watch(networkTransferRepositoryProvider);
  return repo.watchTransfers();
});

/// Count of currently transferring or queued tasks.
final activeTransfersCountProvider = Provider<int>((ref) {
  final transfers = ref.watch(transfersStreamProvider).valueOrNull ?? [];
  return transfers
      .where((t) =>
          t.status == TransferStatus.transferring ||
          t.status == TransferStatus.pending)
      .length;
});

/// Controller handling network operations, server management, and LAN server lifecycle.
class NetworkTransferController extends StateNotifier<AsyncValue<void>> {
  final INetworkTransferRepository _repo;

  NetworkTransferController(this._repo) : super(const AsyncValue.data(null));

  Future<Result<LanTransferSession>> startLanServer({
    int port = 8080,
    String? pin,
  }) async {
    state = const AsyncValue.loading();
    final result = await _repo.startLanServer(port: port, preferredPin: pin);
    state = const AsyncValue.data(null);
    return result;
  }

  Future<void> stopLanServer() async {
    state = const AsyncValue.loading();
    await _repo.stopLanServer();
    state = const AsyncValue.data(null);
  }

  void setSharedFiles(List<String> paths) {
    _repo.setSharedFiles(paths);
  }

  Future<Result<NetworkServerConfig>> saveServer(
      NetworkServerConfig server) async {
    return _repo.saveServer(server);
  }

  Future<Result<void>> deleteServer(String id) async {
    return _repo.deleteServer(id);
  }

  Future<Result<bool>> testConnection(NetworkServerConfig server) async {
    return _repo.testConnection(server);
  }

  Future<Result<NetworkTransferTask>> enqueueTransfer({
    required String fileName,
    required TransferDirection direction,
    required String sourcePath,
    required String destinationPath,
    NetworkProtocol? protocol,
    String? cloudProvider,
    int totalBytes = 0,
  }) async {
    return _repo.enqueueTransfer(
      fileName: fileName,
      direction: direction,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      protocol: protocol,
      cloudProvider: cloudProvider,
      totalBytes: totalBytes,
    );
  }

  Future<void> cancelTransfer(String taskId) async {
    await _repo.cancelTransfer(taskId);
  }

  Future<void> pauseTransfer(String taskId) async {
    await _repo.pauseTransfer(taskId);
  }

  Future<void> resumeTransfer(String taskId) async {
    await _repo.resumeTransfer(taskId);
  }

  Future<void> clearCompletedTransfers() async {
    await _repo.clearCompletedTransfers();
  }
}

final networkTransferControllerProvider =
    StateNotifierProvider<NetworkTransferController, AsyncValue<void>>((ref) {
  final repo = ref.watch(networkTransferRepositoryProvider);
  return NetworkTransferController(repo);
});
