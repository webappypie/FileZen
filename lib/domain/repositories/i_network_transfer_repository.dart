import '../../core/result/result.dart';
import '../models/network_models.dart';

/// Contract for network server connection management, LAN browser file sharing,
/// and remote transfer queue processing.
abstract class INetworkTransferRepository {
  /// Retrieves all configured network servers (SMB, FTP, SFTP, WebDAV).
  Future<List<NetworkServerConfig>> getServers();

  /// Reactive stream broadcasting changes to configured servers.
  Stream<List<NetworkServerConfig>> watchServers();

  /// Saves or updates a network server configuration.
  Future<Result<NetworkServerConfig>> saveServer(NetworkServerConfig server);

  /// Removes a network server configuration.
  Future<Result<void>> deleteServer(String id);

  /// Probes connectivity to the remote server without establishing a permanent session.
  Future<Result<bool>> testConnection(NetworkServerConfig server);

  /// Lists items within a remote directory on the given server.
  Future<Result<List<RemoteFileItem>>> listRemoteFiles(
    NetworkServerConfig server, {
    String path = '/',
  });

  /// Starts the embedded local Wi-Fi / LAN web sharing server.
  Future<Result<LanTransferSession>> startLanServer({
    int port = 8080,
    String? preferredPin,
  });

  /// Stops the running Wi-Fi / LAN web server.
  Future<void> stopLanServer();

  /// Reactive stream broadcasting updates to the LAN transfer session.
  Stream<LanTransferSession> watchLanSession();

  /// Gets the current state of the LAN transfer session.
  LanTransferSession getLanSession();

  /// Updates the list of local file paths exposed via the LAN web share.
  void setSharedFiles(List<String> filePaths);

  /// Adds a transfer task to the transfer queue.
  Future<Result<NetworkTransferTask>> enqueueTransfer({
    required String fileName,
    required TransferDirection direction,
    required String sourcePath,
    required String destinationPath,
    NetworkProtocol? protocol,
    String? serverId,
    String? cloudProvider,
    int totalBytes = 0,
  });

  /// Cancels an active or queued transfer task.
  Future<void> cancelTransfer(String taskId);

  /// Pauses an active transfer.
  Future<void> pauseTransfer(String taskId);

  /// Resumes a paused transfer.
  Future<void> resumeTransfer(String taskId);

  /// Removes all completed or cancelled transfers from the queue history.
  Future<void> clearCompletedTransfers();

  /// Reactive stream broadcasting the list of queued and active transfers.
  Stream<List<NetworkTransferTask>> watchTransfers();

  /// Gets current transfer tasks.
  List<NetworkTransferTask> getTransfers();
}
