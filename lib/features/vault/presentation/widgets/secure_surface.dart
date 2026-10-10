import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/vault/secure_window.dart';
import '../providers/vault_providers.dart';

/// Marks its subtree as sensitive: while [active] and the user's "Screenshot
/// Protection" vault setting is on (it defaults to on until the setting loads),
/// the Android window is flagged `FLAG_SECURE`.
class SecureSurface extends ConsumerStatefulWidget {
  final bool active;
  final Widget child;

  const SecureSurface({super.key, this.active = true, required this.child});

  @override
  ConsumerState<SecureSurface> createState() => _SecureSurfaceState();
}

class _SecureSurfaceState extends ConsumerState<SecureSurface> {
  bool _held = false;

  void _sync(bool want) {
    if (want == _held) return;
    _held = want;
    if (want) {
      SecureWindow.acquire();
    } else {
      SecureWindow.release();
    }
  }

  @override
  void dispose() {
    _sync(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var protect = false;
    if (widget.active) {
      protect = ref.watch(vaultSecurityConfigProvider).maybeWhen(
            data: (config) => config.screenshotProtectionEnabled,
            // Fail closed while loading or if the config cannot be read.
            orElse: () => true,
          );
    }
    _sync(protect);
    return widget.child;
  }
}
