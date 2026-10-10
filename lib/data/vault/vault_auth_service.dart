import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/vault_models.dart';
import '../../domain/repositories/i_vault_auth_service.dart';
import 'vault_biometric_gate.dart';
import 'vault_cipher.dart';
import 'vault_crypto_backend.dart';
import 'vault_file_io.dart';

/// Vault authentication and key management.
///
/// Key hierarchy (see docs/03_Architecture/DECISION_LOG_ISSUE_7_VAULT_SECURITY.md):
///  * A random 256-bit **master key** encrypts all vault content and metadata.
///  * PIN path: `KEK = PBKDF2-HMAC-SHA256(PIN, salt)` wraps the master key with
///    AES-256-GCM; that blob is wrapped again by a hardware-backed Android
///    Keystore key, so the PIN cannot be brute-forced from copied app data.
///  * Biometric path: the master key is wrapped by a Keystore key that the
///    Keystore only releases after a recent system biometric/credential prompt.
///  * Neither the PIN nor the master key is ever written to disk in the clear,
///    and changing the PIN re-wraps the master key without touching vault files.
class VaultAuthService implements IVaultAuthService {
  static const int pinIterations = 210000;
  static const int minPinLength = 4;
  static const int maxFailedAttempts = 5;
  static const int lockoutSeconds = 30;
  static const int configVersion = 2;

  static final Uint8List _masterKeyAad =
      Uint8List.fromList(utf8.encode('zenvault-master-key-v2'));

  final VaultCipher cipher;
  final VaultCryptoBackend backend;
  final VaultBiometricGate biometricGate;
  final String? customConfigPath;

  VaultAuthService({
    VaultCipher? cipher,
    VaultCryptoBackend? backend,
    VaultBiometricGate? biometricGate,
    this.customConfigPath,
  })  : cipher = cipher ?? VaultCipher(),
        backend = backend ?? const MethodChannelVaultCryptoBackend(),
        biometricGate = biometricGate ?? LocalAuthVaultBiometricGate();

  bool _unlocked = false;
  Uint8List? _masterKey;
  Uint8List? _legacyKey;

  @override
  bool get isUnlocked => _unlocked && _masterKey != null;

  /// The 256-bit master key while the vault is unlocked, otherwise null.
  @override
  Uint8List? get activeSessionKey => isUnlocked ? _masterKey : null;

  /// Key protecting pre-v2 containers (the old PIN-derived key). Present only
  /// between a legacy PIN unlock and [completeLegacyMigration].
  Uint8List? get pendingLegacyKey => _legacyKey;

  // ---------------------------------------------------------------------------
  // Config persistence
  // ---------------------------------------------------------------------------

  Future<File> _getConfigFile() async {
    if (customConfigPath != null) {
      return File(customConfigPath!);
    }
    final docsDir = await getApplicationDocumentsDirectory();
    return File(p.join(docsDir.path, '.filezen_vault', 'vault_auth.json'));
  }

