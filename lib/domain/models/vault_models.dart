import 'file_category.dart';

/// Configuration and security policy for FileZen Vault.
class VaultSecurityConfig {
  final bool isPinConfigured;
  final bool isBiometricEnabled;
  final Duration autoLockTimeout;
  final bool screenshotProtectionEnabled;
  final int failedAttempts;
  final DateTime? lockoutUntil;

  const VaultSecurityConfig({
    this.isPinConfigured = false,
    this.isBiometricEnabled = false,
    this.autoLockTimeout = Duration.zero,
    this.screenshotProtectionEnabled = true,
    this.failedAttempts = 0,
    this.lockoutUntil,
  });

  bool get isLockedOut =>
      lockoutUntil != null && DateTime.now().isBefore(lockoutUntil!);

  int get remainingLockoutSeconds => isLockedOut
      ? lockoutUntil!.difference(DateTime.now()).inSeconds.clamp(0, 300)
      : 0;

  VaultSecurityConfig copyWith({
    bool? isPinConfigured,
    bool? isBiometricEnabled,
    Duration? autoLockTimeout,
    bool? screenshotProtectionEnabled,
    int? failedAttempts,
    DateTime? lockoutUntil,
  }) {
    return VaultSecurityConfig(
      isPinConfigured: isPinConfigured ?? this.isPinConfigured,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      autoLockTimeout: autoLockTimeout ?? this.autoLockTimeout,
      screenshotProtectionEnabled:
          screenshotProtectionEnabled ?? this.screenshotProtectionEnabled,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntil: lockoutUntil ?? this.lockoutUntil,
    );
  }

  Map<String, dynamic> toJson() => {
        'isPinConfigured': isPinConfigured,
        'isBiometricEnabled': isBiometricEnabled,
        'autoLockTimeoutMs': autoLockTimeout.inMilliseconds,
        'screenshotProtectionEnabled': screenshotProtectionEnabled,
        'failedAttempts': failedAttempts,
        'lockoutUntil': lockoutUntil?.toIso8601String(),
      };

  factory VaultSecurityConfig.fromJson(Map<String, dynamic> json) =>
      VaultSecurityConfig(
        isPinConfigured: json['isPinConfigured'] as bool? ?? false,
        isBiometricEnabled: json['isBiometricEnabled'] as bool? ?? false,
        autoLockTimeout: Duration(
          milliseconds: json['autoLockTimeoutMs'] as int? ?? 0,
        ),
        screenshotProtectionEnabled:
            json['screenshotProtectionEnabled'] as bool? ?? true,
        failedAttempts: json['failedAttempts'] as int? ?? 0,
        lockoutUntil: json['lockoutUntil'] != null
            ? DateTime.tryParse(json['lockoutUntil'] as String)
            : null,
      );
}

/// Metadata describing an encrypted file stored within the Vault.
class VaultItem {
  final String id;
  final String vaultPath;
  final String originalFileName;
  final String originalPath;
  final int fileSize;
  final int encryptedSize;
  final FileCategory category;
  final String? mimeType;
  final DateTime encryptedAt;

  const VaultItem({
    required this.id,
    required this.vaultPath,
    required this.originalFileName,
    required this.originalPath,
    required this.fileSize,
    required this.encryptedSize,
    required this.category,
    this.mimeType,
    required this.encryptedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'vaultPath': vaultPath,
        'originalFileName': originalFileName,
        'originalPath': originalPath,
        'fileSize': fileSize,
        'encryptedSize': encryptedSize,
        'category': category.name,
        'mimeType': mimeType,
        'encryptedAt': encryptedAt.toIso8601String(),
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) => VaultItem(
        id: json['id'] as String,
        vaultPath: json['vaultPath'] as String,
        originalFileName: json['originalFileName'] as String,
        originalPath: json['originalPath'] as String,
        fileSize: json['fileSize'] as int,
        encryptedSize: json['encryptedSize'] as int,
        category: FileCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => FileCategory.other,
        ),
        mimeType: json['mimeType'] as String?,
        encryptedAt: DateTime.parse(json['encryptedAt'] as String),
      );
}

/// Result of an authentication attempt.
class VaultAuthResult {
  final bool success;
  final bool isLockedOut;
  final int cooldownRemainingSeconds;
  final String? errorMessage;

  const VaultAuthResult({
    required this.success,
    this.isLockedOut = false,
    this.cooldownRemainingSeconds = 0,
    this.errorMessage,
  });

  factory VaultAuthResult.success() => const VaultAuthResult(success: true);

  factory VaultAuthResult.failure(String message) => VaultAuthResult(
        success: false,
        errorMessage: message,
      );

  factory VaultAuthResult.lockedOut(int seconds) => VaultAuthResult(
        success: false,
        isLockedOut: true,
        cooldownRemainingSeconds: seconds,
        errorMessage:
            'Too many failed attempts. Locked out for $seconds seconds.',
      );
}
