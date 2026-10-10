import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../providers/vault_providers.dart';
import '../widgets/secure_surface.dart';

/// The one first-time Vault setup flow, used from the Vault tab and from every
/// "Move to Vault" action. Pops `true` once the Vault exists and is unlocked so
/// the caller can continue with what the user was doing.
///
/// 1. What the Vault does. 2. PIN + confirmation. 3. Optional biometric /
/// device-credential unlock (only offered when the device supports it).
/// 4. Recovery limits, which must be acknowledged. 5. Create.
class VaultSetupScreen extends ConsumerStatefulWidget {
  const VaultSetupScreen({super.key});

  /// Shows the flow; resolves to true when the Vault was created.
  static Future<bool> show(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const VaultSetupScreen(), fullscreenDialog: true),
    );
    return created ?? false;
  }

  @override
  ConsumerState<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends ConsumerState<VaultSetupScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _biometricAvailable = false;
  bool _enableBiometrics = false;
  bool _acknowledged = false;
  bool _busy = false;
  String? _error;

  static final _pinPattern = RegExp(r'^\d{4,6}$');

  @override
  void initState() {
    super.initState();
    ref.read(vaultAuthServiceProvider).isBiometricAvailable().then((available) {
      if (!mounted) return;
      setState(() {
        _biometricAvailable = available;
        _enableBiometrics = available;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final pin = _pin.text.trim();
    if (!_pinPattern.hasMatch(pin)) {
      setState(() => _error = 'Use 4 to 6 digits.');
      return;
    }
    if (pin != _confirm.text.trim()) {
      setState(() => _error = 'The PINs do not match.');
      return;
    }
    if (!_acknowledged) {
      setState(() => _error = 'Please confirm you understand how recovery works.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final created = await ref.read(vaultSessionProvider.notifier).setupInitialPin(pin);
    if (!mounted) return;
    if (!created) {
      setState(() {
        _busy = false;
        _error = 'The Vault could not be created on this device. Nothing was changed.';
      });
      return;
    }

    if (_enableBiometrics) {
      final enabled = await ref.read(vaultAuthServiceProvider).setBiometricEnabled(true);
      ref.invalidate(vaultSecurityConfigProvider);
      if (!enabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fingerprint / face unlock could not be turned on. Your PIN works; '
              'you can retry in Vault settings.'),
        ));
      }
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: AppColors.typeVault),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(text, style: AppTypography.bodySmall)),
            ],
          ),
        );

    return SecureSurface(
      active: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('Set Up Vault')),
        body: SafeArea(
          child: ListView(
            padding: AppSpacing.screenPadding,
            children: [
              Text('Keep private files private',
                  style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              point(Icons.lock_rounded, 'Files you move here are encrypted (AES-256-GCM) on this phone.'),
              point(Icons.visibility_off_rounded,
                  'The unencrypted original is removed and the file disappears from Search, categories and recent files.'),
              point(Icons.timer_outlined, 'The Vault locks when you leave FileZen.'),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Create a 4–6 digit PIN',
                  prefixIcon: Icon(Icons.pin_rounded),
                ),
              ),
              TextField(
                controller: _confirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              if (_biometricAvailable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enableBiometrics,
                  onChanged: _busy ? null : (v) => setState(() => _enableBiometrics = v),
                  title: const Text('Also unlock with fingerprint, face or screen lock'),
                  subtitle: const Text('Your PIN always works as well.'),
                ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: AppSpacing.cardPadding,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: AppSpacing.roundedMd,
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('There is no recovery',
                        style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '• Forgotten PIN: FileZen cannot reset it or decrypt your files.\n'
                      '• The Vault only works on this phone. Uninstalling FileZen, clearing its data, '
                      'a factory reset, or moving to a new phone permanently deletes access to Vault files.\n'
                      '• Vault files are not included in backups. Move files out of the Vault before '
                      'changing phones.',
                      style: AppTypography.bodySmall.copyWith(color: secondary),
                    ),
                  ],
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _acknowledged,
                onChanged: _busy ? null : (v) => setState(() => _acknowledged = v ?? false),
                title: const Text('I understand that lost PINs and lost phones cannot be recovered'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.typeVault),
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.shield_rounded),
                label: const Text('Create Vault'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
