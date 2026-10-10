import '../../../core/error/app_error.dart';
import '../../../core/result/result.dart';
import '../../../domain/models/network_models.dart';

/// Base contract for network protocol adapters.
///
/// Only protocols with a real wire implementation may be registered as working
/// adapters (currently WebDAV). The others use [UnsupportedProtocolAdapter] so
/// the app never reports success for a transfer or listing it did not perform.
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
  ///
  /// [isCancelled] is polled while streaming; when it returns true the
  /// transfer stops, partial data is removed and an [OperationCancelledError]
  /// failure is returned.
  Future<Result<String>> downloadFile(
    NetworkServerConfig server,
    RemoteFileItem file,
    String localDestinationPath, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  });

  /// Uploads a local file to the target remote destination path.
  Future<Result<RemoteFileItem>> uploadFile(
    NetworkServerConfig server,
    String localFilePath,
    String remoteDestinationPath, {
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
  });
}

/// Adapter for protocols FileZen does not implement yet. Every operation fails
/// with a clear message; nothing is faked.
class UnsupportedProtocolAdapter implements ProtocolAdapter {
  @override
  final NetworkProtocol protocol;

  const UnsupportedProtocolAdapter(this.protocol);

  NetworkError get _error => NetworkError(
        message: '${protocol.displayName} is not supported yet.',
        recoverySuggestion: 'Use a WebDAV server or the Wi-Fi browser transfer instead.',
      );

  @override
  Future<Result<bool>> testConnection(NetworkServerConfig server) async =>
      Result.failure(_error);

  @override
  Future<Result<List<RemoteFileItem>>> listDirectory(
    NetworkServerConfig server,
    String remotePath,
  ) async =>
      Result.failure(_error);

  @override
  Future<Result<String>> downloadFile(
    NetworkServerConfig server,
    RemoteFileItem file,
    String localDestinationPath, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async =>
      Result.failure(_error);

  @override
  Future<Result<RemoteFileItem>> uploadFile(
    NetworkServerConfig server,
    String localFilePath,
    String remoteDestinationPath, {
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
  }) async =>
      Result.failure(_error);
}
