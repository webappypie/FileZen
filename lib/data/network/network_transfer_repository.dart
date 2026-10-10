import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/network_models.dart';
import '../../domain/models/notification_models.dart';
import '../../domain/repositories/i_network_transfer_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../vault/vault_crypto_backend.dart';
import 'lan_web_server.dart';
import 'protocol_adapters/ftp_adapter.dart';
import 'protocol_adapters/protocol_adapter.dart';
import 'protocol_adapters/sftp_adapter.dart';
import 'protocol_adapters/smb_adapter.dart';
import 'protocol_adapters/webdav_adapter.dart';

/// Concrete implementation of INetworkTransferRepository.
class NetworkTransferRepository implements INetworkTransferRepository {
  final String? customStoragePath;
  final INotificationRepository? notificationRepository;
  final LanWebServer _lanWebServer;

  /// Wraps saved server passwords with the hardware-backed Android Keystore key
  /// so they are never written to disk in the clear. Null only on non-Android
  /// hosts (desktop test runs), where there is no Keystore.
  final VaultCryptoBackend? _secretBackend;

  final Map<NetworkProtocol, ProtocolAdapter> _adapters;

  final StreamController<List<NetworkServerConfig>> _serversController =
      StreamController<List<NetworkServerConfig>>.broadcast();

  final StreamController<List<NetworkTransferTask>> _transfersController =
      StreamController<List<NetworkTransferTask>>.broadcast();

  List<NetworkServerConfig>? _cachedServers;
  final List<NetworkTransferTask> _tasks = [];
  final Set<String> _activeTaskIds = {};
  final Set<String> _cancelledTaskIds = {};
  bool _initialized = false;

  NetworkTransferRepository({
    this.customStoragePath,
    this.notificationRepository,
    LanWebServer? lanWebServer,
    Map<NetworkProtocol, ProtocolAdapter>? adapters,
    VaultCryptoBackend? secretBackend,
  })  : _lanWebServer = lanWebServer ?? LanWebServer(),
        _secretBackend = secretBackend ??
            (Platform.isAndroid ? const MethodChannelVaultCryptoBackend() : null),
        _adapters = adapters ??
            {
              // Only WebDAV has a real wire implementation; the rest fail honestly.
              NetworkProtocol.webdav: const WebDavProtocolAdapter(),
              NetworkProtocol.ftp: const FtpProtocolAdapter(),
              NetworkProtocol.smb: const SmbProtocolAdapter(),
              NetworkProtocol.sftp: const SftpProtocolAdapter(),
            };

