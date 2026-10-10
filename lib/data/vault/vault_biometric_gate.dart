import 'package:local_auth/local_auth.dart';

import '../../core/logging/app_logger.dart';

/// Thin seam over the platform biometric / device-credential prompt.
///
/// Contract: [authenticate] returns `true` only when the system prompt reported
/// success. Any cancellation, lockout, missing hardware, platform error or
/// exception MUST surface as `false` (fail closed) — callers never unlock on
/// anything else.
abstract class VaultBiometricGate {
  Future<bool> isAvailable();

  Future<bool> authenticate(String reason);
}

/// Android `BiometricPrompt` via `local_auth`.
class LocalAuthVaultBiometricGate implements VaultBiometricGate {
  final LocalAuthentication _localAuth;

  LocalAuthVaultBiometricGate({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      return canCheck || supported;
    } catch (e) {
      AppLogger.warning('Biometric availability check failed: $e', 'VaultBiometric');
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        // BIOMETRIC_STRONG | DEVICE_CREDENTIAL, matching the Keystore key policy.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      AppLogger.warning('Biometric authentication did not succeed: $e', 'VaultBiometric');
      return false;
    }
  }
}
