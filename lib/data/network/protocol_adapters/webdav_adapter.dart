import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/app_error.dart';
import '../../../core/result/result.dart';
import '../../../domain/models/network_models.dart';
import 'protocol_adapter.dart';

/// WebDAV Protocol Adapter using standard HTTP/WebDAV methods (PROPFIND, GET, PUT).
class WebDavProtocolAdapter implements ProtocolAdapter {
  final Duration timeoutDuration;

  const WebDavProtocolAdapter({
    this.timeoutDuration = const Duration(seconds: 8),
  });

  @override
  NetworkProtocol get protocol => NetworkProtocol.webdav;

  @override
  Future<Result<bool>> testConnection(NetworkServerConfig server) async {
    final client = HttpClient()..connectionTimeout = timeoutDuration;
    try {
      final scheme = server.port == 443 ? 'https' : 'http';
      final uri = Uri(
        scheme: scheme,
        host: server.host,
        port: server.port,
        path: server.path.isEmpty ? '/' : server.path,
      );

      final request = await client.openUrl('PROPFIND', uri).timeout(timeoutDuration);
      _applyAuth(request, server);
      request.headers.set('Depth', '0');

      final response = await request.close().timeout(timeoutDuration);
      final statusCode = response.statusCode;

      if (statusCode >= 200 && statusCode < 400) {
        return Result.success(true);
      } else if (statusCode == 401 || statusCode == 403) {
        return Result.failure(NetworkError(
          message: 'Authentication failed for ${server.name}',
          recoverySuggestion: 'Check your username and password.',
        ));
      } else {
        return Result.failure(NetworkError(
          message: 'WebDAV server responded with status $statusCode',
          recoverySuggestion: 'Verify server URL and path configuration.',
        ));
      }
    } on SocketException catch (e) {
      return Result.failure(NetworkError(
        message: 'Could not connect to ${server.host}:${server.port}',
        technicalDetails: e.message,
        recoverySuggestion: 'Check if the WebDAV server is running and accessible on your network.',
      ));
    } on TimeoutException {
      return Result.failure(NetworkError(
        message: 'Connection timed out to ${server.host}:${server.port}',
        recoverySuggestion: 'Ensure host and port are correct and reachable.',
      ));
    } catch (e) {
      return Result.failure(NetworkError(
        message: 'Failed to connect to WebDAV server: $e',
      ));
    } finally {
      client.close();
    }
  }

  @override
  Future<Result<List<RemoteFileItem>>> listDirectory(
    NetworkServerConfig server,
    String remotePath,
  ) async {
    final client = HttpClient()..connectionTimeout = timeoutDuration;
    try {
      final scheme = server.port == 443 ? 'https' : 'http';
      final cleanBase = server.path.endsWith('/') ? server.path : '${server.path}/';
      final subPath = remotePath.startsWith('/') ? remotePath.substring(1) : remotePath;
      final fullPath = p.posix.normalize('$cleanBase$subPath');

      final uri = Uri(
        scheme: scheme,
        host: server.host,
        port: server.port,
        path: fullPath,
      );

      final request = await client.openUrl('PROPFIND', uri).timeout(timeoutDuration);
      _applyAuth(request, server);
      request.headers.set('Depth', '1');

      final response = await request.close().timeout(timeoutDuration);
      if (response.statusCode != 207 && response.statusCode != 200) {
        return Result.failure(NetworkError(
          message: 'WebDAV directory listing returned status ${response.statusCode}',
        ));
      }

      final body = await utf8.decodeStream(response);
      final items = _parseWebDavXml(body, server, fullPath);
      return Result.success(items);
    } on SocketException catch (e) {
      return Result.failure(NetworkError(
        message: 'Network unreachable when listing directory',
        technicalDetails: e.message,
      ));
    } on TimeoutException {
      return Result.failure(const NetworkError(
        message: 'WebDAV directory listing timed out',
      ));
    } catch (e) {
      return Result.failure(NetworkError(
        message: 'Failed to list WebDAV directory: $e',
      ));
    } finally {
      client.close();
    }
  }

  @override
  Future<Result<String>> downloadFile(
    NetworkServerConfig server,
    RemoteFileItem file,
    String localDestinationPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = timeoutDuration;
    try {
      final scheme = server.port == 443 ? 'https' : 'http';
      final uri = Uri(
        scheme: scheme,
        host: server.host,
        port: server.port,
        path: file.remotePath,
      );

      final request = await client.getUrl(uri).timeout(timeoutDuration);
      _applyAuth(request, server);

      final response = await request.close().timeout(timeoutDuration);
      if (response.statusCode != 200) {
        return Result.failure(NetworkError(
          message: 'Download failed with status ${response.statusCode}',
        ));
      }

      final totalBytes = response.contentLength > 0 ? response.contentLength : file.size;
      int receivedBytes = 0;

      final targetFile = File(localDestinationPath);
      final parentDir = targetFile.parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      final sink = targetFile.openWrite();
      await response.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (onProgress != null) {
          onProgress(receivedBytes, totalBytes);
        }
      }).asFuture();

