import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:filezen/core/error/app_error.dart';
import 'package:filezen/data/network/network_transfer_repository.dart';
import 'package:filezen/data/network/protocol_adapters/webdav_adapter.dart';
import 'package:filezen/data/notifications/notification_repository.dart';
import 'package:filezen/domain/models/network_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Minimal WebDAV-ish server: PROPFIND listing, GET (fast and slow) and PUT,
/// with HTTP Basic auth (user "alice" / password "s3cret").
class _TestDavServer {
  late final HttpServer server;
  final Map<String, Uint8List> uploads = {};
  int slowChunksSent = 0;

  static final Uint8List hello = Uint8List.fromList(utf8.encode('Hello from WebDAV!'));

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  int get port => server.port;

  Future<void> stop() => server.close(force: true);

  bool _authorized(HttpRequest r) {
    final header = r.headers.value(HttpHeaders.authorizationHeader);
    return header == 'Basic ${base64.encode(utf8.encode('alice:s3cret'))}';
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      if (!_authorized(r)) {
        r.response.statusCode = HttpStatus.unauthorized;
        await r.response.close();
        return;
      }
      final path = r.uri.path;
      if (r.method == 'PROPFIND') {
        r.response.statusCode = 207;
        r.response.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
        r.response.write('''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
<d:response><d:href>/dav/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
<d:response><d:href>/dav/my%20file.txt</d:href><d:propstat><d:prop><d:getcontentlength>18</d:getcontentlength><d:resourcetype/></d:prop></d:propstat></d:response>
<d:response><d:href>http://127.0.0.1:$port/dav/sub/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
<d:response><d:href>/dav/bad%zzname.txt</d:href><d:propstat><d:prop><d:getcontentlength>1</d:getcontentlength><d:resourcetype/></d:prop></d:propstat></d:response>
</d:multistatus>''');
        await r.response.close();
      } else if (r.method == 'GET' && path == '/dav/hello.txt') {
        r.response.headers.contentLength = hello.length;
        r.response.add(hello);
        await r.response.close();
      } else if (r.method == 'GET' && path == '/dav/slow.bin') {
        r.response.headers.contentLength = 40 * 1024;
        for (var i = 0; i < 40; i++) {
          r.response.add(Uint8List(1024));
          await r.response.flush();
          slowChunksSent++;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        await r.response.close();
      } else if (r.method == 'PUT') {
        final bytes = await r.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        uploads[path] = Uint8List.fromList(bytes);
        r.response.statusCode = HttpStatus.created;
        await r.response.close();
      } else {
        r.response.statusCode = HttpStatus.notFound;
        await r.response.close();
      }
    } catch (_) {
      // Client aborted (cancel tests).
    }
  }
}

NetworkServerConfig _serverConfig(int port, {String password = 's3cret', String id = 'dav1'}) =>
    NetworkServerConfig(
      id: id,
      name: 'Test DAV',
      protocol: NetworkProtocol.webdav,
      host: '127.0.0.1',
      port: port,
      path: '/dav',
      username: 'alice',
      password: password,
    );

Future<NetworkTransferTask> _waitFor(
  NetworkTransferRepository repo,
  String id,
  bool Function(NetworkTransferTask) done, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final t = repo.getTransfers().firstWhere((t) => t.id == id);
    if (done(t)) return t;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('Transfer $id did not reach expected state: '
      '${repo.getTransfers().firstWhere((t) => t.id == id).status}');
}

