import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import 'vault_crypto_backend.dart';

/// Applies Android `FLAG_SECURE` to the activity window (blocks screenshots,
/// screen recording and hides content in the recents screen).
///
/// Reference counted so overlapping sensitive surfaces (the Vault tab plus a
/// pushed preview screen) cannot clear each other's protection.
class SecureWindow {
  const SecureWindow._();

  static int _holders = 0;

  /// Number of surfaces currently requiring a secure window (for tests).
  static int get holders => _holders;

  static Future<void> acquire() async {
    _holders++;
    if (_holders == 1) await _apply(true);
  }

  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _apply(false);
  }

  static Future<void> _apply(bool secure) async {
    try {
      await MethodChannelVaultCryptoBackend.channel.invokeMethod<void>(
        'setSecure',
        {'secure': secure},
      );
    } on MissingPluginException {
      // Host tests / non-Android platforms: nothing to protect.
    } on PlatformException catch (e) {
      AppLogger.warning('Could not update secure window flag: ${e.code}', 'SecureWindow');
    }
  }
}
