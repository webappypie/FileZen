import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import 'vault_providers.dart';

/// App-wide auto-lock. Honors the user's auto-lock timeout and works no matter
/// which screen is showing (the Vault can be unlocked from the file browser).
///
/// Only `paused` (app really in the background) triggers locking: `inactive`
/// also fires for the biometric prompt, permission dialogs and the notification
/// shade, which must not lock the vault mid-authentication.
class VaultLifecycleGuard with WidgetsBindingObserver {
  final Ref _ref;
  DateTime? _backgroundedAt;
  Timer? _backgroundLock;

  VaultLifecycleGuard(this._ref) {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    _backgroundLock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _onBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  Future<void> _onBackgrounded() async {
    final auth = _ref.read(vaultAuthServiceProvider);
    if (!auth.isUnlocked) return;
    _backgroundedAt = DateTime.now();
    try {
      final timeout = (await auth.getSecurityConfig()).autoLockTimeout;
      if (timeout == Duration.zero) {
        _lock();
      } else {
        // Do not keep the key in memory past the timeout while the app sits in
        // the background (the resume check alone only ran on return).
        _backgroundLock?.cancel();
        _backgroundLock = Timer(timeout, _lock);
      }
    } catch (e) {
      // If the policy cannot be read, fail closed.
      AppLogger.warning('Auto-lock policy unreadable; locking vault', 'VaultAuto');
      _lock();
    }
  }

  Future<void> _onResumed() async {
    _backgroundLock?.cancel();
    _backgroundLock = null;
    final since = _backgroundedAt;
    _backgroundedAt = null;
    final auth = _ref.read(vaultAuthServiceProvider);
    if (since == null || !auth.isUnlocked) return;
    try {
      final timeout = (await auth.getSecurityConfig()).autoLockTimeout;
      if (DateTime.now().difference(since) >= timeout) _lock();
    } catch (_) {
      _lock();
    }
  }

  void _lock() => _ref.read(vaultSessionProvider.notifier).lock();
}

/// Keep-alive provider; read once at app start.
final vaultLifecycleGuardProvider = Provider<VaultLifecycleGuard>((ref) {
  final guard = VaultLifecycleGuard(ref);
  ref.onDispose(guard.dispose);
  return guard;
});