  /// Returns null when no vault is configured. A present-but-unreadable config
  /// is reported as `{'_corrupt': true}` so it can never be mistaken for
  /// "not configured" and silently replaced by a new PIN (which would orphan
  /// every vaulted file).
  Future<Map<String, dynamic>?> _readRawConfig() async {
    final file = await _getConfigFile();
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) return {'_corrupt': true};
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return {'_corrupt': true};
      return decoded;
    } catch (e) {
      AppLogger.error('Vault auth config is unreadable: $e', 'VaultAuth');
      return {'_corrupt': true};
    }
  }

  Future<void> _writeRawConfig(Map<String, dynamic> data) async {
    final file = await _getConfigFile();
    await atomicWriteBytes(file, utf8.encode(jsonEncode(data)));
  }

  bool _isCorrupt(Map<String, dynamic>? raw) => raw != null && raw['_corrupt'] == true;

  bool _isLegacy(Map<String, dynamic> raw) =>
      raw['wrappedKey'] == null && raw['pinHash'] != null && raw['saltHex'] != null;

  static Uint8List _unb64(Object? value) => Uint8List.fromList(base64Decode(value as String));

  @override
  Future<bool> isPinConfigured() async {
    final raw = await _readRawConfig();
    if (raw == null) return false;
    if (_isCorrupt(raw)) return true;
    return raw['wrappedKey'] != null || raw['pinHash'] != null;
  }

  @override
  Future<VaultSecurityConfig> getSecurityConfig() async {
    final raw = await _readRawConfig();
    if (raw == null) {
      return const VaultSecurityConfig(isPinConfigured: false);
    }
    if (_isCorrupt(raw)) {
      return const VaultSecurityConfig(isPinConfigured: true);
    }
    return VaultSecurityConfig.fromJson(raw);
  }

  @override
  Future<void> updateSecurityConfig(VaultSecurityConfig config) async {
    final raw = await _readRawConfig() ?? <String, dynamic>{};
    if (_isCorrupt(raw)) {
      throw StateError('Vault configuration is damaged; refusing to overwrite it.');
    }
    final json = config.toJson();
    // Key-material fields are owned by this service, never by callers.
    raw.addAll(json);
    await _writeRawConfig(raw);
  }

  // ---------------------------------------------------------------------------
  // Key wrapping
  // ---------------------------------------------------------------------------

  Uint8List _pinBytes(String pin) => Uint8List.fromList(utf8.encode(pin));

  void _zero(Uint8List? bytes) => bytes?.fillRange(0, bytes.length, 0);

  Future<Uint8List> _deriveKek(String pin, Uint8List salt, int iterations) {
    return backend.pbkdf2(
      password: _pinBytes(pin),
      salt: salt,
      iterations: iterations,
      length: 32,
    );
  }

  /// `keystoreWrap(device, AES-GCM(KEK(pin), masterKey))`.
  Future<Uint8List> _wrapMasterKey(
    String pin,
    Uint8List salt,
    int iterations,
    Uint8List masterKey,
  ) async {
    final kek = await _deriveKek(pin, salt, iterations);
    try {
      final inner = await backend.gcmEncrypt(key: kek, data: masterKey, aad: _masterKeyAad);
      return await backend.keystoreWrap(VaultKeySlot.device, inner);
    } finally {
      _zero(kek);
    }
  }

  Future<Uint8List> _unwrapMasterKey(String pin, Map<String, dynamic> raw) async {
    final kdf = raw['kdf'] as Map<String, dynamic>;
    final salt = _unb64(kdf['salt']);
    final iterations = kdf['iterations'] as int;
    final inner = await backend.keystoreUnwrap(VaultKeySlot.device, _unb64(raw['wrappedKey']));
    final kek = await _deriveKek(pin, salt, iterations);
    try {
      return await backend.gcmDecrypt(key: kek, data: inner, aad: _masterKeyAad);
    } finally {
      _zero(kek);
    }
  }

  Map<String, dynamic> _kdfJson(Uint8List salt, int iterations) => {
        'alg': 'PBKDF2-HMAC-SHA256',
        'iterations': iterations,
        'salt': base64Encode(salt),
      };

  // ---------------------------------------------------------------------------
  // PIN setup / verification
  // ---------------------------------------------------------------------------

  @override
  Future<bool> setupPin(String pin) async {
    if (pin.length < minPinLength) return false;
    // Never overwrite an existing vault: that would orphan its files.
    if (await isPinConfigured()) {
      AppLogger.warning('Refused to set up a PIN: vault is already configured', 'VaultAuth');
      return false;
    }

    final salt = cipher.generateRandomBytes(32);
    final masterKey = cipher.generateRandomBytes(32);
    try {
      final wrapped = await _wrapMasterKey(pin, salt, pinIterations, masterKey);

      final raw = const VaultSecurityConfig(
        isPinConfigured: true,
        isBiometricEnabled: false,
        autoLockTimeout: Duration.zero,
        screenshotProtectionEnabled: true,
        failedAttempts: 0,
      ).toJson();
      raw['version'] = configVersion;
      raw['kdf'] = _kdfJson(salt, pinIterations);
      raw['wrappedKey'] = base64Encode(wrapped);
      await _writeRawConfig(raw);

      _setSession(masterKey);
      AppLogger.info('Vault master PIN configured', 'VaultAuth');
      return true;
    } catch (e) {
      _zero(masterKey);
      AppLogger.error('Vault PIN setup failed: $e', 'VaultAuth');
      return false;
    }
  }

  void _setSession(Uint8List masterKey) {
    _zero(_masterKey);
    _masterKey = masterKey;
    _unlocked = true;
  }

  @override
  Future<VaultAuthResult> verifyPin(String pin) async {
    final raw = await _readRawConfig();
    if (raw == null) {
      return VaultAuthResult.failure('Vault PIN has not been set up yet.');
    }
    if (_isCorrupt(raw)) {
      return VaultAuthResult.failure(
        'Vault configuration is damaged and cannot be read. Your files have not been modified.',
      );
    }
    if (raw['wrappedKey'] == null && raw['pinHash'] == null) {
      return VaultAuthResult.failure('Vault PIN has not been set up yet.');
    }

    final currentConfig = VaultSecurityConfig.fromJson(raw);
    if (currentConfig.isLockedOut) {
      return VaultAuthResult.lockedOut(currentConfig.remainingLockoutSeconds);
    }

    Uint8List? masterKey;
    var legacyUpgrade = false;
    try {
      if (_isLegacy(raw)) {
        masterKey = await _verifyLegacyPinAndUpgrade(pin, raw);
        legacyUpgrade = masterKey != null;
      } else {
        masterKey = await _unwrapMasterKey(pin, raw);
      }
    } on VaultCryptoException catch (e) {
      if (e.code != VaultCryptoException.authFailed) {
        // Keystore/platform trouble is not a wrong PIN: do not count an attempt.
        AppLogger.error('Vault unlock failed (${e.code})', 'VaultAuth');
        return VaultAuthResult.failure(_cryptoFailureMessage(e));
      }
    } on FormatException catch (e) {
      AppLogger.error('Vault config malformed: $e', 'VaultAuth');
      return VaultAuthResult.failure('Vault configuration is damaged and cannot be read.');
    } catch (e) {
      AppLogger.error('Vault unlock failed: ${e.runtimeType}', 'VaultAuth');
      return VaultAuthResult.failure('Unable to unlock the vault on this device.');
    }

    if (masterKey == null) {
      return _recordFailedAttempt(currentConfig);
    }

    _setSession(masterKey);
    if (!legacyUpgrade && raw['legacyMigrationPending'] == true) {
      // An earlier upgrade was interrupted; the old container key is the PIN.
      _zero(_legacyKey);
      _legacyKey = _pinBytes(pin);
    }

    if (currentConfig.failedAttempts > 0) {
      await _writeRawConfig(
        (await _readRawConfig() ?? raw)
          ..['failedAttempts'] = 0
          ..['lockoutUntil'] = null,
      );
    }

    AppLogger.info('Vault unlocked successfully with PIN', 'VaultAuth');
    return VaultAuthResult.success();
  }

  String _cryptoFailureMessage(VaultCryptoException e) {
    switch (e.code) {
      case VaultCryptoException.keyMissing:
      case VaultCryptoException.keyInvalidated:
        return 'The device security key for this vault is no longer available.';
      case VaultCryptoException.unavailable:
        return 'Secure vault storage is not available on this device.';
      default:
        return 'Unable to unlock the vault on this device.';
    }
  }

  Future<VaultAuthResult> _recordFailedAttempt(VaultSecurityConfig current) async {
    final newFailures = current.failedAttempts + 1;
    DateTime? lockout;
    if (newFailures >= maxFailedAttempts) {
      lockout = DateTime.now().add(const Duration(seconds: lockoutSeconds));
      AppLogger.warning('Vault locked out after repeated PIN failures', 'VaultAuth');
    }

    final raw = await _readRawConfig() ?? <String, dynamic>{};
    raw['failedAttempts'] = newFailures;
    raw['lockoutUntil'] = lockout?.toIso8601String();
    await _writeRawConfig(raw);

    if (lockout != null) {
      return VaultAuthResult.lockedOut(lockoutSeconds);
    }
    final remaining = maxFailedAttempts - newFailures;
    return VaultAuthResult.failure('Incorrect PIN. $remaining attempts remaining.');
  }

  // ---------------------------------------------------------------------------
  // Legacy (pre-v2) upgrade
  // ---------------------------------------------------------------------------

  /// Verifies a PIN against the old `HMAC(salt, pin)` verifier and, on success,
  /// upgrades the config to the v2 key hierarchy. Returns the new master key,
  /// or null when the PIN is wrong.
  ///
  /// The insecure legacy fields (`pinHash`, `saltHex`, and `biometricToken`,
  /// which was the PIN XOR-masked with a key derivable from the salt) are
  /// removed. Biometric unlock is switched off and must be re-enabled.
  Future<Uint8List?> _verifyLegacyPinAndUpgrade(String pin, Map<String, dynamic> raw) async {
    final saltHex = raw['saltHex'] as String;
    final legacySalt = Uint8List.fromList([
      for (int i = 0; i < saltHex.length; i += 2) int.parse(saltHex.substring(i, i + 2), radix: 16)
    ]);
    final computed = Hmac(sha256, legacySalt).convert(utf8.encode(pin)).toString();
    if (!VaultCipher.constantTimeEquals(utf8.encode(computed), utf8.encode(raw['pinHash'] as String))) {
      return null;
    }

    final salt = cipher.generateRandomBytes(32);
    final masterKey = cipher.generateRandomBytes(32);
    final wrapped = await _wrapMasterKey(pin, salt, pinIterations, masterKey);

    final upgraded = Map<String, dynamic>.from(raw)
      ..remove('pinHash')
      ..remove('saltHex')
      ..remove('biometricToken')
      ..['isBiometricEnabled'] = false
      ..['version'] = configVersion
      ..['kdf'] = _kdfJson(salt, pinIterations)
      ..['wrappedKey'] = base64Encode(wrapped)
      ..['legacyMigrationPending'] = true;
    await _writeRawConfig(upgraded);

    _zero(_legacyKey);
    _legacyKey = _pinBytes(pin);
    AppLogger.info('Vault configuration upgraded to v2 key hierarchy', 'VaultAuth');
    return masterKey;
  }

  /// Called by the storage service once every legacy container has been
  /// re-encrypted; drops the legacy key and the pending flag.
  Future<void> completeLegacyMigration() async {
    _zero(_legacyKey);
    _legacyKey = null;
    final raw = await _readRawConfig();
    if (raw != null && !_isCorrupt(raw) && raw.remove('legacyMigrationPending') != null) {
      await _writeRawConfig(raw);
    }
  }

  // ---------------------------------------------------------------------------
  // PIN change
  // ---------------------------------------------------------------------------

  @override
  Future<bool> changePin(String oldPin, String newPin) async {
    if (newPin.length < minPinLength) return false;
    final verified = await verifyPin(oldPin);
    final masterKey = _masterKey;
    if (!verified.success || masterKey == null) return false;
    // Legacy containers are keyed by the old PIN; re-wrapping now would strand them.
    if (_legacyKey != null) return false;

    try {
      final raw = await _readRawConfig();
      if (raw == null || _isCorrupt(raw)) return false;
      final salt = cipher.generateRandomBytes(32);
      final wrapped = await _wrapMasterKey(newPin, salt, pinIterations, masterKey);
      raw['kdf'] = _kdfJson(salt, pinIterations);
      raw['wrappedKey'] = base64Encode(wrapped);
      await _writeRawConfig(raw);
      AppLogger.info('Vault master PIN changed', 'VaultAuth');
      return true;
    } catch (e) {
      AppLogger.error('Vault PIN change failed: ${e.runtimeType}', 'VaultAuth');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Biometrics
  // ---------------------------------------------------------------------------

  static const String _biometricReason = 'Authenticate to unlock FileZen Vault';

  @override
  Future<bool> isBiometricAvailable() => biometricGate.isAvailable();

  @override
  Future<bool> setBiometricEnabled(bool enabled) async {
    if (!enabled) {
      await _disableBiometric();
      return true;
    }

    final masterKey = _masterKey;
    if (!isUnlocked || masterKey == null) return false;
    if (!await biometricGate.isAvailable()) return false;
    // Prove presence now; the Keystore additionally requires this fresh
    // authentication before it will wrap/unwrap with the biometric key.
    if (!await _authenticateBiometric()) return false;

    try {
      final blob = await backend.keystoreWrap(VaultKeySlot.biometric, masterKey);
      final raw = await _readRawConfig();
      if (raw == null || _isCorrupt(raw)) return false;
      raw['bioWrappedKey'] = base64Encode(blob);
      raw['isBiometricEnabled'] = true;
      await _writeRawConfig(raw);
      return true;
    } on VaultCryptoException catch (e) {
      AppLogger.warning('Could not enable biometric unlock (${e.code})', 'VaultAuth');
      return false;
    } catch (e) {
      AppLogger.warning('Could not enable biometric unlock: ${e.runtimeType}', 'VaultAuth');
      return false;
    }
  }

  /// Fail closed: only an explicit `true` counts; any throw is a failure.
  Future<bool> _authenticateBiometric() async {
    try {
      return await biometricGate.authenticate(_biometricReason) == true;
    } catch (e) {
      AppLogger.warning('Biometric prompt error: ${e.runtimeType}', 'VaultAuth');
      return false;
    }
  }

  Future<void> _disableBiometric() async {
    try {
      await backend.keystoreDelete(VaultKeySlot.biometric);
    } catch (e) {
      AppLogger.warning('Could not delete biometric key: ${e.runtimeType}', 'VaultAuth');
    }
    final raw = await _readRawConfig();
    if (raw == null || _isCorrupt(raw)) return;
    raw.remove('bioWrappedKey');
    raw['isBiometricEnabled'] = false;
    await _writeRawConfig(raw);
  }

  @override
  Future<VaultAuthResult> authenticateWithBiometrics() async {
    final raw = await _readRawConfig();
    if (raw == null || _isCorrupt(raw)) {
      return VaultAuthResult.failure('Biometric authentication is not enabled for Vault.');
    }
    final config = VaultSecurityConfig.fromJson(raw);
    if (!config.isBiometricEnabled) {
      return VaultAuthResult.failure('Biometric authentication is not enabled for Vault.');
    }
    if (config.isLockedOut) {
      return VaultAuthResult.lockedOut(config.remainingLockoutSeconds);
    }
    if (raw['bioWrappedKey'] == null) {
      await _disableBiometric();
      return VaultAuthResult.failure('Biometric unlock needs to be set up again. Unlock with your PIN.');
    }
    if (!await biometricGate.isAvailable()) {
      return VaultAuthResult.failure('Biometric authentication is unavailable on this device.');
    }

    final authenticated = await _authenticateBiometric();
    if (!authenticated) {
      return VaultAuthResult.failure('Authentication was canceled or failed.');
    }

    try {
      final masterKey = await backend.keystoreUnwrap(
        VaultKeySlot.biometric,
        _unb64(raw['bioWrappedKey']),
      );
      _setSession(masterKey);
      AppLogger.info('Vault unlocked with device biometrics/credentials', 'VaultAuth');
      return VaultAuthResult.success();
    } on VaultCryptoException catch (e) {
      switch (e.code) {
        case VaultCryptoException.keyInvalidated:
        case VaultCryptoException.keyMissing:
          await _disableBiometric();
          return VaultAuthResult.failure(
            'Biometric settings changed on this device. Unlock with your PIN, then re-enable biometric unlock.',
          );
        case VaultCryptoException.authRequired:
          return VaultAuthResult.failure('Biometric verification expired. Please try again.');
        default:
          AppLogger.error('Biometric unlock failed (${e.code})', 'VaultAuth');
          return VaultAuthResult.failure('Biometric unlock failed. Use your PIN instead.');
      }
    } catch (e) {
      AppLogger.error('Biometric unlock failed: ${e.runtimeType}', 'VaultAuth');
      return VaultAuthResult.failure('Biometric unlock failed. Use your PIN instead.');
    }
  }

  // ---------------------------------------------------------------------------
  // Lock
  // ---------------------------------------------------------------------------

  @override
  void lock() {
    _unlocked = false;
    _zero(_masterKey);
    _masterKey = null;
    _zero(_legacyKey);
    _legacyKey = null;
    AppLogger.info('Vault locked. Session keys securely cleared.', 'VaultAuth');
  }
}
