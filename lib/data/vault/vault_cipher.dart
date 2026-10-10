import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// LEGACY (v1) vault format support plus shared helpers.
///
/// The v1 container (HMAC-SHA256 CTR keystream, PIN-derived key, one IV shared
/// by metadata and content) is NOT used for any new data. It remains only so
/// existing v1 containers can be decrypted once and migrated to the AES-256-GCM
/// v2 format (see [VaultContainer] and `VaultStorageService`).
class VaultCipher {
  static const String magicHeader = 'ZENVAULT\x01';
  static const int saltLength = 32;
  static const int ivLength = 16;
  static const int hmacTagLength = 32;
  static const int pbkdf2Iterations = 10000;

  final Random _secureRandom = Random.secure();

  /// Generates cryptographically secure random bytes.
  Uint8List generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Derives a 64-byte key material (32 bytes encryption key + 32 bytes HMAC auth key)
  /// from raw secret key bytes and salt using standard PBKDF2-HMAC-SHA256.
  ({Uint8List encKey, Uint8List authKey}) deriveKeysFromBytes(
    List<int> secretBytes,
    Uint8List salt, {
    int iterations = pbkdf2Iterations,
  }) {
    final block1 = _pbkdf2Block(secretBytes, salt, 1, iterations);
    final block2 = _pbkdf2Block(secretBytes, salt, 2, iterations);

    final encKey = Uint8List.fromList(block1);
    final authKey = Uint8List.fromList(block2);
    return (encKey: encKey, authKey: authKey);
  }

  /// Derives a 64-byte key material from a password/PIN and salt using standard PBKDF2-HMAC-SHA256.
  ({Uint8List encKey, Uint8List authKey}) deriveKeys(
    String pin,
    Uint8List salt, {
    int iterations = pbkdf2Iterations,
  }) {
    return deriveKeysFromBytes(utf8.encode(pin), salt, iterations: iterations);
  }

