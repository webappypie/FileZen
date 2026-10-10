import 'dart:convert';
import 'dart:io';

import 'package:filezen/data/network/lan_web_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late LanWebServer server;
  late HttpClient client;
  late int port;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_lan_sec_');
    server = LanWebServer();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> start({String? pin = '482916'}) async {
    final session = await server.start(port: 0, preferredPin: pin);
    expect(session.isActive, isTrue);
    port = session.port;
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

  Future<(int, String, HttpHeaders)> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final req = await client.openUrl(method, url(path));
    headers.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentLength = body.length;
      req.add(body);
    }
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    return (res.statusCode, text, res.headers);
  }

  Future<String?> login(String pin) async {
    final (status, text, _) = await send(
      'POST',
      '/api/auth',
      headers: {'Content-Type': 'application/json'},
      body: utf8.encode(jsonEncode({'pin': pin})),
    );
    if (status != 200) return null;
    return (jsonDecode(text) as Map<String, dynamic>)['token'] as String;
  }

  group('PIN protection', () {
    test('generated PINs are 6 digits', () async {
      final session = await server.start(port: 0);
      expect(session.accessPin, matches(RegExp(r'^\d{6}$')));
    });

    test('five wrong PINs lock the client out, even for the correct PIN', () async {
      await start();
      for (var i = 0; i < 5; i++) {
        final (status, _, _) = await send(
          'POST',
          '/api/auth',
          headers: {'Content-Type': 'application/json'},
          body: utf8.encode(jsonEncode({'pin': '00000$i'})),
        );
        expect(status, HttpStatus.unauthorized, reason: 'attempt $i');
      }

      final (status, text, _) = await send(
        'POST',
        '/api/auth',
        headers: {'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({'pin': '482916'})),
      );
      expect(status, HttpStatus.tooManyRequests);
      expect(jsonDecode(text)['success'], isFalse);
      expect(await login('482916'), isNull);
    });

    test('a correct PIN before the limit resets the failure counter', () async {
      await start();
      for (var i = 0; i < 4; i++) {
        await send('POST', '/api/auth',
            headers: {'Content-Type': 'application/json'},
            body: utf8.encode(jsonEncode({'pin': '11111$i'})));
      }
      expect(await login('482916'), isNotNull);
      // Counter was reset: four more wrong guesses still do not lock out.
      for (var i = 0; i < 4; i++) {
        await send('POST', '/api/auth',
            headers: {'Content-Type': 'application/json'},
            body: utf8.encode(jsonEncode({'pin': '22222$i'})));
      }
      expect(await login('482916'), isNotNull);
    });

    test('the raw PIN is not accepted as a credential on protected routes', () async {
      await start();
      final (status, _, _) = await send('GET', '/api/files', headers: {'X-Pin': '482916'});
      expect(status, HttpStatus.unauthorized);
    });

    test('malformed or oversized auth bodies are rejected cleanly', () async {
      await start();
      final (bad, _, _) = await send('POST', '/api/auth',
          headers: {'Content-Type': 'application/json'}, body: utf8.encode('[1,2,3]'));
      expect(bad, HttpStatus.unauthorized);

      // The server refuses on the declared length and closes the connection, so
      // the client sees either the 413 or a reset while still sending the body.
      int? big;
      try {
        big = (await send('POST', '/api/auth',
                headers: {'Content-Type': 'application/json'}, body: List.filled(10000, 0x61)))
            .$1;
      } on SocketException {
        // acceptable: connection closed early
      } on HttpException {
        // acceptable: connection closed early
      }
      expect(big, anyOf(isNull, HttpStatus.requestEntityTooLarge));
    });
  });

  group('browser exposure', () {
    test('sends no CORS headers (other websites cannot script the API)', () async {
      await start();
      final (_, _, headers) = await send('GET', '/api/status', headers: {'Origin': 'https://evil.example'});
      expect(headers.value('access-control-allow-origin'), isNull);

      final (optionsStatus, _, optionsHeaders) = await send('OPTIONS', '/api/auth');
      expect(optionsStatus, HttpStatus.methodNotAllowed);
      expect(optionsHeaders.value('access-control-allow-origin'), isNull);
    });

    test('portal is served with CSP and builds the file list without innerHTML injection', () async {
      await start();
      final (status, html, headers) = await send('GET', '/');
      expect(status, HttpStatus.ok);
      expect(headers.value('content-security-policy'), contains("default-src 'none'"));
      expect(headers.value('x-content-type-options'), 'nosniff');
      expect(html, contains('6-digit PIN'));
      // File names must only ever be assigned via textContent.
      expect(html, isNot(contains(r'${f.name}')));
      expect(html, contains('nameEl.textContent = f.name'));
      expect(RegExp(r'innerHTML\s*=\s*[^;]*f\.name').hasMatch(html), isFalse);
    });
  });

  group('downloads', () {
    test('the portal link (token in the query string) can actually download', () async {
      final shared = File(p.join(tempDir.path, 'spaced name.txt'))..writeAsStringSync('payload');
      server.setSharedFiles([shared.path]);
      await start();
      final token = (await login('482916'))!;

      final (_, listText, _) =
          await send('GET', '/api/files', headers: {'Authorization': 'Bearer $token'});
      final id = (jsonDecode(listText)['files'] as List).first['id'] as String;

      final (status, body, headers) =
          await send('GET', '/api/download/${Uri.encodeComponent(id)}?token=${Uri.encodeComponent(token)}');
      expect(status, HttpStatus.ok);
      expect(body, 'payload');
      expect(headers.value('content-disposition'), contains("filename*=UTF-8''spaced%20name.txt"));
    });

    test('downloads still require a valid token, and only listed files can be fetched', () async {
      final shared = File(p.join(tempDir.path, 'shared.txt'))..writeAsStringSync('ok');
      final secret = File(p.join(tempDir.path, 'secret.txt'))..writeAsStringSync('nope');
      server.setSharedFiles([shared.path]);
      await start();
      final token = (await login('482916'))!;

      String idFor(String path) => base64Url.encode(utf8.encode(path));

      final (noToken, _, _) = await send('GET', '/api/download/${idFor(shared.path)}');
      expect(noToken, HttpStatus.unauthorized);

      final (badToken, _, _) = await send('GET', '/api/download/${idFor(shared.path)}?token=bogus');
      expect(badToken, HttpStatus.unauthorized);

      final (unlisted, _, _) =
          await send('GET', '/api/download/${idFor(secret.path)}?token=$token');
      expect(unlisted, HttpStatus.notFound);

      // The query token is not a general-purpose credential.
      final (apiViaQuery, _, _) = await send('GET', '/api/files?token=$token');
      expect(apiViaQuery, HttpStatus.unauthorized);
    });
  });

  group('uploads', () {
    test('land in the configured folder, never overwrite, and sanitise names', () async {
      final dest = Directory(p.join(tempDir.path, 'incoming'));
      server.setUploadDirectory(dest.path);
      await start();
      final token = (await login('482916'))!;

      Future<Map<String, dynamic>> upload(String name, String content) async {
        final (status, text, _) = await send(
          'POST',
          '/api/upload',
          headers: {'Authorization': 'Bearer $token', 'X-File-Name': name},
          body: utf8.encode(content),
        );
        expect(status, HttpStatus.ok);
        return jsonDecode(text) as Map<String, dynamic>;
      }

      final first = await upload(Uri.encodeComponent('photo.txt'), 'one');
      final second = await upload(Uri.encodeComponent('photo.txt'), 'two');
      expect(first['fileName'], 'photo.txt');
      expect(second['fileName'], 'photo (1).txt');
      expect(File(p.join(dest.path, 'photo.txt')).readAsStringSync(), 'one');
      expect(File(p.join(dest.path, 'photo (1).txt')).readAsStringSync(), 'two');

      // Non-ASCII names work because the portal percent-encodes the header.
      final unicode = await upload(Uri.encodeComponent('résumé 日本.txt'), 'u');
      expect(unicode['fileName'], 'résumé 日本.txt');

      // Path traversal in the supplied name is neutralised.
      final sneaky = await upload(Uri.encodeComponent('../../outside.txt'), 'x');
      expect(sneaky['fileName'], 'outside.txt');
      expect(File(p.join(tempDir.path, 'outside.txt')).existsSync(), isFalse);
      expect(File(p.join(dest.path, 'outside.txt')).existsSync(), isTrue);
    });

    test('require authentication', () async {
      server.setUploadDirectory(tempDir.path);
      await start();
      final (status, _, _) = await send('POST', '/api/upload',
          headers: {'X-File-Name': 'a.txt'}, body: utf8.encode('x'));
      expect(status, HttpStatus.unauthorized);
      expect(File(p.join(tempDir.path, 'a.txt')).existsSync(), isFalse);
    });

    test('reject files larger than the limit by declared length', () async {
      server.setUploadDirectory(tempDir.path);
      await start();
      final token = (await login('482916'))!;

      // Raw socket: HttpClient refuses to send a header-only body of this length.
      final socket = await Socket.connect('127.0.0.1', port);
      const crlf = '\r\n';
      socket.write('POST /api/upload HTTP/1.1$crlf'
          'Host: 127.0.0.1:$port$crlf'
          'Authorization: Bearer $token$crlf'
          'X-File-Name: huge.bin$crlf'
          'Content-Length: ${LanWebServer.maxUploadBytes + 1}$crlf'
          'Connection: close$crlf$crlf');
      await socket.flush();
      // The refusal is sent immediately; the server then keeps the socket open
      // for the (never-sent) body, so read only the first chunk, not to EOF.
      final response = utf8.decode(await socket.first.timeout(const Duration(seconds: 5)));
      socket.destroy();
      expect(response, startsWith('HTTP/1.1 413'));
      expect(File(p.join(tempDir.path, 'huge.bin')).existsSync(), isFalse);
    });
  });
}