      await sink.flush();
      await sink.close();

      return Result.success(localDestinationPath);
    } catch (e) {
      return Result.failure(NetworkError(
        message: 'Failed to download WebDAV file: $e',
      ));
    } finally {
      client.close();
    }
  }

  @override
  Future<Result<RemoteFileItem>> uploadFile(
    NetworkServerConfig server,
    String localFilePath,
    String remoteDestinationPath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = timeoutDuration;
    try {
      final localFile = File(localFilePath);
      if (!localFile.existsSync()) {
        return Result.failure(FileNotFoundError(path: localFilePath));
      }

      final scheme = server.port == 443 ? 'https' : 'http';
      final uri = Uri(
        scheme: scheme,
        host: server.host,
        port: server.port,
        path: remoteDestinationPath,
      );

      final request = await client.putUrl(uri).timeout(timeoutDuration);
      _applyAuth(request, server);

      final totalBytes = localFile.lengthSync();
      request.headers.contentLength = totalBytes;
      final mime = lookupMimeType(localFilePath) ?? 'application/octet-stream';
      request.headers.contentType = ContentType.parse(mime);

      int sentBytes = 0;
      final stream = localFile.openRead();
      await request.addStream(stream.map((chunk) {
        sentBytes += chunk.length;
        if (onProgress != null) {
          onProgress(sentBytes, totalBytes);
        }
        return chunk;
      }));

      final response = await request.close().timeout(timeoutDuration);
      if (response.statusCode != 200 &&
          response.statusCode != 201 &&
          response.statusCode != 204) {
        return Result.failure(NetworkError(
          message: 'Upload failed with status ${response.statusCode}',
        ));
      }

      final uploadedItem = RemoteFileItem(
        id: remoteDestinationPath,
        name: p.basename(remoteDestinationPath),
        remotePath: remoteDestinationPath,
        size: totalBytes,
        isDirectory: false,
        modifiedAt: DateTime.now(),
        mimeType: mime,
        sourceId: server.id,
        sourceType: 'webdav',
      );

      return Result.success(uploadedItem);
    } catch (e) {
      return Result.failure(NetworkError(
        message: 'Failed to upload file to WebDAV: $e',
      ));
    } finally {
      client.close();
    }
  }

  void _applyAuth(HttpClientRequest request, NetworkServerConfig server) {
    if (!server.isAnonymous && server.username.isNotEmpty) {
      final credentials = '${server.username}:${server.password}';
      final encoded = base64.encode(utf8.encode(credentials));
      request.headers.set('Authorization', 'Basic $encoded');
    }
  }

  List<RemoteFileItem> _parseWebDavXml(
    String xml,
    NetworkServerConfig server,
    String parentPath,
  ) {
    final items = <RemoteFileItem>[];
    final responseRegex = RegExp(r'<(?:\w+:)?response[^>]*>([\s\S]*?)<\/(?:\w+:)?response>');
    final hrefRegex = RegExp(r'<(?:\w+:)?href[^>]*>([^<]+)<\/(?:\w+:)?href>');
    final getcontentlengthRegex = RegExp(r'<(?:\w+:)?getcontentlength[^>]*>([^<]+)<\/(?:\w+:)?getcontentlength>');
    final isCollectionRegex = RegExp(r'<(?:\w+:)?collection\s*\/>|<(?:\w+:)?resourcetype[^>]*>\s*<(?:\w+:)?collection');
    final getlastmodifiedRegex = RegExp(r'<(?:\w+:)?getlastmodified[^>]*>([^<]+)<\/(?:\w+:)?getlastmodified>');

    final matches = responseRegex.allMatches(xml);
    for (final match in matches) {
      final content = match.group(1) ?? '';
      final hrefMatch = hrefRegex.firstMatch(content);
      if (hrefMatch == null) continue;

      final rawHref = hrefMatch.group(1)?.trim() ?? '';
      final decodedPath = Uri.decodeComponent(rawHref);

      // Skip root/self directory match
      final normalizedParent = p.posix.normalize(parentPath);
      final normalizedPath = p.posix.normalize(decodedPath);
      if (normalizedPath == normalizedParent || normalizedPath == '$normalizedParent/') {
        continue;
      }

      final isDir = isCollectionRegex.hasMatch(content);
      final sizeStr = getcontentlengthRegex.firstMatch(content)?.group(1);
      final size = sizeStr != null ? int.tryParse(sizeStr) ?? 0 : 0;
      final modStr = getlastmodifiedRegex.firstMatch(content)?.group(1);
      final modDate = modStr != null ? (DateTime.tryParse(modStr) ?? DateTime.now()) : DateTime.now();

      final name = p.posix.basename(normalizedPath);
      if (name.isEmpty) continue;

      items.add(RemoteFileItem(
        id: normalizedPath,
        name: name,
        remotePath: normalizedPath,
        size: size,
        isDirectory: isDir,
        modifiedAt: modDate,
        mimeType: isDir ? null : lookupMimeType(name),
        sourceId: server.id,
        sourceType: 'webdav',
      ));
    }

    return items;
  }
}
