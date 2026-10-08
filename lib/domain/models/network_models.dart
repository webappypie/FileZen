import 'dart:convert';

/// Supported network storage and transfer protocols in FileZen.
enum NetworkProtocol {
  smb,
  ftp,
  sftp,
  webdav;

  String get displayName => switch (this) {
        NetworkProtocol.smb => 'SMB / Windows Share',
        NetworkProtocol.ftp => 'FTP (File Transfer Protocol)',
        NetworkProtocol.sftp => 'SFTP (SSH File Transfer)',
        NetworkProtocol.webdav => 'WebDAV',
      };

  String get shortName => switch (this) {
        NetworkProtocol.smb => 'SMB',
        NetworkProtocol.ftp => 'FTP',
        NetworkProtocol.sftp => 'SFTP',
        NetworkProtocol.webdav => 'WebDAV',
      };

  int get defaultPort => switch (this) {
        NetworkProtocol.smb => 445,
        NetworkProtocol.ftp => 21,
        NetworkProtocol.sftp => 22,
        NetworkProtocol.webdav => 80,
      };

  String get uriScheme => switch (this) {
        NetworkProtocol.smb => 'smb',
        NetworkProtocol.ftp => 'ftp',
        NetworkProtocol.sftp => 'sftp',
        NetworkProtocol.webdav => 'webdav',
      };
}

/// Connection status of a remote network server.
enum ServerStatus {
  disconnected,
  connecting,
  connected,
  error;

  String get displayName => switch (this) {
        ServerStatus.disconnected => 'Disconnected',
        ServerStatus.connecting => 'Connecting...',
        ServerStatus.connected => 'Connected',
        ServerStatus.error => 'Connection Error',
      };
}

/// Configuration record for a remote network server.
class NetworkServerConfig {
  final String id;
  final String name;
  final NetworkProtocol protocol;
  final String host;
  final int port;
  final String path;
  final String username;
  final String password;
  final bool isAnonymous;
  final ServerStatus status;
  final String? lastError;
  final DateTime? lastConnectedAt;
  final Map<String, dynamic> customOptions;

