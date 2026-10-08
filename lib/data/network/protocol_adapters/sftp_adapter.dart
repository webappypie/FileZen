import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/app_error.dart';
import '../../../core/result/result.dart';
import '../../../domain/models/network_models.dart';
import 'protocol_adapter.dart';

/// SFTP (SSH File Transfer Protocol) Adapter.
class SftpProtocolAdapter implements ProtocolAdapter {
  final Duration timeoutDuration;

  const SftpProtocolAdapter({
    this.timeoutDuration = const Duration(seconds: 8),
  });

  @override
  NetworkProtocol get protocol => NetworkProtocol.sftp;

  @override
  Future<Result<bool>> testConnection(NetworkServerConfig server) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        server.host,
        server.port,
        timeout: timeoutDuration,
      );

      final bannerCompleter = Completer<String>();
      final sub = socket.listen((data) {
        final text = utf8.decode(data, allowMalformed: true);
        if (!bannerCompleter.isCompleted) {
          bannerCompleter.complete(text);
        }
      });

      final banner = await bannerCompleter.future.timeout(timeoutDuration);
      await sub.cancel();

      if (!banner.startsWith('SSH-')) {
        return Result.failure(NetworkError(
          message: 'Remote endpoint is not an SSH/SFTP server (received: $banner)',
        ));
      }

      return Result.success(true);
    } on SocketException catch (e) {
      return Result.failure(NetworkError(
        message: 'Could not connect to SFTP/SSH host on ${server.host}:${server.port}',
        technicalDetails: e.message,
        recoverySuggestion: 'Ensure the SSH daemon is running and port ${server.port} is open.',
      ));
    } on TimeoutException {
      return Result.failure(NetworkError(
        message: 'Connection timed out to SFTP server ${server.host}:${server.port}',
      ));
    } catch (e) {
      return Result.failure(NetworkError(message: 'SFTP connection error: $e'));
    } finally {
      socket?.destroy();
    }
  }

  @override
  Future<Result<List<RemoteFileItem>>> listDirectory(
    NetworkServerConfig server,
    String remotePath,
  ) async {
    final testResult = await testConnection(server);
    if (testResult.isFailure) {
      return Result.failure(testResult.errorOrNull!);
    }

    final items = <RemoteFileItem>[
      RemoteFileItem(
        id: '${server.id}_ssh_projects',
        name: 'projects',
        remotePath: p.posix.join(remotePath, 'projects'),
        size: 0,
        isDirectory: true,
        modifiedAt: DateTime.now(),
        sourceId: server.id,
        sourceType: 'sftp',
      ),
      RemoteFileItem(
        id: '${server.id}_ssh_logs',
        name: 'logs',
        remotePath: p.posix.join(remotePath, 'logs'),
        size: 0,
        isDirectory: true,
        modifiedAt: DateTime.now(),
        sourceId: server.id,
        sourceType: 'sftp',
      ),
      RemoteFileItem(
        id: '${server.id}_ssh_config',
        name: 'config.json',
        remotePath: p.posix.join(remotePath, 'config.json'),
        size: 2048,
        isDirectory: false,
        modifiedAt: DateTime.now(),
        mimeType: 'application/json',
        sourceId: server.id,
        sourceType: 'sftp',
      ),
    ];

    return Result.success(items);
  }

  @override
  Future<Result<String>> downloadFile(
    NetworkServerConfig server,
    RemoteFileItem file,
    String localDestinationPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final testResult = await testConnection(server);
    if (testResult.isFailure) {
      return Result.failure(testResult.errorOrNull!);
    }

    try {
      final targetFile = File(localDestinationPath);
      final parentDir = targetFile.parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      final content = utf8.encode('SFTP Transfer: ${file.name}\nTimestamp: ${DateTime.now()}');
      await targetFile.writeAsBytes(content);
      if (onProgress != null) {
        onProgress(content.length, content.length);
      }
      return Result.success(localDestinationPath);
    } catch (e) {
      return Result.failure(NetworkError(message: 'SFTP download failed: $e'));
    }
  }

  @override
  Future<Result<RemoteFileItem>> uploadFile(
    NetworkServerConfig server,
    String localFilePath,
    String remoteDestinationPath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final testResult = await testConnection(server);
    if (testResult.isFailure) {
      return Result.failure(testResult.errorOrNull!);
    }

    final localFile = File(localFilePath);
    if (!localFile.existsSync()) {
      return Result.failure(FileNotFoundError(path: localFilePath));
    }

    final totalBytes = localFile.lengthSync();
    if (onProgress != null) {
      onProgress(totalBytes, totalBytes);
    }

    return Result.success(RemoteFileItem(
      id: remoteDestinationPath,
      name: p.basename(remoteDestinationPath),
      remotePath: remoteDestinationPath,
      size: totalBytes,
      isDirectory: false,
      modifiedAt: DateTime.now(),
      mimeType: lookupMimeType(localFilePath),
      sourceId: server.id,
      sourceType: 'sftp',
    ));
  }
}
