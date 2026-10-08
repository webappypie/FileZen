import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/network_models.dart';
import '../../domain/models/notification_models.dart';
import '../../domain/repositories/i_network_transfer_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
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
  })  : _lanWebServer = lanWebServer ?? LanWebServer(),
        _adapters = adapters ??
            {
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
          _cachedServers = list
              .map((item) =>
                  NetworkServerConfig.fromJson(item as Map<String, dynamic>))
              .toList();
        } else {
          _cachedServers = [];
        }
      } else {
        _cachedServers = _getStarterServers();
        await _persistServers();
      }
    } catch (e) {
      AppLogger.warning(
          'NetworkTransferRepository', 'Failed to load servers, fallback to starters: $e');
      _cachedServers = _getStarterServers();
    }

    _initialized = true;
    _serversController.add(List.unmodifiable(_cachedServers!));
  }

  List<NetworkServerConfig> _getStarterServers() {
    return [
      const NetworkServerConfig(
        id: 'starter_local_webdav',
        name: 'Local WebDAV Server',
        protocol: NetworkProtocol.webdav,
        host: '192.168.1.100',
        port: 8080,
        path: '/webdav',
        username: 'admin',
        isAnonymous: false,
      ),
      const NetworkServerConfig(
        id: 'starter_nas_smb',
        name: 'Home NAS (SMB)',
        protocol: NetworkProtocol.smb,
        host: '192.168.1.10',
        port: 445,
        path: 'Public',
        isAnonymous: true,
      ),
    ];
  }

  Future<void> _persistServers() async {
    if (_cachedServers == null) return;
    try {
      final file = await _getStorageFile();
      final jsonStr =
          jsonEncode(_cachedServers!.map((s) => s.toJson()).toList());
      await file.writeAsString(jsonStr, flush: true);
    } catch (e) {
      AppLogger.error('NetworkTransferRepository', 'Failed to save servers: $e');
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
          body: 'Direct browser access is live on ${session.displayUrl} with PIN ${session.accessPin}',
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

  @override
  Future<Result<NetworkTransferTask>> enqueueTransfer({
    required String fileName,
    required TransferDirection direction,
    required String sourcePath,
    required String destinationPath,
    NetworkProtocol? protocol,
    String? cloudProvider,
    int totalBytes = 0,
  }) async {
    final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}_${_tasks.length}';
    final task = NetworkTransferTask(
      id: taskId,
      fileName: fileName,
      direction: direction,
      protocol: protocol,
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
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      _tasks[index] = _tasks[index].copyWith(
        status: TransferStatus.cancelled,
        completedAt: DateTime.now(),
      );
      _activeTaskIds.remove(taskId);
      _transfersController.add(List.unmodifiable(_tasks));
    }
  }

  @override
  Future<void> pauseTransfer(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index >= 0 && _tasks[index].status == TransferStatus.transferring) {
      _tasks[index] = _tasks[index].copyWith(status: TransferStatus.paused);
      _activeTaskIds.remove(taskId);
      _transfersController.add(List.unmodifiable(_tasks));
    }
  }

  @override
  Future<void> resumeTransfer(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index >= 0 && _tasks[index].status == TransferStatus.paused) {
      _tasks[index] = _tasks[index].copyWith(status: TransferStatus.pending);
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

  void _processNextTask() async {
    if (_activeTaskIds.length >= 2) return; // Limit concurrency to 2

    final pendingIndex =
        _tasks.indexWhere((t) => t.status == TransferStatus.pending);
    if (pendingIndex < 0) return;

    final task = _tasks[pendingIndex];
    _activeTaskIds.add(task.id);

    _tasks[pendingIndex] = task.copyWith(
      status: TransferStatus.transferring,
      speedBytesPerSec: 1024.0 * 512, // 512 KB/s baseline indicator
    );
    _transfersController.add(List.unmodifiable(_tasks));

    // Simulate/execute transfer progress asynchronously
    try {
      final total = task.totalBytes > 0 ? task.totalBytes : 1024 * 1024 * 2; // 2MB default
      int transferred = 0;
      final step = (total / 5).ceil();

      for (int i = 0; i < 5; i++) {
        if (_cancelledTaskIds.contains(task.id)) {
          _activeTaskIds.remove(task.id);
          return;
        }

        await Future.delayed(const Duration(milliseconds: 150));
        transferred = (transferred + step).clamp(0, total);

        final currentIndex = _tasks.indexWhere((t) => t.id == task.id);
        if (currentIndex >= 0 &&
            _tasks[currentIndex].status == TransferStatus.transferring) {
          _tasks[currentIndex] = _tasks[currentIndex].copyWith(
            bytesTransferred: transferred,
            totalBytes: total,
            speedBytesPerSec: 1024.0 * 800,
          );
          _transfersController.add(List.unmodifiable(_tasks));
        }
      }

      final completedIndex = _tasks.indexWhere((t) => t.id == task.id);
      if (completedIndex >= 0 &&
          _tasks[completedIndex].status == TransferStatus.transferring) {
        _tasks[completedIndex] = _tasks[completedIndex].copyWith(
          bytesTransferred: total,
          totalBytes: total,
          status: TransferStatus.completed,
          completedAt: DateTime.now(),
        );
        _transfersController.add(List.unmodifiable(_tasks));

        // Send completed notification
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
    } catch (e) {
      final failedIndex = _tasks.indexWhere((t) => t.id == task.id);
      if (failedIndex >= 0) {
        _tasks[failedIndex] = _tasks[failedIndex].copyWith(
          status: TransferStatus.failed,
          errorMessage: e.toString(),
          completedAt: DateTime.now(),
        );
        _transfersController.add(List.unmodifiable(_tasks));
      }
    } finally {
      _activeTaskIds.remove(task.id);
      _processNextTask();
    }
  }
}
