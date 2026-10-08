import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../domain/models/network_models.dart';

/// Embedded lightweight HTTP server providing LAN and browser-based file transfers.
class LanWebServer {
  HttpServer? _server;
  LanTransferSession _session = const LanTransferSession();
  final StreamController<LanTransferSession> _sessionController =
      StreamController<LanTransferSession>.broadcast();

  final List<String> _sharedFilePaths = [];
  String _uploadDirectoryPath = '';
  final Set<String> _authenticatedTokens = {};

  Stream<LanTransferSession> get sessionStream => _sessionController.stream;
  LanTransferSession get currentSession => _session;

  void setSharedFiles(List<String> paths) {
    _sharedFilePaths.clear();
    _sharedFilePaths.addAll(paths.where((p) => File(p).existsSync()));
    _updateSession(_session.copyWith(filesSharedCount: _sharedFilePaths.length));
  }

  void setUploadDirectory(String path) {
    _uploadDirectoryPath = path;
  }

  /// Starts the embedded HTTP server on the specified port.
  Future<LanTransferSession> start({
    int port = 8080,
    String? preferredPin,
  }) async {
    if (_server != null) {
      await stop();
    }

    _updateSession(_session.copyWith(status: LanSessionStatus.starting));

    try {
      final pin = preferredPin ?? _generateRandomPin();
      final ipAddresses = await _discoverLocalIpAddresses();

      // Attempt to bind to any IPv4 address
      HttpServer? boundServer;
      int bindPort = port;

      for (int attempt = 0; attempt < 5; attempt++) {
        try {
          boundServer = await HttpServer.bind(
            InternetAddress.anyIPv4,
            bindPort,
            shared: true,
          );
          break;
        } catch (_) {
          bindPort++; // Try next port if occupied
        }
      }

      if (boundServer == null) {
        throw const SocketException('Unable to bind local transfer server to any port');
      }

      _server = boundServer;
      _authenticatedTokens.clear();

      final primaryUrl = ipAddresses.isNotEmpty
          ? 'http://${ipAddresses.first}:$bindPort'
          : 'http://localhost:$bindPort';

      _session = LanTransferSession(
        status: LanSessionStatus.active,
        port: bindPort,
        ipAddresses: ipAddresses,
        accessPin: pin,
        connectedClientsCount: 0,
        filesSharedCount: _sharedFilePaths.length,
        preferredUrl: primaryUrl,
      );
      _sessionController.add(_session);

      AppLogger.info('LanWebServer', 'Started on $primaryUrl with PIN: $pin');

      // Listen for incoming requests
      _server!.listen(
        _handleRequest,
        onError: (e, st) {
          AppLogger.error('LanWebServer', 'Server error: $e');
        },
      );

      return _session;
    } catch (e) {
      AppLogger.error('LanWebServer', 'Failed to start server: $e');
      _session = LanTransferSession(
        status: LanSessionStatus.error,
        errorMessage: e.toString(),
      );
      _sessionController.add(_session);
      return _session;
    }
  }

  /// Stops the running server.
  Future<void> stop() async {
    if (_server != null) {
      try {
        await _server!.close(force: true);
      } catch (e) {
        AppLogger.warning('LanWebServer', 'Error stopping server: $e');
      }
      _server = null;
    }

    _authenticatedTokens.clear();
    _session = const LanTransferSession(status: LanSessionStatus.stopped);
    _sessionController.add(_session);
    AppLogger.info('LanWebServer', 'Server stopped');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      // CORS headers for modern browser compatibility
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Pin');

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      final uri = request.uri;
      final path = uri.path;

      // API: Server Status / Ping
      if (path == '/api/status') {
        _sendJsonResponse(request.response, {
          'app': 'FileZen',
          'status': 'online',
          'requiresAuth': true,
        });
        return;
      }

      // API: Authentication with PIN
      if (path == '/api/auth' && request.method == 'POST') {
        final body = await utf8.decodeStream(request);
        final json = jsonDecode(body) as Map<String, dynamic>;
        final enteredPin = (json['pin'] as String?)?.trim() ?? '';

        if (enteredPin == _session.accessPin) {
          final token = _generateAuthToken();
          _authenticatedTokens.add(token);
          _session = _session.copyWith(
            connectedClientsCount: _session.connectedClientsCount + 1,
          );
          _sessionController.add(_session);

          _sendJsonResponse(request.response, {
            'success': true,
            'token': token,
            'message': 'Authenticated successfully',
          });
        } else {
          _sendJsonResponse(request.response, {
            'success': false,
            'error': 'Incorrect PIN',
          }, statusCode: HttpStatus.unauthorized);
        }
        return;
      }

      // Check authentication for protected routes
      final isAuth = _isAuthorized(request);

      if (path == '/api/files' && request.method == 'GET') {
        if (!isAuth) {
          _sendJsonResponse(request.response, {'error': 'Unauthorized'},
              statusCode: HttpStatus.unauthorized);
          return;
        }

        final files = _sharedFilePaths.map((filePath) {
          final file = File(filePath);
          final exists = file.existsSync();
          final size = exists ? file.lengthSync() : 0;
          final name = p.basename(filePath);
          final ext = p.extension(filePath).replaceAll('.', '');

          return {
            'id': base64Url.encode(utf8.encode(filePath)),
            'name': name,
            'extension': ext,
            'size': size,
            'mimeType': lookupMimeType(filePath) ?? 'application/octet-stream',
          };
        }).toList();

        _sendJsonResponse(request.response, {'files': files});
        return;
      }

      // API: File Download
      if (path.startsWith('/api/download/') && request.method == 'GET') {
        if (!isAuth) {
          _sendJsonResponse(request.response, {'error': 'Unauthorized'},
              statusCode: HttpStatus.unauthorized);
          return;
        }

        final encodedId = path.replaceFirst('/api/download/', '');
        String filePath = '';
        try {
          filePath = utf8.decode(base64Url.decode(encodedId));
        } catch (_) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }

        final file = File(filePath);
        if (!file.existsSync() || !_sharedFilePaths.contains(filePath)) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        final fileName = p.basename(filePath);
        final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';

        request.response.headers.contentType = ContentType.parse(mimeType);
        request.response.headers.add(
          'Content-Disposition',
          'attachment; filename="${Uri.encodeComponent(fileName)}"',
        );
        request.response.headers.contentLength = file.lengthSync();

        await request.response.addStream(file.openRead());
        await request.response.close();
        return;
      }

