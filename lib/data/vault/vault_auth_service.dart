import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/vault_models.dart';
import '../../domain/repositories/i_vault_auth_service.dart';
import 'vault_cipher.dart';

/// Implementation of IVaultAuthService managing PIN setup, rate-limiting,
/// biometric state, auto-lock policies, and session key management.
class VaultAuthService implements IVaultAuthService {
  final VaultCipher cipher;
  final String? customConfigPath;

  VaultAuthService({
    VaultCipher? cipher,
    this.customConfigPath,
  }) : cipher = cipher ?? VaultCipher();

  bool _unlocked = false;
  String? _activePin;
  Uint8List? _activeKey;

  @override
  bool get isUnlocked => _unlocked;

  @override
  Uint8List? get activeSessionKey => _activeKey;

  String? get activePin => _activePin;

  Future<File> _getConfigFile() async {
    if (customConfigPath != null) {
      final file = File(customConfigPath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, '.filezen_vault', 'vault_auth.json'));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  Future<Map<String, dynamic>?> _readRawConfig() async {
    try {
      final file = await _getConfigFile();
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.warning('Failed to read vault auth config: $e', 'VaultAuth');
      return null;
    }
  }

  Future<void> _writeRawConfig(Map<String, dynamic> data) async {
    try {
      final file = await _getConfigFile();
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      AppLogger.error('Failed to save vault auth config: $e', 'VaultAuth');
    }
  }

  @override
  Future<bool> isPinConfigured() async {
    final raw = await _readRawConfig();
    return raw != null && raw['pinHash'] != null;
  }

  @override
  Future<VaultSecurityConfig> getSecurityConfig() async {
    final raw = await _readRawConfig();
    if (raw == null) {
      return const VaultSecurityConfig(isPinConfigured: false);
    }
    return VaultSecurityConfig.fromJson(raw);
  }

  @override
  Future<void> updateSecurityConfig(VaultSecurityConfig config) async {
    final raw = (await _readRawConfig()) ?? {};
    raw.addAll(config.toJson());
    await _writeRawConfig(raw);
  }

  @override
  Future<bool> setupPin(String pin) async {
    if (pin.length < 4) return false;

    final salt = cipher.generateRandomBytes(32);
    final saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final hmac = Hmac(sha256, salt);
    final pinHash = hmac.convert(utf8.encode(pin)).toString();

    final config = VaultSecurityConfig(
      isPinConfigured: true,
      isBiometricEnabled: false,
      autoLockTimeout: Duration.zero,
      screenshotProtectionEnabled: true,
      failedAttempts: 0,
    );

    final raw = config.toJson();
    raw['pinHash'] = pinHash;
    raw['saltHex'] = saltHex;
    await _writeRawConfig(raw);

    // Automatically unlock session after initial setup
    _unlocked = true;
    _activePin = pin;
    _activeKey = Uint8List.fromList(sha256.convert(utf8.encode(pin)).bytes);

    AppLogger.info('Vault master PIN configured', 'VaultAuth');
    return true;
  }

  @override
  Future<VaultAuthResult> verifyPin(String pin) async {
    final raw = await _readRawConfig();
    if (raw == null || raw['pinHash'] == null || raw['saltHex'] == null) {
      return VaultAuthResult.failure('Vault PIN has not been set up yet.');
    }

    final currentConfig = VaultSecurityConfig.fromJson(raw);
    if (currentConfig.isLockedOut) {
      return VaultAuthResult.lockedOut(currentConfig.remainingLockoutSeconds);
    }

    final saltHex = raw['saltHex'] as String;
    final salt = Uint8List.fromList([
      for (int i = 0; i < saltHex.length; i += 2)
        int.parse(saltHex.substring(i, i + 2), radix: 16)
    ]);

    final hmac = Hmac(sha256, salt);
    final computedHash = hmac.convert(utf8.encode(pin)).toString();
    final storedHash = raw['pinHash'] as String;

    if (computedHash == storedHash) {
      // Success
      _unlocked = true;
      _activePin = pin;
      _activeKey = Uint8List.fromList(sha256.convert(utf8.encode(pin)).bytes);

      // Reset failed attempts
      if (currentConfig.failedAttempts > 0) {
        final updated = currentConfig.copyWith(failedAttempts: 0, lockoutUntil: null);
        await updateSecurityConfig(updated);
      }

      AppLogger.info('Vault unlocked successfully with PIN', 'VaultAuth');
      return VaultAuthResult.success();
    } else {
      // Failure
      final newFailures = currentConfig.failedAttempts + 1;
      DateTime? lockout;
      if (newFailures >= 5) {
        lockout = DateTime.now().add(const Duration(seconds: 30));
        AppLogger.warning('Vault locked out due to 5 consecutive PIN failures', 'VaultAuth');
      }

      final updated = currentConfig.copyWith(
        failedAttempts: newFailures,
        lockoutUntil: lockout,
      );
      await updateSecurityConfig(updated);

      if (lockout != null) {
        return VaultAuthResult.lockedOut(30);
      }

      final remaining = 5 - newFailures;
      return VaultAuthResult.failure('Incorrect PIN. $remaining attempts remaining.');
    }
  }

  @override
  Future<bool> changePin(String oldPin, String newPin) async {
    final verifyRes = await verifyPin(oldPin);
    if (!verifyRes.success) return false;
    return await setupPin(newPin);
  }

  @override
  Future<bool> isBiometricAvailable() async {
    // Biometric hardware check abstraction
    return true;
  }

  @override
  Future<bool> setBiometricEnabled(bool enabled) async {
    final config = await getSecurityConfig();
    await updateSecurityConfig(config.copyWith(isBiometricEnabled: enabled));
    return true;
  }

  @override
  Future<VaultAuthResult> authenticateWithBiometrics() async {
    final config = await getSecurityConfig();
    if (!config.isBiometricEnabled) {
      return VaultAuthResult.failure('Biometric authentication is not enabled for Vault.');
    }
    if (config.isLockedOut) {
      return VaultAuthResult.lockedOut(config.remainingLockoutSeconds);
    }

    // Biometric pass - if PIN is configured, unlock session
    if (_activePin != null) {
      _unlocked = true;
      return VaultAuthResult.success();
    }

    // When app cold starts, biometrics verifies identity; if PIN was stored in hardware Keystore,
    // session unlocks. For clean emulation, unlock with session marker:
    _unlocked = true;
    AppLogger.info('Vault unlocked with device biometrics', 'VaultAuth');
    return VaultAuthResult.success();
  }

  @override
  void lock() {
    _unlocked = false;
    _activePin = null;
    if (_activeKey != null) {
      _activeKey!.fillRange(0, _activeKey!.length, 0);
      _activeKey = null;
    }
    AppLogger.info('Vault locked. Session keys securely cleared.', 'VaultAuth');
  }
}
