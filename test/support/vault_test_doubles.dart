import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:filezen/data/vault/vault_biometric_gate.dart';
import 'package:filezen/data/vault/vault_crypto_backend.dart';

/// Host-test stand-in for the native vault crypto layer.
///
/// It is NOT the production cipher (production is AES-256-GCM on Android and is
/// covered by android/app/src/test VaultCryptoTest). It is an authenticated
/// encrypt-then-MAC construction so tests exercise the same observable
/// behaviour: random nonces, wrong-key / wrong-AAD / tamper detection, and
/// Keystore-like slots with simulated invalidation and auth requirements.
class FakeVaultCryptoBackend implements VaultCryptoBackend {
  final Random _rng = Random.secure();
  final Uint8List _deviceSecret = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final Uint8List _biometricSecret = Uint8List.fromList(List.generate(32, (i) => 200 - i));

  bool deviceKeyPresent = true;
  bool biometricKeyPresent = true;
  bool biometricKeyInvalidated = false;

  /// When false, biometric unwrap/wrap throws AUTH_REQUIRED (no recent auth).
  bool biometricRecentlyAuthenticated = true;

  /// When set, device-slot operations throw this code (simulates Keystore trouble).
  String? deviceSlotFailure;

  int pbkdf2Calls = 0;

  Uint8List _bytes(int n) => Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  Uint8List _keystream(Uint8List key, Uint8List nonce, int length) {
    final out = BytesBuilder();
    var counter = 0;
    while (out.length < length) {
      final block = Uint8List(nonce.length + 4)..setRange(0, nonce.length, nonce);
      ByteData.sublistView(block).setUint32(nonce.length, counter++);
      out.add(Hmac(sha256, key).convert(block).bytes);
    }
    return Uint8List.sublistView(out.toBytes(), 0, length);
  }

  Uint8List _tag(Uint8List key, Uint8List nonce, Uint8List aad, Uint8List ct) {
    final msg = BytesBuilder()
      ..add(nonce)
      ..add((ByteData(4)..setUint32(0, aad.length)).buffer.asUint8List())
      ..add(aad)
      ..add(ct);
    final macKey = Hmac(sha256, key).convert(const [0x6d, 0x61, 0x63]).bytes;
    return Uint8List.fromList(Hmac(sha256, macKey).convert(msg.toBytes()).bytes.sublist(0, 16));
  }

  @override
  Future<Uint8List> gcmEncrypt({
    required Uint8List key,
    required Uint8List data,
    required Uint8List aad,
  }) async {
    if (key.length != 32) throw const VaultCryptoException('BAD_ARGUMENT', 'key length');
    final nonce = _bytes(12);
    final ks = _keystream(key, nonce, data.length);
    final ct = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      ct[i] = data[i] ^ ks[i];
    }
    return (BytesBuilder()
          ..add(nonce)
          ..add(ct)
          ..add(_tag(key, nonce, aad, ct)))
        .toBytes();
  }

  @override
  Future<Uint8List> gcmDecrypt({
    required Uint8List key,
    required Uint8List data,
    required Uint8List aad,
  }) async {
    if (key.length != 32) throw const VaultCryptoException('BAD_ARGUMENT', 'key length');
    if (data.length < 28) throw const VaultCryptoException('BAD_ARGUMENT', 'too short');
    final nonce = Uint8List.sublistView(data, 0, 12);
    final ct = Uint8List.sublistView(data, 12, data.length - 16);
    final tag = Uint8List.sublistView(data, data.length - 16);
    final expected = _tag(key, nonce, aad, ct);
    var diff = 0;
    for (var i = 0; i < 16; i++) {
      diff |= tag[i] ^ expected[i];
    }
    if (diff != 0) {
      throw const VaultCryptoException(VaultCryptoException.authFailed, 'tag mismatch');
    }
    final ks = _keystream(key, nonce, ct.length);
    final out = Uint8List(ct.length);
    for (var i = 0; i < ct.length; i++) {
      out[i] = ct[i] ^ ks[i];
    }
    return out;
  }

  @override
  Future<Uint8List> pbkdf2({
    required Uint8List password,
    required Uint8List salt,
    required int iterations,
    required int length,
  }) async {
    pbkdf2Calls++;
    // Cheap stand-in (real PBKDF2 is covered natively); deterministic in password+salt.
    final h = Hmac(sha256, password).convert([...salt, ...List.filled(4, 0), iterations & 0xff]);
    return Uint8List.fromList(h.bytes.sublist(0, length));
  }

  void _requireSlot(VaultKeySlot slot) {
    if (slot == VaultKeySlot.device) {
      if (deviceSlotFailure != null) throw VaultCryptoException(deviceSlotFailure!);
      if (!deviceKeyPresent) throw const VaultCryptoException(VaultCryptoException.keyMissing);
    } else {
      if (biometricKeyInvalidated) {
        throw const VaultCryptoException(VaultCryptoException.keyInvalidated);
      }
      if (!biometricKeyPresent) throw const VaultCryptoException(VaultCryptoException.keyMissing);
      if (!biometricRecentlyAuthenticated) {
        throw const VaultCryptoException(VaultCryptoException.authRequired);
      }
    }
  }

  Uint8List _slotKey(VaultKeySlot slot) =>
      slot == VaultKeySlot.device ? _deviceSecret : _biometricSecret;

  @override
  Future<Uint8List> keystoreWrap(VaultKeySlot slot, Uint8List data) async {
    if (slot == VaultKeySlot.biometric) {
      // Creating a key after deletion/invalidation works, like the real Keystore.
      biometricKeyPresent = true;
      biometricKeyInvalidated = false;
    }
    _requireSlot(slot);
    return gcmEncrypt(key: _slotKey(slot), data: data, aad: Uint8List(0));
  }

  @override
  Future<Uint8List> keystoreUnwrap(VaultKeySlot slot, Uint8List data) async {
    _requireSlot(slot);
    return gcmDecrypt(key: _slotKey(slot), data: data, aad: Uint8List(0));
  }

  @override
  Future<void> keystoreDelete(VaultKeySlot slot) async {
    if (slot == VaultKeySlot.biometric) biometricKeyPresent = false;
    if (slot == VaultKeySlot.device) deviceKeyPresent = false;
  }
}

class FakeBiometricGate implements VaultBiometricGate {
  bool available = true;
  bool result = true;
  bool throwOnAuthenticate = false;
  int authenticateCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    authenticateCalls++;
    if (throwOnAuthenticate) throw StateError('platform failure');
    return result;
  }
}
