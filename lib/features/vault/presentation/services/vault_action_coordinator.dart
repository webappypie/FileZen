import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/models/file_entity.dart';
import '../providers/vault_providers.dart';
import '../screens/vault_setup_screen.dart';

/// Coordinator for moving files into Vault from any screen in FileZen
/// (files browser, categories, search, details, recent collections).
class VaultActionCoordinator {
  const VaultActionCoordinator._();

  /// Move a single file to Vault
  static Future<void> moveFileToVault(
    BuildContext context,
    WidgetRef ref,
    FileEntity file, {
    VoidCallback? onSuccess,
  }) =>
      moveFilesToVault(context, ref, [file], onSuccess: onSuccess);

  /// Move multiple files to Vault
  static Future<void> moveMultipleToVault(
    BuildContext context,
    WidgetRef ref,
    List<FileEntity> files, {
    VoidCallback? onSuccess,
  }) =>
      moveFilesToVault(context, ref, files, onSuccess: onSuccess);

  /// Prompts user and moves one or more files securely into Vault.
  static Future<void> moveFilesToVault(
    BuildContext context,
    WidgetRef ref,
    List<FileEntity> files, {
    VoidCallback? onSuccess,
  }) async {
    if (files.isEmpty) return;

    final authService = ref.read(vaultAuthServiceProvider);
    final isConfigured = await authService.isPinConfigured();

    if (!context.mounted) return;

    // 1. Vault Onboarding: If not configured, guide through first-time setup
    if (!isConfigured) {
      final setupComplete = await _showOnboardingSetup(context, ref);
      if (!setupComplete || !context.mounted) return;
    }

    // 2. Unlock Vault if currently locked
    final isUnlocked = ref.read(vaultSessionProvider);
    if (!isUnlocked) {
      final unlockSuccess = await _showUnlockPrompt(context, ref);
      if (!unlockSuccess || !context.mounted) return;
    }

    // 3. Confirm move
    final count = files.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.shield_outlined, color: AppColors.typeVault, size: 36),
        title: Text(count == 1 ? 'Move File to Vault?' : 'Move $count Files to Vault?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 1
                  ? 'Moving "${files.first.name}" will encrypt it with hardware-grade AES-256 and remove the unencrypted source.'
                  : 'Moving $count selected files will encrypt them with hardware-grade AES-256 and remove unencrypted source files.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.typeVault.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, size: 18, color: AppColors.typeVault),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Access requires your Vault PIN or Biometrics.',
                      style: AppTypography.bodySmall.copyWith(fontSize: 11, color: AppColors.typeVault),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.typeVault),
            icon: const Icon(Icons.lock_rounded, size: 16),
            label: const Text('Move to Vault'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    // 4. Execute the move. Each file is encrypted, the encrypted copy is
    // verified, and only then is the original deleted (see VaultStorageService).
    int succeeded = 0;
    final errors = <String>[];
    final progress = ValueNotifier<int>(0);
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, done, __) => Row(
              children: [
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(width: 16),
                Expanded(child: Text('Encrypting ${done + 1 > count ? count : done + 1} of $count…')),
              ],
            ),
          ),
        ),
      ),
    ));

    try {
      for (final file in files) {
        final result = await ref.read(vaultItemsProvider.notifier).importFile(
              file.path,
              deleteSource: true,
            );
        if (result.isSuccess) {
          succeeded++;
        } else {
          errors.add('${file.name}: ${result.errorOrNull?.message}');
        }
        progress.value++;
      }
    } finally {
      navigator.pop();
      progress.dispose();
    }

    if (!context.mounted) return;

    if (succeeded > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully moved $succeeded item(s) to Vault'),
          backgroundColor: AppColors.success,
        ),
      );
      onSuccess?.call();
    }

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to move ${errors.length} item(s): ${errors.first}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// The same first-time setup the Vault tab uses; returns true when created.
  static Future<bool> _showOnboardingSetup(BuildContext context, WidgetRef ref) =>
      VaultSetupScreen.show(context);

  static Future<bool> _showUnlockPrompt(BuildContext context, WidgetRef ref) async {
    final pinController = TextEditingController();
    String? errorText;
    final biometricEnabled =
        (await ref.read(vaultAuthServiceProvider).getSecurityConfig()).isBiometricEnabled;
    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: const Icon(Icons.lock_rounded, color: AppColors.typeVault, size: 36),
          title: const Text('Unlock Vault'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your Vault PIN to continue.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Master PIN',
                  prefixIcon: const Icon(Icons.pin_rounded),
                  errorText: errorText,
                ),
                onSubmitted: (val) async {
                  final authRes = await ref.read(vaultSessionProvider.notifier).unlockWithPin(val.trim());
                  if (authRes.success) {
                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                  } else {
                    setDialogState(() => errorText = authRes.errorMessage ?? 'Incorrect PIN');
                  }
                },
              ),
              if (biometricEnabled) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Use fingerprint / face'),
                  onPressed: () async {
                    final bioRes = await ref.read(vaultSessionProvider.notifier).unlockWithBiometrics();
                    if (bioRes.success) {
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } else {
                      setDialogState(() => errorText = bioRes.errorMessage ?? 'Biometric authentication failed');
                    }
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.typeVault),
              onPressed: () async {
                final authRes = await ref.read(vaultSessionProvider.notifier).unlockWithPin(pinController.text.trim());
                if (authRes.success) {
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } else {
                  setDialogState(() => errorText = authRes.errorMessage ?? 'Incorrect PIN');
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }
}