  Future<File> _getStorageFile() async {
    if (customStoragePath != null) {
      final file = File(customStoragePath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(docsDir.path, '.filezen_network_servers.json'));
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    } catch (_) {
      final tempDir = Directory.systemTemp;
      return File(p.join(tempDir.path, '.filezen_network_servers.json'));
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized && _cachedServers != null) return;

    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final list = jsonDecode(content) as List<dynamic>;
          final loaded = <NetworkServerConfig>[];
          var hasPlaintextPassword = false;
          for (final item in list) {
            final json = item as Map<String, dynamic>;
            // Earlier builds seeded placeholder "starter" servers that pointed
            // at made-up LAN addresses; they were never user-configured.
            if ((json['id'] as String? ?? '').startsWith('starter_')) continue;
            if ((json['password'] as String? ?? '').isNotEmpty) hasPlaintextPassword = true;
            loaded.add(await _decodeServer(json));
          }
          _cachedServers = loaded;
          // Re-save so any legacy plaintext password is replaced by a wrapped one.
          if (hasPlaintextPassword && _secretBackend != null) {
            await _persistServers();
          }
        } else {
          _cachedServers = [];
        }
      } else {
        _cachedServers = [];
      }
    } catch (e) {
      AppLogger.warning(
          'NetworkTransferRepository', 'Failed to load servers: $e');
      _cachedServers = [];
    }

    _initialized = true;
    _serversController.add(List.unmodifiable(_cachedServers!));
  }

  Future<void> _persistServers() async {
    if (_cachedServers == null) return;
    try {
      final file = await _getStorageFile();
      final encoded = <Map<String, dynamic>>[];
      for (final server in _cachedServers!) {
        encoded.add(await _encodeServer(server));
      }
      await file.writeAsString(jsonEncode(encoded), flush: true);
    } catch (e) {
      AppLogger.error('NetworkTransferRepository', 'Failed to save servers: $e');
    }
  }

  Future<Map<String, dynamic>> _encodeServer(NetworkServerConfig server) async {
    final json = server.toJson();
    if (server.password.isEmpty || _secretBackend == null) return json;
    try {
      final wrapped = await _secretBackend.keystoreWrap(
        VaultKeySlot.device,
        Uint8List.fromList(utf8.encode(server.password)),
      );
      json['password'] = '';
      json['passwordEnc'] = base64Encode(wrapped);
    } catch (e) {
      // Never fall back to writing the password in the clear.
      AppLogger.error('NetworkTransferRepository',
          'Could not protect a saved server password; it will not be stored: ${e.runtimeType}');
      json['password'] = '';
    }
    return json;
  }

  Future<NetworkServerConfig> _decodeServer(Map<String, dynamic> json) async {
    final server = NetworkServerConfig.fromJson(json);
    final enc = json['passwordEnc'] as String?;
    if (enc == null || enc.isEmpty || _secretBackend == null) return server;
    try {
      final plain = await _secretBackend.keystoreUnwrap(
        VaultKeySlot.device,
        Uint8List.fromList(base64Decode(enc)),
      );
      return server.copyWith(password: utf8.decode(plain));
    } catch (e) {
      AppLogger.warning('NetworkTransferRepository',
          'Saved server password could not be unlocked; re-enter it: ${e.runtimeType}');
      return server;
    }
  }

  // ==================== Server Configurations ====================

  @override
  Future<List<NetworkServerConfig>> getServers() async {
    await _ensureInitialized();
    return List.unmodifiable(_cachedServers!);
  }

  @override
  Stream<List<NetworkServerConfig>> watchServers() {
    _ensureInitialized().then((_) {
      if (_cachedServers != null) {
        _serversController.add(List.unmodifiable(_cachedServers!));
      }
    });
    return _serversController.stream;
  }

  @override
  Future<Result<NetworkServerConfig>> saveServer(NetworkServerConfig server) async {
    await _ensureInitialized();
    final index = _cachedServers!.indexWhere((s) => s.id == server.id);
    if (index >= 0) {
      _cachedServers![index] = server;
    } else {
      _cachedServers!.add(server);
    }

    await _persistServers();
    _serversController.add(List.unmodifiable(_cachedServers!));
    AppLogger.info('NetworkTransferRepository', 'Saved server: ${server.name}');
    return Result.success(server);
  }

  @override
  Future<Result<void>> deleteServer(String id) async {
    await _ensureInitialized();
    _cachedServers!.removeWhere((s) => s.id == id);
    await _persistServers();
    _serversController.add(List.unmodifiable(_cachedServers!));
    AppLogger.info('NetworkTransferRepository', 'Deleted server ID: $id');
    return Result.success(null);
  }

  @override
  Future<Result<bool>> testConnection(NetworkServerConfig server) async {
    final adapter = _adapters[server.protocol];
    if (adapter == null) {
      return Result.failure(UnsupportedFormatError(
        extension: server.protocol.name,
        message: 'Unsupported network protocol: ${server.protocol.displayName}',
      ));
    }

    try {
      // Mark as connecting
      _updateServerStatus(server.id, ServerStatus.connecting, null);

      final result = await adapter.testConnection(server);
      if (result.isSuccess) {
        _updateServerStatus(
          server.id,
          ServerStatus.connected,
          null,
          lastConnectedAt: DateTime.now(),
        );
        return Result.success(true);
      } else {
        final errorMsg = result.errorOrNull?.message ?? 'Connection failed';
        _updateServerStatus(server.id, ServerStatus.error, errorMsg);
        return Result.failure(result.errorOrNull!);
      }
    } catch (e) {
      final error = NetworkError(message: 'Connection test failed: $e');
      _updateServerStatus(server.id, ServerStatus.error, error.message);
      return Result.failure(error);
    }
  }

  void _updateServerStatus(
    String serverId,
    ServerStatus status,
    String? error, {
    DateTime? lastConnectedAt,
  }) {
    if (_cachedServers == null) return;
    final index = _cachedServers!.indexWhere((s) => s.id == serverId);
    if (index >= 0) {
      _cachedServers![index] = _cachedServers![index].copyWith(
        status: status,
        lastError: error,
        lastConnectedAt: lastConnectedAt ?? _cachedServers![index].lastConnectedAt,
      );
      _persistServers();
      _serversController.add(List.unmodifiable(_cachedServers!));
    }
  }

  // ==================== Remote File Browsing ====================

  @override
  Future<Result<List<RemoteFileItem>>> listRemoteFiles(
    NetworkServerConfig server, {
    String path = '/',
  }) async {
    final adapter = _adapters[server.protocol];
    if (adapter == null) {
      return Result.failure(UnsupportedFormatError(
        extension: server.protocol.name,
        message: 'Unsupported network protocol: ${server.protocol.displayName}',
      ));
    }

    return adapter.listDirectory(server, path);
  }

  // ==================== LAN / Web Browser Server ====================

  @override
  Future<Result<LanTransferSession>> startLanServer({
    int port = 8080,
    String? preferredPin,
  }) async {
    try {
      final session = await _lanWebServer.start(
        port: port,
        preferredPin: preferredPin,
      );

      if (session.status == LanSessionStatus.active) {
        // Send notification
        await notificationRepository?.addNotification(AppNotification(
          id: 'lan_started_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Wi-Fi Web Share Active',
          body: 'Direct browser access is live on ${session.displayUrl}. Open Network & Cloud to see the access PIN.',
          type: NotificationType.transfer,
          priority: NotificationPriority.normal,
          timestamp: DateTime.now(),
          actionRoute: '/transfer',
        ));
        return Result.success(session);
      } else {
        return Result.failure(NetworkError(
          message: session.errorMessage ?? 'Failed to start LAN web share server',
        ));
      }
    } catch (e) {
      return Result.failure(NetworkError(message: 'Failed to start LAN server: $e'));
    }
  }

  @override
  Future<void> stopLanServer() async {
    await _lanWebServer.stop();
  }

  @override
  Stream<LanTransferSession> watchLanSession() => _lanWebServer.sessionStream;

  @override
  LanTransferSession getLanSession() => _lanWebServer.currentSession;

  @override
  void setSharedFiles(List<String> filePaths) {
    _lanWebServer.setSharedFiles(filePaths);
  }

  // ==================== Transfer Queue ====================

  final Set<String> _pausedTaskIds = {};

  @override
  Future<Result<NetworkTransferTask>> enqueueTransfer({
    required String fileName,
    required TransferDirection direction,
    required String sourcePath,
    required String destinationPath,
    NetworkProtocol? protocol,
    String? serverId,
    String? cloudProvider,
    int totalBytes = 0,
  }) async {
    final taskId = 'task_${DateTime.now().microsecondsSinceEpoch}_${_tasks.length}';
    final task = NetworkTransferTask(
      id: taskId,
      fileName: fileName,
      direction: direction,
      protocol: protocol,
      serverId: serverId,
      cloudProvider: cloudProvider,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      totalBytes: totalBytes,
      status: TransferStatus.pending,
      createdAt: DateTime.now(),
    );

    _tasks.add(task);
    _transfersController.add(List.unmodifiable(_tasks));

    // Kick off worker loop asynchronously
    _processNextTask();

    return Result.success(task);
  }

  @override
  Future<void> cancelTransfer(String taskId) async {
    _cancelledTaskIds.add(taskId);
    _pausedTaskIds.remove(taskId);
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      _tasks[index] = _tasks[index].copyWith(
        status: TransferStatus.cancelled,
        completedAt: DateTime.now(),
      );
      _transfersController.add(List.unmodifiable(_tasks));
    }
  }

  /// Pausing stops the in-flight request and discards the partial data;
  /// [resumeTransfer] restarts the transfer from the beginning (the adapters do
  /// not support ranged resume).
  @override
  Future<void> pauseTransfer(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index < 0) return;
    final status = _tasks[index].status;
    if (status == TransferStatus.transferring) {
      _pausedTaskIds.add(taskId);
    } else if (status == TransferStatus.pending) {
      _tasks[index] = _tasks[index].copyWith(status: TransferStatus.paused);
      _transfersController.add(List.unmodifiable(_tasks));
    }
  }

  @override
  Future<void> resumeTransfer(String taskId) async {
    _pausedTaskIds.remove(taskId);
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index >= 0 && _tasks[index].status == TransferStatus.paused) {
      _tasks[index] = _tasks[index].copyWith(
        status: TransferStatus.pending,
        bytesTransferred: 0,
      );
      _transfersController.add(List.unmodifiable(_tasks));
      _processNextTask();
    }
  }

  @override
  Future<void> clearCompletedTransfers() async {
    _tasks.removeWhere((t) =>
        t.status == TransferStatus.completed ||
        t.status == TransferStatus.cancelled ||
        t.status == TransferStatus.failed);
    _transfersController.add(List.unmodifiable(_tasks));
  }

  @override
  Stream<List<NetworkTransferTask>> watchTransfers() =>
      _transfersController.stream;

  @override
  List<NetworkTransferTask> getTransfers() => List.unmodifiable(_tasks);

  void _updateTask(String id, NetworkTransferTask Function(NetworkTransferTask) change) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;
    _tasks[index] = change(_tasks[index]);
    _transfersController.add(List.unmodifiable(_tasks));
  }

  void _failTask(String id, String message) {
    _updateTask(
      id,
      (t) => t.status == TransferStatus.cancelled
          ? t
          : t.copyWith(
              status: TransferStatus.failed,
              errorMessage: message,
              completedAt: DateTime.now(),
            ),
    );
  }

  void _processNextTask() {
    if (_activeTaskIds.length >= 2) return; // Limit concurrency to 2

    final pendingIndex =
        _tasks.indexWhere((t) => t.status == TransferStatus.pending);
    if (pendingIndex < 0) return;

    final task = _tasks[pendingIndex];
    _activeTaskIds.add(task.id);
    _updateTask(task.id, (t) => t.copyWith(status: TransferStatus.transferring));

    _runTask(task).catchError((Object e) {
      _failTask(task.id, 'Transfer failed: $e');
    }).whenComplete(() {
      _activeTaskIds.remove(task.id);
      _processNextTask();
    });
  }

  /// Executes a queued transfer through the real protocol adapter. Nothing is
  /// simulated: a task completes only when the adapter reports success.
  Future<void> _runTask(NetworkTransferTask task) async {
    await _ensureInitialized();

    if (task.cloudProvider != null) {
      _failTask(task.id, 'Cloud transfers are not available in this version.');
      return;
    }

    final server = _cachedServers!.where((s) => s.id == task.serverId).firstOrNull;
    if (server == null) {
      _failTask(task.id, 'The server for this transfer is no longer configured.');
      return;
    }
    final adapter = _adapters[server.protocol];
    if (adapter == null) {
      _failTask(task.id, 'Unsupported network protocol: ${server.protocol.displayName}');
      return;
    }

    bool stopRequested() =>
        _cancelledTaskIds.contains(task.id) || _pausedTaskIds.contains(task.id);

    final watch = Stopwatch()..start();
    var lastEmitMs = -1000;
    void onProgress(int done, int total) {
      if (stopRequested()) return;
      final ms = watch.elapsedMilliseconds;
      if (ms - lastEmitMs < 100 && (total <= 0 || done < total)) return;
      lastEmitMs = ms;
      _updateTask(
        task.id,
        (t) => t.copyWith(
          bytesTransferred: done,
          totalBytes: total > 0 ? total : t.totalBytes,
          speedBytesPerSec: ms > 0 ? done * 1000 / ms : 0.0,
        ),
      );
    }

    Result<Object?> result;
    var finalSize = task.totalBytes;

    if (task.direction == TransferDirection.download) {
      // Never overwrite an existing local file.
      final destination = await _uniqueLocalPath(task.destinationPath);
      if (destination != task.destinationPath) {
        _updateTask(task.id, (t) => t.copyWith(destinationPath: destination));
      }
      result = await adapter.downloadFile(
        server,
        RemoteFileItem(
          id: task.sourcePath,
          name: task.fileName,
          remotePath: task.sourcePath,
          size: task.totalBytes,
          isDirectory: false,
          modifiedAt: DateTime.now(),
          sourceId: server.id,
          sourceType: server.protocol.name,
        ),
        destination,
        onProgress: onProgress,
        isCancelled: stopRequested,
      );
      if (result.isSuccess) {
        try {
          finalSize = await File(destination).length();
        } catch (_) {}
      }
    } else {
      try {
        finalSize = await File(task.sourcePath).length();
      } catch (_) {}
      result = await adapter.uploadFile(
        server,
        task.sourcePath,
        task.destinationPath,
        onProgress: onProgress,
        isCancelled: stopRequested,
      );
    }

    if (_cancelledTaskIds.contains(task.id)) return; // already marked cancelled

    if (_pausedTaskIds.contains(task.id)) {
      _updateTask(
        task.id,
        (t) => t.copyWith(
          status: TransferStatus.paused,
          bytesTransferred: 0,
          speedBytesPerSec: 0.0,
        ),
      );
      return;
    }

    if (result.isFailure) {
      _failTask(task.id, result.errorOrNull?.message ?? 'Transfer failed');
      return;
    }

    _updateTask(
      task.id,
      (t) => t.copyWith(
        bytesTransferred: finalSize,
        totalBytes: finalSize,
        speedBytesPerSec: 0.0,
        status: TransferStatus.completed,
        completedAt: DateTime.now(),
      ),
    );

    await notificationRepository?.addNotification(AppNotification(
      id: 'transfer_completed_${task.id}',
      title: 'Transfer Completed',
      body: '${task.fileName} transferred successfully (${task.direction.name}).',
      type: NotificationType.transfer,
      priority: NotificationPriority.low,
      timestamp: DateTime.now(),
      actionRoute: '/transfer',
    ));
  }

  Future<String> _uniqueLocalPath(String path) async {
    if (!await File(path).exists()) return path;
    final dir = p.dirname(path);
    final base = p.basenameWithoutExtension(path);
    final ext = p.extension(path);
    for (var i = 1; i < 1000; i++) {
      final candidate = p.join(dir, '$base ($i)$ext');
      if (!await File(candidate).exists()) return candidate;
    }
    return p.join(dir, '${base}_${DateTime.now().millisecondsSinceEpoch}$ext');
  }
}