  const NetworkServerConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.path = '/',
    this.username = '',
    this.password = '',
    this.isAnonymous = false,
    this.status = ServerStatus.disconnected,
    this.lastError,
    this.lastConnectedAt,
    this.customOptions = const {},
  });

  /// Generates a sanitized display URI (omitting sensitive credentials).
  String get displayUri {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '${protocol.uriScheme}://$host:$port$cleanPath';
  }

  NetworkServerConfig copyWith({
    String? id,
    String? name,
    NetworkProtocol? protocol,
    String? host,
    int? port,
    String? path,
    String? username,
    String? password,
    bool? isAnonymous,
    ServerStatus? status,
    String? lastError,
    DateTime? lastConnectedAt,
    Map<String, dynamic>? customOptions,
  }) {
    return NetworkServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      path: path ?? this.path,
      username: username ?? this.username,
      password: password ?? this.password,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      customOptions: customOptions ?? this.customOptions,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'host': host,
        'port': port,
        'path': path,
        'username': username,
        'password': password,
        'isAnonymous': isAnonymous,
        'status': status.name,
        'lastError': lastError,
        'lastConnectedAt': lastConnectedAt?.toIso8601String(),
        'customOptions': customOptions,
      };

  factory NetworkServerConfig.fromJson(Map<String, dynamic> json) {
    return NetworkServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      protocol: NetworkProtocol.values.firstWhere(
        (p) => p.name == json['protocol'],
        orElse: () => NetworkProtocol.webdav,
      ),
      host: json['host'] as String,
      port: (json['port'] as num?)?.toInt() ?? 80,
      path: (json['path'] as String?) ?? '/',
      username: (json['username'] as String?) ?? '',
      password: (json['password'] as String?) ?? '',
      isAnonymous: (json['isAnonymous'] as bool?) ?? false,
      status: ServerStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ServerStatus.disconnected,
      ),
      lastError: json['lastError'] as String?,
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.tryParse(json['lastConnectedAt'] as String)
          : null,
      customOptions: (json['customOptions'] as Map<String, dynamic>?) ?? {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkServerConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Represents a file or folder located on a remote network or cloud source.
class RemoteFileItem {
  final String id;
  final String name;
  final String remotePath;
  final int size;
  final bool isDirectory;
  final DateTime modifiedAt;
  final String? mimeType;
  final String sourceId;
  final String sourceType; // 'smb', 'ftp', 'sftp', 'webdav', 'googleDrive', etc.

  const RemoteFileItem({
    required this.id,
    required this.name,
    required this.remotePath,
    required this.size,
    required this.isDirectory,
    required this.modifiedAt,
    this.mimeType,
    required this.sourceId,
    required this.sourceType,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'remotePath': remotePath,
        'size': size,
        'isDirectory': isDirectory,
        'modifiedAt': modifiedAt.toIso8601String(),
        'mimeType': mimeType,
        'sourceId': sourceId,
        'sourceType': sourceType,
      };

  factory RemoteFileItem.fromJson(Map<String, dynamic> json) {
    return RemoteFileItem(
      id: json['id'] as String,
      name: json['name'] as String,
      remotePath: json['remotePath'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      isDirectory: (json['isDirectory'] as bool?) ?? false,
      modifiedAt: DateTime.tryParse(json['modifiedAt'] as String? ?? '') ??
          DateTime.now(),
      mimeType: json['mimeType'] as String?,
      sourceId: json['sourceId'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteFileItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          remotePath == other.remotePath;

  @override
  int get hashCode => id.hashCode ^ remotePath.hashCode;
}

/// Direction of file transfer.
enum TransferDirection { upload, download }

/// State of a network transfer operation.
enum TransferStatus {
  pending,
  transferring,
  paused,
  completed,
  failed,
  cancelled;

  String get displayName => switch (this) {
        TransferStatus.pending => 'Waiting in Queue',
        TransferStatus.transferring => 'Transferring...',
        TransferStatus.paused => 'Paused',
        TransferStatus.completed => 'Completed',
        TransferStatus.failed => 'Failed',
        TransferStatus.cancelled => 'Cancelled',
      };
}

/// Record representing an active, completed, or failed network transfer task.
class NetworkTransferTask {
  final String id;
  final String fileName;
  final TransferDirection direction;
  final NetworkProtocol? protocol;
  final String? cloudProvider;
  final String sourcePath;
  final String destinationPath;
  final int bytesTransferred;
  final int totalBytes;
  final TransferStatus status;
  final double speedBytesPerSec;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;

  const NetworkTransferTask({
    required this.id,
    required this.fileName,
    required this.direction,
    this.protocol,
    this.cloudProvider,
    required this.sourcePath,
    required this.destinationPath,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.status = TransferStatus.pending,
    this.speedBytesPerSec = 0.0,
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
  });

  double get progress =>
      totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0.0, 1.0) : 0.0;

  NetworkTransferTask copyWith({
    String? id,
    String? fileName,
    TransferDirection? direction,
    NetworkProtocol? protocol,
    String? cloudProvider,
    String? sourcePath,
    String? destinationPath,
    int? bytesTransferred,
    int? totalBytes,
    TransferStatus? status,
    double? speedBytesPerSec,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return NetworkTransferTask(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      direction: direction ?? this.direction,
      protocol: protocol ?? this.protocol,
      cloudProvider: cloudProvider ?? this.cloudProvider,
      sourcePath: sourcePath ?? this.sourcePath,
      destinationPath: destinationPath ?? this.destinationPath,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'direction': direction.name,
        'protocol': protocol?.name,
        'cloudProvider': cloudProvider,
        'sourcePath': sourcePath,
        'destinationPath': destinationPath,
        'bytesTransferred': bytesTransferred,
        'totalBytes': totalBytes,
        'status': status.name,
        'speedBytesPerSec': speedBytesPerSec,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory NetworkTransferTask.fromJson(Map<String, dynamic> json) {
    return NetworkTransferTask(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      direction: TransferDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => TransferDirection.download,
      ),
      protocol: json['protocol'] != null
          ? NetworkProtocol.values.firstWhere(
              (p) => p.name == json['protocol'],
              orElse: () => NetworkProtocol.webdav,
            )
          : null,
      cloudProvider: json['cloudProvider'] as String?,
      sourcePath: json['sourcePath'] as String,
      destinationPath: json['destinationPath'] as String,
      bytesTransferred: (json['bytesTransferred'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      status: TransferStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => TransferStatus.pending,
      ),
      speedBytesPerSec: (json['speedBytesPerSec'] as num?)?.toDouble() ?? 0.0,
      errorMessage: json['errorMessage'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkTransferTask &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// State of the local Wi-Fi / LAN web sharing server.
enum LanSessionStatus { stopped, starting, active, error }

/// Model representing the live LAN / Browser Transfer session.
class LanTransferSession {
  final LanSessionStatus status;
  final int port;
  final List<String> ipAddresses;
  final String accessPin;
  final int connectedClientsCount;
  final int filesSharedCount;
  final String? preferredUrl;
  final String? errorMessage;

  const LanTransferSession({
    this.status = LanSessionStatus.stopped,
    this.port = 8080,
    this.ipAddresses = const [],
    this.accessPin = '0000',
    this.connectedClientsCount = 0,
    this.filesSharedCount = 0,
    this.preferredUrl,
    this.errorMessage,
  });

  bool get isActive => status == LanSessionStatus.active;

  /// Returns the primary display URL for browser pairing (e.g. http://192.168.1.50:8080).
  String get displayUrl {
    if (preferredUrl != null && preferredUrl!.isNotEmpty) return preferredUrl!;
    if (ipAddresses.isNotEmpty) {
      return 'http://${ipAddresses.first}:$port';
    }
    return 'http://localhost:$port';
  }

  /// Pairing QR code payload data (URL + PIN).
  String get qrPairingPayload => jsonEncode({
        'url': displayUrl,
        'pin': accessPin,
        'app': 'FileZen',
        'type': 'lan_share',
      });

  LanTransferSession copyWith({
    LanSessionStatus? status,
    int? port,
    List<String>? ipAddresses,
    String? accessPin,
    int? connectedClientsCount,
    int? filesSharedCount,
    String? preferredUrl,
    String? errorMessage,
  }) {
    return LanTransferSession(
      status: status ?? this.status,
      port: port ?? this.port,
      ipAddresses: ipAddresses ?? this.ipAddresses,
      accessPin: accessPin ?? this.accessPin,
      connectedClientsCount:
          connectedClientsCount ?? this.connectedClientsCount,
      filesSharedCount: filesSharedCount ?? this.filesSharedCount,
      preferredUrl: preferredUrl ?? this.preferredUrl,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