  Uint8List _pbkdf2Block(
    List<int> password,
    List<int> salt,
    int blockIndex,
    int iterations,
  ) {
    final hmac = Hmac(sha256, password);
    final saltWithIndex = Uint8List(salt.length + 4);
    saltWithIndex.setRange(0, salt.length, salt);
    // 4-byte big-endian block index
    ByteData.view(saltWithIndex.buffer).setUint32(salt.length, blockIndex, Endian.big);

    Uint8List u = Uint8List.fromList(hmac.convert(saltWithIndex).bytes);
    final result = Uint8List.fromList(u);

    for (int iter = 1; iter < iterations; iter++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int k = 0; k < result.length; k++) {
        result[k] ^= u[k];
      }
    }
    return result;
  }

  /// Encrypts data in CTR mode using HMAC-SHA256 keystream expansion.
  Uint8List _cryptCtr(Uint8List key, Uint8List iv, Uint8List input) {
    final output = Uint8List(input.length);
    final hmac = Hmac(sha256, key);
    final counterBlock = Uint8List(iv.length + 4);
    counterBlock.setRange(0, iv.length, iv);

    int offset = 0;
    int counter = 0;

    while (offset < input.length) {
      ByteData.view(counterBlock.buffer).setUint32(iv.length, counter, Endian.big);
      final keyStreamBlock = hmac.convert(counterBlock).bytes;

      final chunkSize = min(keyStreamBlock.length, input.length - offset);
      for (int i = 0; i < chunkSize; i++) {
        output[offset + i] = input[offset + i] ^ keyStreamBlock[i];
      }

      offset += chunkSize;
      counter++;
    }

    return output;
  }

  /// Packages and encrypts plaintext and metadata into an authenticated .zenvault container.
  Uint8List encryptPayload({
    required List<int> plaintext,
    required Map<String, dynamic> metadata,
    String? pin,
    List<int>? secretKey,
  }) {
    assert(pin != null || secretKey != null, 'Either pin or secretKey must be provided');
    final salt = generateRandomBytes(saltLength);
    final iv = generateRandomBytes(ivLength);
    final secretBytes = secretKey ?? utf8.encode(pin!);
    final keys = deriveKeysFromBytes(secretBytes, salt);

    final metadataJsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
    final plaintextBytes = Uint8List.fromList(plaintext);

    final encryptedMetadata = _cryptCtr(keys.encKey, iv, metadataJsonBytes);
    final encryptedContent = _cryptCtr(keys.encKey, iv, plaintextBytes);

    final magicBytes = utf8.encode(magicHeader);

    // Compute HMAC-SHA256 authentication tag over all header and encrypted parts
    final hmac = Hmac(sha256, keys.authKey);

    // Layout:
    // [Magic (9)] + [Salt (32)] + [IV (16)] + [MetaLen (4)] + [EncMeta] + [EncData] + [HMAC Tag (32)]
    final totalSize = magicBytes.length +
        saltLength +
        ivLength +
        4 +
        encryptedMetadata.length +
        encryptedContent.length +
        hmacTagLength;

    final buffer = Uint8List(totalSize);
    final byteData = ByteData.view(buffer.buffer);

    int pos = 0;
    buffer.setRange(pos, pos + magicBytes.length, magicBytes);
    pos += magicBytes.length;

    buffer.setRange(pos, pos + saltLength, salt);
    pos += saltLength;

    buffer.setRange(pos, pos + ivLength, iv);
    pos += ivLength;

    byteData.setUint32(pos, encryptedMetadata.length, Endian.big);
    pos += 4;

    buffer.setRange(pos, pos + encryptedMetadata.length, encryptedMetadata);
    pos += encryptedMetadata.length;

    buffer.setRange(pos, pos + encryptedContent.length, encryptedContent);
    pos += encryptedContent.length;

    // Calculate HMAC tag over everything up to this point
    final hmacDigest = hmac.convert(buffer.sublist(0, pos)).bytes;
    buffer.setRange(pos, pos + hmacTagLength, hmacDigest);

    return buffer;
  }

  /// Decrypts and authenticates a .zenvault container.
  ({Uint8List plaintext, Map<String, dynamic> metadata}) decryptPayload({
    required Uint8List containerBytes,
    String? pin,
    List<int>? secretKey,
  }) {
    assert(pin != null || secretKey != null, 'Either pin or secretKey must be provided');
    final magicBytes = utf8.encode(magicHeader);
    if (containerBytes.length < magicBytes.length + saltLength + ivLength + 4 + hmacTagLength) {
      throw const FormatException('Invalid or corrupt vault container: file too small');
    }

    int pos = 0;
    final magicInFile = utf8.decode(containerBytes.sublist(0, magicBytes.length));
    if (magicInFile != magicHeader) {
      throw const FormatException('Unrecognized vault container header format');
    }
    pos += magicBytes.length;

    final salt = containerBytes.sublist(pos, pos + saltLength);
    pos += saltLength;

    final iv = containerBytes.sublist(pos, pos + ivLength);
    pos += ivLength;

    final byteData = ByteData.sublistView(containerBytes);
    final metaLen = byteData.getUint32(pos, Endian.big);
    pos += 4;

    if (containerBytes.length < pos + metaLen + hmacTagLength) {
      throw const FormatException('Corrupt vault container: metadata length out of bounds');
    }

    final encryptedMetadata = containerBytes.sublist(pos, pos + metaLen);
    pos += metaLen;

    final contentLen = containerBytes.length - pos - hmacTagLength;
    final encryptedContent = containerBytes.sublist(pos, pos + contentLen);
    pos += contentLen;

    final expectedTag = containerBytes.sublist(pos, pos + hmacTagLength);

    // Derive keys from supplied secret key or PIN and container's salt
    final secretBytes = secretKey ?? utf8.encode(pin!);
    final keys = deriveKeysFromBytes(secretBytes, salt);

    // Verify HMAC authentication tag in constant time
    final hmac = Hmac(sha256, keys.authKey);
    final computedTag = hmac.convert(containerBytes.sublist(0, pos)).bytes;

    if (!constantTimeEquals(expectedTag, computedTag)) {
      throw const FormatException('Authentication failed: Invalid PIN or tampered container');
    }

    // Decrypt metadata and content
    final decryptedMetaBytes = _cryptCtr(keys.encKey, iv, encryptedMetadata);
    final decryptedContentBytes = _cryptCtr(keys.encKey, iv, encryptedContent);

    final metaJson = jsonDecode(utf8.decode(decryptedMetaBytes)) as Map<String, dynamic>;
    return (plaintext: decryptedContentBytes, metadata: metaJson);
  }

  /// Constant-time byte array equality comparison to protect against timing attacks.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
