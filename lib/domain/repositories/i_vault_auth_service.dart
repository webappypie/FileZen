import 'dart:typed_data';
import '../models/vault_models.dart';

/// Contract for Vault authentication, PIN management, biometrics, and session key handling.
abstract class IVaultAuthService {
  /// Whether the user has configured a master PIN.
  Future<bool> isPinConfigured();

  /// Sets up a new master PIN for the Vault.
  Future<bool> setupPin(String pin);

  /// Authenticates using master PIN.
  Future<VaultAuthResult> verifyPin(String pin);

  /// Updates PIN, verifying current PIN first.
  Future<bool> changePin(String oldPin, String newPin);

  /// Whether biometric authentication hardware is available on this device.
  Future<bool> isBiometricAvailable();

  /// Toggles biometric unlock on or off.
  Future<bool> setBiometricEnabled(bool enabled);

  /// Authenticates using device biometrics.
  Future<VaultAuthResult> authenticateWithBiometrics();

  /// Retrieves current security policy.
  Future<VaultSecurityConfig> getSecurityConfig();

  /// Updates security configuration.
  Future<void> updateSecurityConfig(VaultSecurityConfig config);

  /// Locks the vault and zeroes out session keys.
  void lock();

  /// Whether the vault is currently unlocked in memory.
  bool get isUnlocked;

  /// Returns the current active 256-bit cryptographic session key in memory, or null if locked.
  Uint8List? get activeSessionKey;
}
