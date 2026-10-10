import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filezen/app/theme/app_theme.dart';
import 'package:filezen/core/result/result.dart';
import 'package:filezen/domain/models/network_models.dart';
import 'package:filezen/domain/repositories/i_network_transfer_repository.dart';
import 'package:filezen/features/transfer/presentation/providers/network_providers.dart';
import 'package:filezen/features/transfer/presentation/screens/network_hub_screen.dart';

class _FakeNetworkTransferRepository implements INetworkTransferRepository {
  final List<NetworkServerConfig> _servers;
  final List<NetworkTransferTask> _transfers;
  LanTransferSession _session;

  final StreamController<List<NetworkServerConfig>> _serversController =
      StreamController<List<NetworkServerConfig>>.broadcast();
  final StreamController<List<NetworkTransferTask>> _transfersController =
      StreamController<List<NetworkTransferTask>>.broadcast();
  final StreamController<LanTransferSession> _sessionController =
      StreamController<LanTransferSession>.broadcast();

  _FakeNetworkTransferRepository({
    List<NetworkServerConfig>? servers,
    List<NetworkTransferTask>? transfers,
    LanTransferSession? session,
  })  : _servers = servers ??
            [
              const NetworkServerConfig(
                id: 'srv_1',
                name: 'Office NAS',
                protocol: NetworkProtocol.smb,
                host: '192.168.1.10',
                port: 445,
                status: ServerStatus.connected,
              ),
              const NetworkServerConfig(
                id: 'srv_2',
                name: 'WebDAV Cloud',
                protocol: NetworkProtocol.webdav,
                host: '192.168.1.50',
                port: 8080,
                status: ServerStatus.disconnected,
              ),
            ],
        _transfers = transfers ??
            [
              NetworkTransferTask(
                id: 'task_1',
                fileName: 'presentation.pdf',
                direction: TransferDirection.download,
                sourcePath: '/remote/presentation.pdf',
                destinationPath: '/local/presentation.pdf',
                bytesTransferred: 500,
                totalBytes: 1000,
                status: TransferStatus.transferring,
                speedBytesPerSec: 512000,
                createdAt: DateTime.now(),
              ),
            ],
        _session = session ?? const LanTransferSession();

  @override
  Future<List<NetworkServerConfig>> getServers() async => List.unmodifiable(_servers);

  @override
  Stream<List<NetworkServerConfig>> watchServers() async* {
    yield List.unmodifiable(_servers);
    yield* _serversController.stream;
  }

  @override
  Future<Result<NetworkServerConfig>> saveServer(NetworkServerConfig server) async {
    _servers.add(server);
    _serversController.add(List.unmodifiable(_servers));
    return Result.success(server);
  }

  @override
  Future<Result<void>> deleteServer(String id) async {
    _servers.removeWhere((s) => s.id == id);
    _serversController.add(List.unmodifiable(_servers));
    return Result.success(null);
  }

  @override
  Future<Result<bool>> testConnection(NetworkServerConfig server) async {
    return Result.success(true);
  }

  @override
  Future<Result<List<RemoteFileItem>>> listRemoteFiles(
    NetworkServerConfig server, {
    String path = '/',
  }) async {
    return Result.success([
      RemoteFileItem(
        id: 'rem_1',
        name: 'SharedDocs',
        remotePath: '/SharedDocs',
        size: 0,
        isDirectory: true,
        modifiedAt: DateTime.now(),
        sourceId: server.id,
        sourceType: server.protocol.name,
      ),
      RemoteFileItem(
        id: 'rem_2',
        name: 'document.txt',
        remotePath: '/document.txt',
        size: 2048,
        isDirectory: false,
        modifiedAt: DateTime.now(),
        sourceId: server.id,
        sourceType: server.protocol.name,
      ),
    ]);
  }

  @override
  Future<Result<LanTransferSession>> startLanServer({
    int port = 8080,
    String? preferredPin,
  }) async {
    _session = LanTransferSession(
      status: LanSessionStatus.active,
      port: port,
      ipAddresses: ['192.168.1.42'],
      accessPin: preferredPin ?? '9999',
      connectedClientsCount: 1,
      preferredUrl: 'http://192.168.1.42:$port',
    );
    _sessionController.add(_session);
    return Result.success(_session);
  }

