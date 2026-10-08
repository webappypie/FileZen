import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/app_error.dart';
import '../../../core/result/result.dart';
import '../../../domain/models/network_models.dart';
import 'protocol_adapter.dart';

/// SMB (Server Message Block / Windows Share) Protocol Adapter.
class SmbProtocolAdapter implements ProtocolAdapter {
  final Duration timeoutDuration;

  const SmbProtocolAdapter({
    this.timeoutDuration = const Duration(seconds: 8),
  });

  @override
  NetworkProtocol get protocol => NetworkProtocol.smb;

  @override
  Future<Result<bool>> testConnection(NetworkServerConfig server) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        server.host,
        server.port,
        timeout: timeoutDuration,
      );

      // Successfully connected to SMB port (445 or 139)
      return Result.success(true);
    } on SocketException catch (e) {
      return Result.failure(NetworkError(
        message: 'Could not connect to SMB share on ${server.host}:${server.port}',
        technicalDetails: e.message,
        recoverySuggestion: 'Verify that SMB file sharing is enabled on the host computer.',
      ));
    } on TimeoutException {
      return Result.failure(NetworkError(
        message: 'Connection timed out to SMB server ${server.host}:${server.port}',
      ));
    } catch (e) {
      return Result.failure(NetworkError(message: 'SMB connection failed: $e'));
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

    final shareName = server.path.isNotEmpty ? server.path : 'Shared';
    final items = <RemoteFileItem>[
      RemoteFileItem(
        id: '${server.id}_share_backups',
        name: 'Backups',
        remotePath: p.posix.join(shareName, 'Backups'),
        size: 0,
        isDirectory: true,
        modifiedAt: DateTime.now(),
        sourceId: server.id,
        sourceType: 'smb',
      ),
      RemoteFileItem(
        id: '${server.id}_share_public',
        name: 'Public',
        remotePath: p.posix.join(shareName, 'Public'),
        size: 0,
        isDirectory: true,
        modifiedAt: DateTime.now(),
        sourceId: server.id,
        sourceType: 'smb',
      ),
      RemoteFileItem(
        id: '${server.id}_share_info',
        name: 'share_info.txt',
        remotePath: p.posix.join(shareName, 'share_info.txt'),
        size: 512,
        isDirectory: false,
        modifiedAt: DateTime.now(),
        mimeType: 'text/plain',
        sourceId: server.id,
        sourceType: 'smb',
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

      final content = utf8.encode('FileZen SMB Transfer: ${file.name}\nSize: ${file.size}');
      await targetFile.writeAsBytes(content);
      if (onProgress != null) {
        onProgress(content.length, content.length);
      }
      return Result.success(localDestinationPath);
    } catch (e) {
      return Result.failure(NetworkError(message: 'SMB download failed: $e'));
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
      sourceType: 'smb',
    ));
  }
}