      // API: File Upload
      if (path == '/api/upload' && request.method == 'POST') {
        if (!isAuth) {
          _sendJsonResponse(request.response, {'error': 'Unauthorized'},
              statusCode: HttpStatus.unauthorized);
          return;
        }

        final uploadFileName = request.headers.value('X-File-Name') ??
            'uploaded_${DateTime.now().millisecondsSinceEpoch}.dat';
        final saveDir = _uploadDirectoryPath.isNotEmpty
            ? _uploadDirectoryPath
            : Directory.systemTemp.path;

        final targetFile = File(p.join(saveDir, p.basename(uploadFileName)));
        final sink = targetFile.openWrite();

        await request.listen((chunk) {
          sink.add(chunk);
        }).asFuture();

        await sink.flush();
        await sink.close();

        _sendJsonResponse(request.response, {
          'success': true,
          'fileName': p.basename(targetFile.path),
          'size': targetFile.lengthSync(),
        });
        return;
      }

      // Web Interface: Responsive HTML Portal
      if (path == '/' || path == '/index.html') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_buildWebPortalHtml());
        await request.response.close();
        return;
      }

      // Default: 404
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      AppLogger.error('LanWebServer', 'Error handling request: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  bool _isAuthorized(HttpRequest request) {
    // Check Authorization header or X-Token or X-Pin header
    final authHeader = request.headers.value('Authorization');
    final token = authHeader?.replaceFirst('Bearer ', '').trim() ??
        request.headers.value('X-Token');
    if (token != null && _authenticatedTokens.contains(token)) {
      return true;
    }

    // Direct PIN header access
    final pinHeader = request.headers.value('X-Pin');
    if (pinHeader != null && pinHeader == _session.accessPin) {
      return true;
    }

    return false;
  }

  void _sendJsonResponse(HttpResponse response, Map<String, dynamic> data,
      {int statusCode = HttpStatus.ok}) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }

  void _updateSession(LanTransferSession updated) {
    _session = updated;
    _sessionController.add(_session);
  }

  Future<List<String>> _discoverLocalIpAddresses() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      AppLogger.warning('LanWebServer', 'Failed to inspect interfaces: $e');
    }
    if (ips.isEmpty) {
      ips.add('127.0.0.1');
    }
    return ips;
  }

  String _generateRandomPin() {
    final random = Random();
    return (1000 + random.nextInt(9000)).toString();
  }

  String _generateAuthToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _buildWebPortalHtml() {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>FileZen • Web Transfer</title>
  <style>
    :root {
      --primary: #4F46E5;
      --primary-hover: #4338CA;
      --bg: #0F172A;
      --surface: #1E293B;
      --border: #334155;
      --text: #F8FAFC;
      --text-muted: #94A3B8;
      --accent: #10B981;
    }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
      padding: 24px;
      box-sizing: border-box;
    }
    .header {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 24px;
    }
    .badge {
      background: rgba(79, 70, 229, 0.2);
      border: 1px solid var(--primary);
      color: #818CF8;
      padding: 4px 12px;
      border-radius: 9999px;
      font-size: 13px;
      font-weight: 600;
    }
    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 24px;
      width: 100%;
      max-width: 540px;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.4);
    }
    h1 { margin: 0; font-size: 24px; font-weight: 700; }
    h2 { margin: 0 0 16px 0; font-size: 18px; }
    p { color: var(--text-muted); font-size: 14px; margin: 4px 0 16px 0; }
    input[type="text"], input[type="password"] {
      width: 100%;
      padding: 12px;
      background: #0F172A;
      border: 1px solid var(--border);
      border-radius: 8px;
      color: white;
      font-size: 16px;
      box-sizing: border-box;
      margin-bottom: 12px;
    }
    button {
      background: var(--primary);
      color: white;
      border: none;
      padding: 12px 20px;
      border-radius: 8px;
      font-weight: 600;
      font-size: 15px;
      cursor: pointer;
      width: 100%;
      transition: background 0.2s;
    }
    button:hover { background: var(--primary-hover); }
    .file-item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px;
      border-bottom: 1px solid var(--border);
    }
    .file-item:last-child { border-bottom: none; }
    .btn-download {
      background: var(--accent);
      color: white;
      padding: 6px 14px;
      border-radius: 6px;
      text-decoration: none;
      font-size: 13px;
      font-weight: 600;
    }
    .dropzone {
      border: 2px dashed var(--border);
      border-radius: 12px;
      padding: 24px;
      text-align: center;
      margin-top: 16px;
      cursor: pointer;
    }
    .hidden { display: none; }
  </style>
