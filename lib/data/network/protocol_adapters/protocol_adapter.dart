import '../../../core/result/result.dart';
import '../../../domain/models/network_models.dart';

/// Base contract for network protocol adapters (WebDAV, FTP, SMB, SFTP).
abstract class ProtocolAdapter {
  NetworkProtocol get protocol;

  /// Probes network connectivity to the target host and port.
  Future<Result<bool>> testConnection(NetworkServerConfig server);

  /// Lists entries in the specified remote directory.
  Future<Result<List<RemoteFileItem>>> listDirectory(
    NetworkServerConfig server,
    String remotePath,
  );

  /// Downloads a remote file to a local destination path.
  Future<Result<String>> downloadFile(
    NetworkServerConfig server,
    RemoteFileItem file,
    String localDestinationPath, {
    void Function(int received, int total)? onProgress,
  });

  /// Uploads a local file to the target remote destination path.
  Future<Result<RemoteFileItem>> uploadFile(
    NetworkServerConfig server,
    String localFilePath,
    String remoteDestinationPath, {
    void Function(int sent, int total)? onProgress,
  });
}
