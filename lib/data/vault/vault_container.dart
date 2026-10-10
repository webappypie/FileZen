import 'dart:convert';
import 'dart:typed_data';

import 'vault_crypto_backend.dart';

/// `.zenvault` v2 container: AES-256-GCM for both metadata and content.
///
/// Layout:
/// ```
/// magic "ZENVAULT\x02" (9) | metaBlobLen u32-be (4) | metaBlob | contentBlob
/// ```
/// Each blob is `nonce(12) || ciphertext || tag(16)` with an independent random
/// nonce. The metadata blob authenticates the magic as AAD; the content blob
/// authenticates the magic plus the metadata blob, so content and metadata
/// cannot be swapped between containers.
class VaultContainer {
  const VaultContainer._();

  static const String magicV2 = 'ZENVAULT\x02';
  static const String magicV1 = 'ZENVAULT\x01';

  static final Uint8List _magicV2Bytes = Uint8List.fromList(utf8.encode(magicV2));
  static const int _minBlob = 12 + 16;

  static bool isV2(Uint8List bytes) => _hasMagic(bytes, magicV2);

  static bool isLegacyV1(Uint8List bytes) => _hasMagic(bytes, magicV1);

  static bool _hasMagic(Uint8List bytes, String magic) {
    final m = utf8.encode(magic);
    if (bytes.length < m.length) return false;
    for (var i = 0; i < m.length; i++) {
      if (bytes[i] != m[i]) return false;
    }
    return true;
  }

  static Uint8List _contentAad(Uint8List metaBlob) {
    final aad = Uint8List(_magicV2Bytes.length + metaBlob.length);
    aad.setRange(0, _magicV2Bytes.length, _magicV2Bytes);
    aad.setRange(_magicV2Bytes.length, aad.length, metaBlob);
    return aad;
  }

  static Future<Uint8List> seal(
    VaultCryptoBackend backend, {
    required Uint8List key,
    required Uint8List plaintext,
    required Map<String, dynamic> metadata,
  }) async {
    final metaBlob = await backend.gcmEncrypt(
      key: key,
      data: Uint8List.fromList(utf8.encode(jsonEncode(metadata))),
      aad: _magicV2Bytes,
    );
    final contentBlob = await backend.gcmEncrypt(
      key: key,
      data: plaintext,
      aad: _contentAad(metaBlob),
    );

    final out = Uint8List(_magicV2Bytes.length + 4 + metaBlob.length + contentBlob.length);
    var pos = 0;
    out.setRange(pos, pos += _magicV2Bytes.length, _magicV2Bytes);
    ByteData.sublistView(out).setUint32(pos, metaBlob.length, Endian.big);
    pos += 4;
    out.setRange(pos, pos += metaBlob.length, metaBlob);
    out.setRange(pos, pos += contentBlob.length, contentBlob);
    return out;
  }

  /// Authenticates and decrypts a v2 container.
  ///
  /// Throws [FormatException] for malformed containers and
  /// [VaultCryptoException] (`AUTH_FAILED`) for a wrong key or tampered data.
  static Future<({Uint8List plaintext, Map<String, dynamic> metadata})> open(
    VaultCryptoBackend backend, {
    required Uint8List key,
    required Uint8List container,
  }) async {
    if (!isV2(container)) {
      throw const FormatException('Unrecognized vault container format');
    }
    final headerLen = _magicV2Bytes.length + 4;
    if (container.length < headerLen + 2 * _minBlob) {
      throw const FormatException('Corrupt vault container: too small');
    }
    final metaLen = ByteData.sublistView(container).getUint32(_magicV2Bytes.length, Endian.big);
    if (metaLen < _minBlob || headerLen + metaLen + _minBlob > container.length) {
      throw const FormatException('Corrupt vault container: metadata length out of bounds');
    }

    final metaBlob = Uint8List.sublistView(container, headerLen, headerLen + metaLen);
    final contentBlob = Uint8List.sublistView(container, headerLen + metaLen);

    final metaBytes = await backend.gcmDecrypt(key: key, data: metaBlob, aad: _magicV2Bytes);
    final plaintext = await backend.gcmDecrypt(
      key: key,
      data: contentBlob,
      aad: _contentAad(metaBlob),
    );
    final metadata = jsonDecode(utf8.decode(metaBytes));
    if (metadata is! Map<String, dynamic>) {
      throw const FormatException('Corrupt vault container: invalid metadata');
    }
    return (plaintext: plaintext, metadata: metadata);
  }
}