void main() {
  late _TestDavServer dav;
  late Directory tempDir;

  setUp(() async {
    dav = _TestDavServer();
    await dav.start();
    tempDir = await Directory.systemTemp.createTemp('filezen_dav_test_');
  });

  tearDown(() async {
    await dav.stop();
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('WebDavProtocolAdapter (real HTTP)', () {
    const adapter = WebDavProtocolAdapter();

    test('testConnection succeeds with valid credentials and fails with wrong ones', () async {
      expect((await adapter.testConnection(_serverConfig(dav.port))).isSuccess, isTrue);

      final bad = await adapter.testConnection(_serverConfig(dav.port, password: 'nope'));
      expect(bad.isFailure, isTrue);
      expect(bad.errorOrNull!.message, contains('Authentication failed'));
    });

    test('listDirectory parses entries, skips the directory itself, handles absolute and bad hrefs',
        () async {
      final res = await adapter.listDirectory(_serverConfig(dav.port), '/');
      expect(res.isSuccess, isTrue);
      final items = {for (final i in res.dataOrNull!) i.name: i};

      expect(items.keys, containsAll(['my file.txt', 'sub']));
      expect(items['my file.txt']!.isDirectory, isFalse);
      expect(items['my file.txt']!.size, 18);
      expect(items['sub']!.isDirectory, isTrue);
      // A malformed percent-escape must not abort the whole listing.
      expect(items.keys.any((n) => n.startsWith('bad')), isTrue);
      expect(items.containsKey('dav'), isFalse);
    });

    test('downloadFile writes the real remote bytes with progress and leaves no .part file', () async {
      final dest = '${tempDir.path}/hello.txt';
      final progress = <int>[];
      final res = await adapter.downloadFile(
        _serverConfig(dav.port),
        RemoteFileItem(
          id: 'x',
          name: 'hello.txt',
          remotePath: '/dav/hello.txt',
          size: 18,
          isDirectory: false,
          modifiedAt: DateTime(2026),
          sourceId: 'dav1',
          sourceType: 'webdav',
        ),
        dest,
        onProgress: (received, total) => progress.add(received),
      );

      expect(res.isSuccess, isTrue);
      expect(File(dest).readAsStringSync(), 'Hello from WebDAV!');
      expect(File('$dest.part').existsSync(), isFalse);
      expect(progress.last, 18);
    });

    test('downloadFile reports HTTP errors and writes nothing', () async {
      final dest = '${tempDir.path}/missing.txt';
      final res = await adapter.downloadFile(
        _serverConfig(dav.port),
        RemoteFileItem(
          id: 'x',
          name: 'missing.txt',
          remotePath: '/dav/missing.txt',
          size: 1,
          isDirectory: false,
          modifiedAt: DateTime(2026),
          sourceId: 'dav1',
          sourceType: 'webdav',
        ),
        dest,
      );
      expect(res.isFailure, isTrue);
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.part').existsSync(), isFalse);
    });

    test('downloadFile honours cancellation and removes partial data', () async {
      final dest = '${tempDir.path}/slow.bin';
      var received = 0;
      final res = await adapter.downloadFile(
        _serverConfig(dav.port),
        RemoteFileItem(
          id: 'x',
          name: 'slow.bin',
          remotePath: '/dav/slow.bin',
          size: 40 * 1024,
          isDirectory: false,
          modifiedAt: DateTime(2026),
          sourceId: 'dav1',
          sourceType: 'webdav',
        ),
        dest,
        onProgress: (r, t) => received = r,
        isCancelled: () => received >= 3 * 1024,
      );

      expect(res.isFailure, isTrue);
      expect(res.errorOrNull, isA<OperationCancelledError>());
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.part').existsSync(), isFalse);
    });

    test('uploadFile sends the real file content', () async {
      final local = File('${tempDir.path}/up.txt')..writeAsStringSync('upload me');
      final res = await adapter.uploadFile(_serverConfig(dav.port), local.path, '/dav/up.txt');

      expect(res.isSuccess, isTrue);
      expect(utf8.decode(dav.uploads['/dav/up.txt']!), 'upload me');
    });

    test('uploadFile fails for a missing local file and for a cancelled transfer', () async {
      final missing = await adapter.uploadFile(
        _serverConfig(dav.port),
        '${tempDir.path}/nope.txt',
        '/dav/nope.txt',
      );
      expect(missing.isFailure, isTrue);

      final local = File('${tempDir.path}/c.txt')..writeAsStringSync('cancelled');
      final cancelled = await adapter.uploadFile(
        _serverConfig(dav.port),
        local.path,
        '/dav/c.txt',
        isCancelled: () => true,
      );
      expect(cancelled.errorOrNull, isA<OperationCancelledError>());
      expect(dav.uploads.containsKey('/dav/c.txt'), isFalse);
    });
  });

  group('NetworkTransferRepository queue (executes through adapters)', () {
    late NetworkTransferRepository repo;
    late NotificationRepository notifRepo;

    setUp(() async {
      notifRepo = NotificationRepository(customStoragePath: '${tempDir.path}/notifs.json');
      repo = NetworkTransferRepository(
        customStoragePath: '${tempDir.path}/servers.json',
        notificationRepository: notifRepo,
      );
      await repo.saveServer(_serverConfig(dav.port));
    });

    tearDown(() async => repo.stopLanServer());

    test('no placeholder servers are seeded on a fresh install', () async {
      final fresh = NetworkTransferRepository(customStoragePath: '${tempDir.path}/fresh.json');
      expect(await fresh.getServers(), isEmpty);
    });

    test('previously seeded starter servers are dropped on load', () async {
      File('${tempDir.path}/legacy.json').writeAsStringSync(jsonEncode([
        const NetworkServerConfig(
          id: 'starter_nas_smb',
          name: 'Home NAS (SMB)',
          protocol: NetworkProtocol.smb,
          host: '192.168.1.10',
          port: 445,
        ).toJson(),
        _serverConfig(dav.port, id: 'mine').toJson(),
      ]));
      final loaded = NetworkTransferRepository(customStoragePath: '${tempDir.path}/legacy.json');
      expect((await loaded.getServers()).map((s) => s.id), ['mine']);
    });

    test('a download really fetches the remote file and then notifies', () async {
      final dest = '${tempDir.path}/hello.txt';
      final task = (await repo.enqueueTransfer(
        fileName: 'hello.txt',
        direction: TransferDirection.download,
        sourcePath: '/dav/hello.txt',
        destinationPath: dest,
        protocol: NetworkProtocol.webdav,
        serverId: 'dav1',
        totalBytes: 18,
      ))
          .dataOrNull!;

      final done = await _waitFor(repo, task.id, (t) => t.status == TransferStatus.completed);
      expect(File(dest).readAsStringSync(), 'Hello from WebDAV!');
      expect(done.progress, 1.0);
      expect(done.bytesTransferred, 18);

      final notifs = await notifRepo.getNotifications();
      expect(notifs.any((n) => n.title.contains('Transfer Completed')), isTrue);
    });

    test('a download never overwrites an existing local file', () async {
      final dest = '${tempDir.path}/hello.txt';
      File(dest).writeAsStringSync('precious original');

      final task = (await repo.enqueueTransfer(
        fileName: 'hello.txt',
        direction: TransferDirection.download,
        sourcePath: '/dav/hello.txt',
        destinationPath: dest,
        protocol: NetworkProtocol.webdav,
        serverId: 'dav1',
      ))
          .dataOrNull!;

      final done = await _waitFor(repo, task.id, (t) => t.status == TransferStatus.completed);
      expect(File(dest).readAsStringSync(), 'precious original');
      expect(p.basename(done.destinationPath), 'hello (1).txt');
      expect(p.dirname(done.destinationPath), p.dirname(dest));
      expect(File(done.destinationPath).readAsStringSync(), 'Hello from WebDAV!');
    });

    test('an upload really sends the local file', () async {
      final local = File('${tempDir.path}/report.txt')..writeAsStringSync('quarterly numbers');
      final task = (await repo.enqueueTransfer(
        fileName: 'report.txt',
        direction: TransferDirection.upload,
        sourcePath: local.path,
        destinationPath: '/dav/report.txt',
        protocol: NetworkProtocol.webdav,
        serverId: 'dav1',
      ))
          .dataOrNull!;

      await _waitFor(repo, task.id, (t) => t.status == TransferStatus.completed);
      expect(utf8.decode(dav.uploads['/dav/report.txt']!), 'quarterly numbers');
    });

    test('server errors surface as a failed task, never a fake success', () async {
      final task = (await repo.enqueueTransfer(
        fileName: 'gone.txt',
        direction: TransferDirection.download,
        sourcePath: '/dav/gone.txt',
        destinationPath: '${tempDir.path}/gone.txt',
        protocol: NetworkProtocol.webdav,
        serverId: 'dav1',
      ))
          .dataOrNull!;

      final done = await _waitFor(repo, task.id, (t) => t.status == TransferStatus.failed);
      expect(done.errorMessage, contains('404'));
      expect(File('${tempDir.path}/gone.txt').existsSync(), isFalse);
      final notifs = await notifRepo.getNotifications();
      expect(notifs.any((n) => n.title.contains('Transfer Completed')), isFalse);
    });

    test('unsupported protocols fail honestly and write nothing', () async {
      await repo.saveServer(const NetworkServerConfig(
        id: 'ftp1',
        name: 'Old FTP',
        protocol: NetworkProtocol.ftp,
        host: '127.0.0.1',
        port: 21,
      ));
      final dest = '${tempDir.path}/ftp_file.txt';
      final task = (await repo.enqueueTransfer(
        fileName: 'ftp_file.txt',
        direction: TransferDirection.download,
        sourcePath: '/ftp_file.txt',
        destinationPath: dest,
        protocol: NetworkProtocol.ftp,
        serverId: 'ftp1',
      ))
          .dataOrNull!;

      final done = await _waitFor(repo, task.id, (t) => t.status == TransferStatus.failed);
      expect(done.errorMessage, contains('not supported'));
      expect(File(dest).existsSync(), isFalse);

      for (final proto in [NetworkProtocol.ftp, NetworkProtocol.sftp, NetworkProtocol.smb]) {
        final server = NetworkServerConfig(id: 'u', name: 'u', protocol: proto, host: 'h', port: 1);
        expect((await repo.testConnection(server)).isFailure, isTrue, reason: proto.name);
        expect((await repo.listRemoteFiles(server)).isFailure, isTrue, reason: proto.name);
      }
    });

    test('cloud and unknown-server tasks fail instead of completing', () async {
      final cloud = (await repo.enqueueTransfer(
        fileName: 'c.txt',
        direction: TransferDirection.download,
        sourcePath: '/c.txt',
        destinationPath: '${tempDir.path}/c.txt',
        cloudProvider: 'googleDrive',
      ))
          .dataOrNull!;
      final orphan = (await repo.enqueueTransfer(
        fileName: 'o.txt',
        direction: TransferDirection.download,
        sourcePath: '/o.txt',
        destinationPath: '${tempDir.path}/o.txt',
        serverId: 'deleted-server',
      ))
          .dataOrNull!;

      expect((await _waitFor(repo, cloud.id, (t) => t.status == TransferStatus.failed)).errorMessage,
          contains('not available'));
      expect((await _waitFor(repo, orphan.id, (t) => t.status == TransferStatus.failed)).errorMessage,
          contains('no longer configured'));
    });

    test('cancelling an in-flight download stops it and removes partial data', () async {
      final dest = '${tempDir.path}/slow.bin';
      final task = (await repo.enqueueTransfer(
        fileName: 'slow.bin',
        direction: TransferDirection.download,
        sourcePath: '/dav/slow.bin',
        destinationPath: dest,
        protocol: NetworkProtocol.webdav,
        serverId: 'dav1',
        totalBytes: 40 * 1024,
      ))
          .dataOrNull!;

      await _waitFor(repo, task.id,
          (t) => t.status == TransferStatus.transferring && t.bytesTransferred > 0);
      await repo.cancelTransfer(task.id);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(repo.getTransfers().firstWhere((t) => t.id == task.id).status, TransferStatus.cancelled);
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.part').existsSync(), isFalse);
      expect(dav.slowChunksSent, lessThan(40));
    });

    test('pausing an in-flight download discards partial data and resume restarts it', () async {
      final dest = '${tempDir.path}/slow.bin';
      final task = (await repo.enqueueTransfer(
        fileName: 'slow.bin',
        direction: TransferDirection.download,
        sourcePath: '/dav/slow.bin',
        destinationPath: dest,
        protocol: NetworkProtocol.webdav,
        serverId: 'dav1',
        totalBytes: 40 * 1024,
      ))
          .dataOrNull!;

      await _waitFor(repo, task.id,
          (t) => t.status == TransferStatus.transferring && t.bytesTransferred > 0);
      await repo.pauseTransfer(task.id);
      final paused = await _waitFor(repo, task.id, (t) => t.status == TransferStatus.paused);
      expect(paused.bytesTransferred, 0);
      expect(File('$dest.part').existsSync(), isFalse);

      await repo.resumeTransfer(task.id);
      final done = await _waitFor(
        repo,
        task.id,
        (t) => t.status == TransferStatus.completed,
        timeout: const Duration(seconds: 15),
      );
      expect(File(done.destinationPath).lengthSync(), 40 * 1024);
    });
  });
}