  @override
  Future<void> stopLanServer() async {
    _session = const LanTransferSession(status: LanSessionStatus.stopped);
    _sessionController.add(_session);
  }

  @override
  Stream<LanTransferSession> watchLanSession() async* {
    yield _session;
    yield* _sessionController.stream;
  }

  @override
  LanTransferSession getLanSession() => _session;

  @override
  void setSharedFiles(List<String> filePaths) {}

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
    final task = NetworkTransferTask(
      id: 'task_${_transfers.length + 1}',
      fileName: fileName,
      direction: direction,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      totalBytes: totalBytes,
      status: TransferStatus.pending,
      createdAt: DateTime.now(),
    );
    _transfers.add(task);
    _transfersController.add(List.unmodifiable(_transfers));
    return Result.success(task);
  }

  @override
  Future<void> cancelTransfer(String taskId) async {
    final index = _transfers.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      _transfers[index] = _transfers[index].copyWith(status: TransferStatus.cancelled);
      _transfersController.add(List.unmodifiable(_transfers));
    }
  }

  @override
  Future<void> pauseTransfer(String taskId) async {}

  @override
  Future<void> resumeTransfer(String taskId) async {}

  @override
  Future<void> clearCompletedTransfers() async {
    _transfers.clear();
    _transfersController.add(List.unmodifiable(_transfers));
  }

  @override
  Stream<List<NetworkTransferTask>> watchTransfers() async* {
    yield List.unmodifiable(_transfers);
    yield* _transfersController.stream;
  }

  @override
  List<NetworkTransferTask> getTransfers() => List.unmodifiable(_transfers);
}

void main() {
  Widget createTestWidget({
    _FakeNetworkTransferRepository? repo,
    int initialTabIndex = 0,
  }) {
    final fakeRepo = repo ?? _FakeNetworkTransferRepository();
    return ProviderScope(
      overrides: [
        networkTransferRepositoryProvider.overrideWithValue(fakeRepo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: NetworkHubScreen(initialTabIndex: initialTabIndex),
      ),
    );
  }

  testWidgets('NetworkHubScreen renders 3 tabs and headers', (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Network & Transfer'), findsOneWidget);
    expect(find.text('Wi-Fi Share'), findsOneWidget);
    expect(find.text('Network Storage'), findsOneWidget);
    expect(find.text('Transfers'), findsOneWidget);

    // Initial tab is Wi-Fi Share
    expect(find.text('Wi-Fi Web Share'), findsOneWidget);
    expect(find.text('Start Web Share'), findsOneWidget);
  });

  testWidgets('Tapping Start Web Share starts session and displays URL & PIN', (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    final startButton = find.text('Start Web Share');
    expect(startButton, findsOneWidget);

    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.text('Web Share is Live'), findsOneWidget);
    expect(find.text('Stop Web Share'), findsOneWidget);
    expect(find.text('http://192.168.1.42:8080'), findsOneWidget);
    expect(find.text('Security PIN'), findsOneWidget);
    expect(find.text('9999'), findsOneWidget);
  });

  testWidgets('Network Storage tab renders servers list and Add Storage action', (tester) async {
    await tester.pumpWidget(createTestWidget(initialTabIndex: 1));
    await tester.pumpAndSettle();

    expect(find.text('Office NAS'), findsOneWidget);
    expect(find.text('WebDAV Cloud'), findsOneWidget);
    expect(find.text('Add Storage'), findsOneWidget);

    // Tap Add Storage to open dialog
    await tester.tap(find.text('Add Storage'));
    await tester.pumpAndSettle();

    expect(find.text('Add Network Storage'), findsOneWidget);
    expect(find.text('Host / IP Address *'), findsOneWidget);

    // Scroll dialog content to reveal Save button
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Transfers tab displays transfer task progress and status', (tester) async {
    await tester.pumpWidget(createTestWidget(initialTabIndex: 2));
    await tester.pumpAndSettle();

    expect(find.text('presentation.pdf'), findsOneWidget);
    expect(find.text('Clear Completed'), findsOneWidget);
  });
}
