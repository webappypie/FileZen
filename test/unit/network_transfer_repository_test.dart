import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:filezen/data/network/network_transfer_repository.dart';
import 'package:filezen/data/notifications/notification_repository.dart';
import 'package:filezen/domain/models/network_models.dart';

void main() {
  late Directory tempDir;
  late String storagePath;
  late String notifStoragePath;
  late NotificationRepository notifRepo;
  late NetworkTransferRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_network_test_');
    storagePath = '${tempDir.path}/test_network_servers.json';
    notifStoragePath = '${tempDir.path}/test_notifications.json';

    notifRepo = NotificationRepository(customStoragePath: notifStoragePath);
    repository = NetworkTransferRepository(
      customStoragePath: storagePath,
      notificationRepository: notifRepo,
    );
  });

  tearDown(() async {
    await repository.stopLanServer();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('NetworkTransferRepository - Server Configuration CRUD', () {
    test('Pre-seeds default starter servers on fresh configuration', () async {
      final servers = await repository.getServers();
      expect(servers, isNotEmpty);
      expect(servers.any((s) => s.protocol == NetworkProtocol.webdav), isTrue);
      expect(servers.any((s) => s.protocol == NetworkProtocol.smb), isTrue);
    });

    test('Saves and persists a new FTP server configuration', () async {
      const newServer = NetworkServerConfig(
        id: 'ftp_nas_1',
        name: 'Office FTP',
        protocol: NetworkProtocol.ftp,
        host: '192.168.1.200',
        port: 21,
        path: '/public',
        username: 'anonymous',
        isAnonymous: true,
      );

      final saveResult = await repository.saveServer(newServer);
      expect(saveResult.isSuccess, isTrue);

      final servers = await repository.getServers();
      expect(servers.any((s) => s.id == 'ftp_nas_1'), isTrue);

      // Verify file persistence round-trip
      final restoredRepo = NetworkTransferRepository(
        customStoragePath: storagePath,
        notificationRepository: notifRepo,
      );
      final restored = await restoredRepo.getServers();
      expect(restored.any((s) => s.id == 'ftp_nas_1'), isTrue);
    });

    test('Deletes a server configuration cleanly', () async {
      final initialServers = await repository.getServers();
      final toDeleteId = initialServers.first.id;

      final deleteResult = await repository.deleteServer(toDeleteId);
      expect(deleteResult.isSuccess, isTrue);

      final updatedServers = await repository.getServers();
      expect(updatedServers.any((s) => s.id == toDeleteId), isFalse);
    });

    test('watchServers stream emits on mutations', () async {
      final expectation = expectLater(
        repository.watchServers(),
        emitsThrough(predicate<List<NetworkServerConfig>>(
          (list) => list.any((s) => s.id == 'stream_srv'),
        )),
      );

      await repository.saveServer(const NetworkServerConfig(
        id: 'stream_srv',
        name: 'Stream Server',
        protocol: NetworkProtocol.sftp,
        host: '10.0.0.1',
        port: 22,
      ));

      await expectation;
    });
  });

  group('NetworkTransferRepository - LAN Web Server & Sharing', () {
    test('Starts and stops LAN web server, generates valid PIN and URL', () async {
      final sessionResult = await repository.startLanServer(
        port: 8899,
        preferredPin: '4321',
      );

      expect(sessionResult.isSuccess, isTrue);
      final session = sessionResult.dataOrNull!;
      expect(session.isActive, isTrue);
      expect(session.accessPin, '4321');
      expect(session.displayUrl, contains(':'));

      // Check notification was emitted
      final notifs = await notifRepo.getNotifications();
      expect(notifs.any((n) => n.title.contains('Wi-Fi Web Share Active')), isTrue);

      await repository.stopLanServer();
      final stoppedSession = repository.getLanSession();
      expect(stoppedSession.isActive, isFalse);
    });

    test('LAN Web Server handles HTTP authentication and file operations', () async {
      final dummyFile = File('${tempDir.path}/share_test.txt');
      await dummyFile.writeAsString('Hello from FileZen Wi-Fi Share!');

      repository.setSharedFiles([dummyFile.path]);
      final startResult = await repository.startLanServer(
        port: 9091,
        preferredPin: '7788',
      );
      expect(startResult.isSuccess, isTrue);
      final session = startResult.dataOrNull!;

      final client = HttpClient();

      // Test 1: ping status endpoint
      final statusReq = await client.getUrl(Uri.parse('http://127.0.0.1:${session.port}/api/status'));
      final statusRes = await statusReq.close();
      expect(statusRes.statusCode, HttpStatus.ok);
      final statusJson = jsonDecode(await utf8.decodeStream(statusRes)) as Map<String, dynamic>;
      expect(statusJson['app'], 'FileZen');

      // Test 2: failed PIN authentication
      final badAuthReq = await client.postUrl(Uri.parse('http://127.0.0.1:${session.port}/api/auth'));
      badAuthReq.headers.contentType = ContentType.json;
      badAuthReq.write(jsonEncode({'pin': '0000'}));
      final badAuthRes = await badAuthReq.close();
      expect(badAuthRes.statusCode, HttpStatus.unauthorized);

      // Test 3: successful PIN authentication
      final authReq = await client.postUrl(Uri.parse('http://127.0.0.1:${session.port}/api/auth'));
      authReq.headers.contentType = ContentType.json;
      authReq.write(jsonEncode({'pin': '7788'}));
      final authRes = await authReq.close();
      expect(authRes.statusCode, HttpStatus.ok);
      final authJson = jsonDecode(await utf8.decodeStream(authRes)) as Map<String, dynamic>;
      expect(authJson['success'], isTrue);
      final token = authJson['token'] as String;

      // Test 4: list shared files
      final filesReq = await client.getUrl(Uri.parse('http://127.0.0.1:${session.port}/api/files'));
      filesReq.headers.set('Authorization', 'Bearer $token');
      final filesRes = await filesReq.close();
      expect(filesRes.statusCode, HttpStatus.ok);
      final filesJson = jsonDecode(await utf8.decodeStream(filesRes)) as Map<String, dynamic>;
      final filesList = filesJson['files'] as List<dynamic>;
      expect(filesList, isNotEmpty);
      expect(filesList.first['name'], 'share_test.txt');

      // Test 5: download shared file
      final fileId = filesList.first['id'] as String;
      final dlReq = await client.getUrl(Uri.parse('http://127.0.0.1:${session.port}/api/download/$fileId'));
      dlReq.headers.set('Authorization', 'Bearer $token');
      final dlRes = await dlReq.close();
      expect(dlRes.statusCode, HttpStatus.ok);
      final downloadedContent = await utf8.decodeStream(dlRes);
      expect(downloadedContent, 'Hello from FileZen Wi-Fi Share!');

      client.close();
      await repository.stopLanServer();
    });
  });

  group('NetworkTransferRepository - Transfer Queue Lifecycle', () {
    test('Enqueues, runs worker, and completes transfer task with notification', () async {
      final taskResult = await repository.enqueueTransfer(
        fileName: 'report_2026.pdf',
        direction: TransferDirection.download,
        sourcePath: '/remote/report_2026.pdf',
        destinationPath: '${tempDir.path}/report_2026.pdf',
        protocol: NetworkProtocol.webdav,
        totalBytes: 5000,
      );

      expect(taskResult.isSuccess, isTrue);
      final task = taskResult.dataOrNull!;
      expect(task.fileName, 'report_2026.pdf');

      // Wait for task worker loop to process
      await Future.delayed(const Duration(milliseconds: 1000));

      final transfers = repository.getTransfers();
      final finished = transfers.firstWhere((t) => t.id == task.id);
      expect(finished.status, TransferStatus.completed);
      expect(finished.progress, 1.0);

      // Check notification
      final notifs = await notifRepo.getNotifications();
      expect(notifs.any((n) => n.title.contains('Transfer Completed')), isTrue);
    });

    test('Cancels an active or pending transfer task', () async {
      final taskResult = await repository.enqueueTransfer(
        fileName: 'huge_backup.iso',
        direction: TransferDirection.upload,
        sourcePath: '${tempDir.path}/huge.iso',
        destinationPath: '/remote/huge.iso',
        protocol: NetworkProtocol.smb,
        totalBytes: 100000000,
      );

      final task = taskResult.dataOrNull!;
      await repository.cancelTransfer(task.id);

      final transfers = repository.getTransfers();
      final cancelled = transfers.firstWhere((t) => t.id == task.id);
      expect(cancelled.status, TransferStatus.cancelled);
    });

    test('Clears completed and cancelled transfers', () async {
      await repository.enqueueTransfer(
        fileName: 'quick.txt',
        direction: TransferDirection.download,
        sourcePath: '/src',
        destinationPath: '/dest',
        totalBytes: 100,
      );

      await Future.delayed(const Duration(milliseconds: 900));
      await repository.clearCompletedTransfers();

      final remaining = repository.getTransfers();
      expect(remaining.where((t) => t.status == TransferStatus.completed).isEmpty, isTrue);
    });
  });
}
