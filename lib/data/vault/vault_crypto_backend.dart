
import 'package:flutter/services.dart';

/// Keystore-backed wrapping slots (see android `VaultKeystore`).
enum VaultKeySlot {
  /// Hardware-backed key bound to this device; no user authentication required.
  device,

  /// Key the Android Keystore only releases shortly after a successful
  /// biometric / device-credential authentication.
  biometric,
}

/// Failure reported by the native vault crypto layer.
class VaultCryptoException implements Exception {
  /// Authentication tag mismatch: wrong key/PIN or tampered data.
  static const authFailed = 'AUTH_FAILED';

  /// Keystore key is missing (reset, restored to another device, deleted).
  static const keyMissing = 'KEY_MISSING';

  /// Keystore key was invalidated (for example biometric enrollment changed).
  static const keyInvalidated = 'KEY_INVALIDATED';

  /// Keystore requires a fresh user authentication.
  static const authRequired = 'AUTH_REQUIRED';

  /// The device has no secure lock screen, so auth-bound keys cannot be created.
  static const noSecureLock = 'NO_SECURE_LOCK';

  /// Native crypto layer is not present (host tests, unsupported platform).
  static const unavailable = 'UNAVAILABLE';

  final String code;
  final String message;

  const VaultCryptoException(this.code, [this.message = '']);

  @override
  String toString() => 'VaultCryptoException($code${message.isEmpty ? '' : ': $message'})';
}

/// Cryptographic operations the vault delegates to the platform.
///
/// Production uses [MethodChannelVaultCryptoBackend] (AES-256-GCM via
/// `javax.crypto`, PBKDF2-HMAC-SHA256, Android Keystore). Tests inject a fake.
abstract class VaultCryptoBackend {
  /// Returns `nonce(12) || ciphertext || tag(16)` using a fresh random nonce.
  Future<Uint8List> gcmEncrypt({
    required Uint8List key,
    required Uint8List data,
    required Uint8List aad,
  });

  /// Throws [VaultCryptoException] with [VaultCryptoException.authFailed] when
  /// the key, AAD or data does not authenticate.
  Future<Uint8List> gcmDecrypt({
    required Uint8List key,
    required Uint8List data,
    required Uint8List aad,
  });

  Future<Uint8List> pbkdf2({
    required Uint8List password,
    required Uint8List salt,
    required int iterations,
    required int length,
  });

  Future<Uint8List> keystoreWrap(VaultKeySlot slot, Uint8List data);

  Future<Uint8List> keystoreUnwrap(VaultKeySlot slot, Uint8List data);

  Future<void> keystoreDelete(VaultKeySlot slot);
}

/// [VaultCryptoBackend] backed by the Android `MainActivity` method channel.
class MethodChannelVaultCryptoBackend implements VaultCryptoBackend {
  static const MethodChannel channel = MethodChannel('com.webappypie.filezen/vault');

  const MethodChannelVaultCryptoBackend();

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw VaultCryptoException(e.code, e.message ?? '');
    } on MissingPluginException {
      throw const VaultCryptoException(
        VaultCryptoException.unavailable,
        'Native vault crypto is not available on this platform',
      );
    }
  }

  Future<Uint8List> _bytes(String method, Map<String, Object?> args) async {
    final result = await _invoke<Uint8List>(method, args);
    if (result == null) {
      throw VaultCryptoException('CRYPTO_ERROR', '$method returned no data');
    }
    return result;
  }

  @override
  Future<Uint8List> gcmEncrypt({
    required Uint8List key,
    required Uint8List data,
    required Uint8List aad,
  }) =>
      _bytes('gcmEncrypt', {'key': key, 'data': data, 'aad': aad});

  @override
  Future<Uint8List> gcmDecrypt({
    required Uint8List key,
    required Uint8List data,
    required Uint8List aad,
  }) =>
      _bytes('gcmDecrypt', {'key': key, 'data': data, 'aad': aad});

  @override
  Future<Uint8List> pbkdf2({
    required Uint8List password,
    required Uint8List salt,
    required int iterations,
    required int length,
  }) =>
      _bytes('pbkdf2', {
        'password': password,
        'salt': salt,
        'iterations': iterations,
        'length': length,
      });

  @override
  Future<Uint8List> keystoreWrap(VaultKeySlot slot, Uint8List data) =>
      _bytes('keystoreWrap', {'slot': slot.name, 'data': data});

  @override
  Future<Uint8List> keystoreUnwrap(VaultKeySlot slot, Uint8List data) =>
      _bytes('keystoreUnwrap', {'slot': slot.name, 'data': data});

  @override
  Future<void> keystoreDelete(VaultKeySlot slot) async {
    await _invoke<void>('keystoreDelete', {'slot': slot.name});
  }
}
