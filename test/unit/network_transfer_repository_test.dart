import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:filezen/data/network/network_transfer_repository.dart';
import 'package:filezen/data/notifications/notification_repository.dart';
import 'package:filezen/domain/models/network_models.dart';

import '../support/vault_test_doubles.dart';

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
    test('Starts with no servers (nothing is pre-seeded)', () async {
      expect(await repository.getServers(), isEmpty);
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
      await repository.saveServer(const NetworkServerConfig(
        id: 'to_delete',
        name: 'Temp',
        protocol: NetworkProtocol.webdav,
        host: '10.0.0.5',
        port: 80,
      ));
      final toDeleteId = (await repository.getServers()).first.id;

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
    // End-to-end transfers against a real WebDAV server live in
    // webdav_transfer_test.dart; here we cover queue bookkeeping.
    test('A task without a usable server fails instead of faking completion', () async {
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

      await Future.delayed(const Duration(milliseconds: 300));

      final finished = repository.getTransfers().firstWhere((t) => t.id == task.id);
      expect(finished.status, TransferStatus.failed);
      expect(File('${tempDir.path}/report_2026.pdf').existsSync(), isFalse);

      final notifs = await notifRepo.getNotifications();
      expect(notifs.any((n) => n.title.contains('Transfer Completed')), isFalse);
    });

    test('Cancels a transfer task', () async {
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

      final cancelled = repository.getTransfers().firstWhere((t) => t.id == task.id);
      expect(cancelled.status, TransferStatus.cancelled);
    });

    test('Clears finished transfers', () async {
      await repository.enqueueTransfer(
        fileName: 'quick.txt',
        direction: TransferDirection.download,
        sourcePath: '/src',
        destinationPath: '/dest',
        totalBytes: 100,
      );

      await Future.delayed(const Duration(milliseconds: 300));
      await repository.clearCompletedTransfers();

      expect(repository.getTransfers(), isEmpty);
    });
  });

  group('NetworkTransferRepository - saved credentials', () {
    const secret = 'Correct-Horse-9!';
    const server = NetworkServerConfig(
      id: 'dav_secure',
      name: 'Secure DAV',
      protocol: NetworkProtocol.webdav,
      host: '192.168.1.50',
      port: 8080,
      path: '/dav',
      username: 'alice',
      password: secret,
    );

    test('passwords are Keystore-wrapped on disk and restored on load', () async {
      final backend = FakeVaultCryptoBackend();
      final repo = NetworkTransferRepository(
        customStoragePath: storagePath,
        secretBackend: backend,
      );
      await repo.saveServer(server);

      final onDisk = File(storagePath).readAsStringSync();
      expect(onDisk.contains(secret), isFalse);
      final stored = (jsonDecode(onDisk) as List).single as Map<String, dynamic>;
      expect(stored['password'], '');
      expect(stored['passwordEnc'], isNotEmpty);

      final restored = NetworkTransferRepository(
        customStoragePath: storagePath,
        secretBackend: backend,
      );
      expect((await restored.getServers()).single.password, secret);
    });

    test('a legacy plaintext password is re-saved wrapped on first load', () async {
      File(storagePath).writeAsStringSync(jsonEncode([server.toJson()]));
      expect(File(storagePath).readAsStringSync().contains(secret), isTrue);

      final repo = NetworkTransferRepository(
        customStoragePath: storagePath,
        secretBackend: FakeVaultCryptoBackend(),
      );
      expect((await repo.getServers()).single.password, secret);
      expect(File(storagePath).readAsStringSync().contains(secret), isFalse);
    });

    test('if the Keystore refuses, the password is dropped rather than written in the clear', () async {
      final backend = FakeVaultCryptoBackend()..deviceSlotFailure = 'CRYPTO_ERROR';
      final repo = NetworkTransferRepository(
        customStoragePath: storagePath,
        secretBackend: backend,
      );
      await repo.saveServer(server);

      expect(File(storagePath).readAsStringSync().contains(secret), isFalse);
    });

    test('an unrecoverable wrapped password loads as empty (user must re-enter)', () async {
      final backend = FakeVaultCryptoBackend();
      await NetworkTransferRepository(customStoragePath: storagePath, secretBackend: backend)
          .saveServer(server);

      backend.deviceKeyPresent = false; // e.g. app data restored to another device
      final repo = NetworkTransferRepository(customStoragePath: storagePath, secretBackend: backend);
      final loaded = (await repo.getServers()).single;
      expect(loaded.id, 'dav_secure');
      expect(loaded.password, isEmpty);
    });
  });
}
