import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../providers/vault_providers.dart';
import '../widgets/secure_surface.dart';

/// Screen managing Vault security policies: PIN change, biometrics, auto-lock timeout, and screenshot protection.
class VaultSettingsScreen extends ConsumerStatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  ConsumerState<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends ConsumerState<VaultSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final configAsync = ref.watch(vaultSecurityConfigProvider);

    return SecureSurface(
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Vault Security Settings'),
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading settings: $e')),
        data: (config) {
          return ListView(
            padding: AppSpacing.screenPadding,
            children: [
              // Security Policy Overview Card
              Container(
                padding: AppSpacing.cardPadding,
                decoration: BoxDecoration(
                  color: AppColors.typeVault.withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: AppSpacing.roundedMd,
                  border: Border.all(color: AppColors.typeVault.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security_rounded, color: AppColors.typeVault, size: 28),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Authenticated Enclave',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.typeVault,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'AES-256-GCM encryption with a master key protected by your PIN and the Android Keystore.',
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // PIN Management
              Card(
                child: ListTile(
                  leading: const Icon(Icons.pin_rounded, color: AppColors.primary),
                  title: const Text('Change Master PIN'),
                  subtitle: const Text('Update your 4-6 digit numeric vault PIN'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showChangePinDialog(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Biometrics Toggle
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.fingerprint_rounded, color: AppColors.secondary),
                  title: const Text('Biometric Unlock'),
                  subtitle: const Text('Use fingerprint or face recognition to unlock Vault'),
                  value: config.isBiometricEnabled,
                  onChanged: (val) async {
                    final auth = ref.read(vaultAuthServiceProvider);
                    final ok = await auth.setBiometricEnabled(val);
                    ref.invalidate(vaultSecurityConfigProvider);
                    if (!ok && val && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Biometric unlock could not be enabled. Make sure a screen lock and '
                            'a fingerprint or face are set up on this device, then try again.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Screenshot & Recording Protection
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.screenshot_outlined, color: AppColors.warning),
                  title: const Text('Screenshot Protection'),
                  subtitle: const Text('Block screenshots and hide previews in recent apps'),
                  value: config.screenshotProtectionEnabled,
                  onChanged: (val) async {
                    final auth = ref.read(vaultAuthServiceProvider);
                    await auth.updateSecurityConfig(
                      config.copyWith(screenshotProtectionEnabled: val),
                    );
                    ref.invalidate(vaultSecurityConfigProvider);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Auto-Lock Timeout
              Card(
                child: ListTile(
                  leading: const Icon(Icons.timer_outlined, color: AppColors.info),
                  title: const Text('Auto-Lock Policy'),
                  subtitle: Text(_formatTimeout(config.autoLockTimeout)),
                  trailing: PopupMenuButton<int>(
                    initialValue: config.autoLockTimeout.inSeconds,
                    onSelected: (seconds) async {
                      final auth = ref.read(vaultAuthServiceProvider);
                      await auth.updateSecurityConfig(
                        config.copyWith(autoLockTimeout: Duration(seconds: seconds)),
                      );
                      ref.invalidate(vaultSecurityConfigProvider);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 0, child: Text('Immediately on Background')),
                      PopupMenuItem(value: 30, child: Text('After 30 seconds')),
                      PopupMenuItem(value: 60, child: Text('After 1 minute')),
                      PopupMenuItem(value: 300, child: Text('After 5 minutes')),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  String _formatTimeout(Duration d) {
    if (d == Duration.zero) return 'Immediately when app minimized';
    if (d.inMinutes >= 1) return 'After ${d.inMinutes} minute(s)';
    return 'After ${d.inSeconds} seconds';
  }

  Future<void> _showChangePinDialog(BuildContext context) async {
    final oldPinController = TextEditingController();
    final newPinController = TextEditingController();
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Change Master PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Current PIN'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: newPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'New PIN (4-6 digits)'),
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final oldPin = oldPinController.text.trim();
                final newPin = newPinController.text.trim();
                if (newPin.length < 4) {
                  setDialogState(() => error = 'New PIN must be at least 4 digits');
                  return;
                }
                final auth = ref.read(vaultAuthServiceProvider);
                final success = await auth.changePin(oldPin, newPin);
                if (success) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Master PIN updated successfully')),
                    );
                  }
                } else {
                  setDialogState(() => error = 'Current PIN is incorrect');
                }
              },
              child: const Text('Update PIN'),
            ),
          ],
        ),
      ),
    );
  }
}
