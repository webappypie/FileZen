/// Supported cloud file storage providers in FileZen.
enum CloudProviderType {
  googleDrive,
  oneDrive,
  dropbox,
  box;

  String get displayName => switch (this) {
        CloudProviderType.googleDrive => 'Google Drive',
        CloudProviderType.oneDrive => 'Microsoft OneDrive',
        CloudProviderType.dropbox => 'Dropbox',
        CloudProviderType.box => 'Box',
      };

  String get shortName => switch (this) {
        CloudProviderType.googleDrive => 'Drive',
        CloudProviderType.oneDrive => 'OneDrive',
        CloudProviderType.dropbox => 'Dropbox',
        CloudProviderType.box => 'Box',
      };

  String get iconKey => switch (this) {
        CloudProviderType.googleDrive => 'google_drive',
        CloudProviderType.oneDrive => 'onedrive',
        CloudProviderType.dropbox => 'dropbox',
        CloudProviderType.box => 'box',
      };
}

/// Represents a connected or saved cloud storage account.
class CloudAccount {
  final String id;
  final CloudProviderType provider;
  final String accountEmail;
  final String displayName;
  final bool isConnected;
  final int totalStorageBytes;
  final int usedStorageBytes;
  final DateTime? lastSyncedAt;
  final String? lastError;
  final Map<String, dynamic> metadata;

  const CloudAccount({
    required this.id,
    required this.provider,
    required this.accountEmail,
    required this.displayName,
    this.isConnected = true,
    this.totalStorageBytes = 15 * 1024 * 1024 * 1024, // 15 GB default
    this.usedStorageBytes = 0,
    this.lastSyncedAt,
    this.lastError,
    this.metadata = const {},
  });

  double get usedPercentage => totalStorageBytes > 0
      ? (usedStorageBytes / totalStorageBytes).clamp(0.0, 1.0)
      : 0.0;

  int get freeStorageBytes =>
      (totalStorageBytes - usedStorageBytes).clamp(0, totalStorageBytes);

  CloudAccount copyWith({
    String? id,
    CloudProviderType? provider,
    String? accountEmail,
    String? displayName,
    bool? isConnected,
    int? totalStorageBytes,
    int? usedStorageBytes,
    DateTime? lastSyncedAt,
    String? lastError,
    Map<String, dynamic>? metadata,
  }) {
    return CloudAccount(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      accountEmail: accountEmail ?? this.accountEmail,
      displayName: displayName ?? this.displayName,
      isConnected: isConnected ?? this.isConnected,
      totalStorageBytes: totalStorageBytes ?? this.totalStorageBytes,
      usedStorageBytes: usedStorageBytes ?? this.usedStorageBytes,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: lastError ?? this.lastError,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider.name,
        'accountEmail': accountEmail,
        'displayName': displayName,
        'isConnected': isConnected,
        'totalStorageBytes': totalStorageBytes,
        'usedStorageBytes': usedStorageBytes,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'lastError': lastError,
        'metadata': metadata,
      };

  factory CloudAccount.fromJson(Map<String, dynamic> json) {
    return CloudAccount(
      id: json['id'] as String,
      provider: CloudProviderType.values.firstWhere(
        (p) => p.name == json['provider'],
        orElse: () => CloudProviderType.googleDrive,
      ),
      accountEmail: json['accountEmail'] as String,
      displayName: json['displayName'] as String,
      isConnected: (json['isConnected'] as bool?) ?? true,
      totalStorageBytes: (json['totalStorageBytes'] as num?)?.toInt() ??
          15 * 1024 * 1024 * 1024,
      usedStorageBytes: (json['usedStorageBytes'] as num?)?.toInt() ?? 0,
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.tryParse(json['lastSyncedAt'] as String)
          : null,
      lastError: json['lastError'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudAccount &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