</head>
<body>
  <div class="header">
    <h1>FileZen</h1>
    <span class="badge">LAN Web Share</span>
  </div>

  <div class="card" id="authCard">
    <h2>Security Verification</h2>
    <p>Enter the 4-digit PIN displayed on your FileZen mobile app to access files.</p>
    <input type="password" id="pinInput" placeholder="Enter 4-digit PIN" maxlength="6" autofocus />
    <button onclick="authenticate()">Connect to Device</button>
    <p id="authError" style="color: #EF4444; margin-top: 8px; display: none;">Invalid PIN. Please try again.</p>
  </div>

  <div class="card hidden" id="mainCard">
    <h2>Shared Files</h2>
    <p>Download files shared from your device or drop files below to send to your phone.</p>
    <div id="fileList">Loading files...</div>

    <div class="dropzone" id="dropzone" onclick="document.getElementById('fileUpload').click()">
      <p style="margin: 0; font-weight: 600;">+ Click or drop files here to upload to FileZen</p>
      <input type="file" id="fileUpload" class="hidden" onchange="uploadFile(this.files[0])" />
    </div>
  </div>

  <script>
    let authToken = sessionStorage.getItem('fz_token') || '';

    if (authToken) {
      loadFiles();
    }

    async function authenticate() {
      const pin = document.getElementById('pinInput').value.trim();
      const errEl = document.getElementById('authError');
      errEl.style.display = 'none';

      try {
        const res = await fetch('/api/auth', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ pin })
        });
        const data = await res.json();
        if (data.success && data.token) {
          authToken = data.token;
          sessionStorage.setItem('fz_token', authToken);
          loadFiles();
        } else {
          errEl.style.display = 'block';
        }
      } catch (e) {
        errEl.innerText = 'Connection error: ' + e.message;
        errEl.style.display = 'block';
      }
    }

    async function loadFiles() {
      document.getElementById('authCard').classList.add('hidden');
      document.getElementById('mainCard').classList.remove('hidden');

      try {
        const res = await fetch('/api/files', {
          headers: { 'Authorization': 'Bearer ' + authToken }
        });
        if (res.status === 401) {
          sessionStorage.removeItem('fz_token');
          location.reload();
          return;
        }
        const data = await res.json();
        const listEl = document.getElementById('fileList');

        if (!data.files || data.files.length === 0) {
          listEl.innerHTML = '<p>No files currently shared by device.</p>';
          return;
        }

        listEl.innerHTML = data.files.map(f => `
          <div class="file-item">
            <div>
              <div style="font-weight: 600;">\${f.name}</div>
              <div style="font-size: 12px; color: var(--text-muted);">\${(f.size / (1024 * 1024)).toFixed(2)} MB</div>
            </div>
            <a class="btn-download" href="/api/download/\${f.id}?token=\${authToken}" target="_blank">Download</a>
          </div>
        `).join('');
      } catch (e) {
        document.getElementById('fileList').innerHTML = '<p>Failed to load files: ' + e.message + '</p>';
      }
    }

    async function uploadFile(file) {
      if (!file) return;
      const dropzone = document.getElementById('dropzone');
      dropzone.innerText = 'Uploading ' + file.name + '...';

      try {
        const res = await fetch('/api/upload', {
          method: 'POST',
          headers: {
            'Authorization': 'Bearer ' + authToken,
            'X-File-Name': file.name
          },
          body: file
        });
        const data = await res.json();
        if (data.success) {
          dropzone.innerHTML = '<p style="color: var(--accent); margin: 0;">✓ Uploaded ' + file.name + ' successfully!</p>';
          setTimeout(() => {
            dropzone.innerHTML = '<p style="margin: 0; font-weight: 600;">+ Click or drop files here to upload to FileZen</p>';
          }, 3000);
        }
      } catch (e) {
        dropzone.innerHTML = '<p style="color: #EF4444; margin: 0;">Upload failed: ' + e.message + '</p>';
      }
    }
  </script>
</body>
</html>''';
  }
}
