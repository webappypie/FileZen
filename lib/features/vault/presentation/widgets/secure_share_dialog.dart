import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/vault/vault_share_service.dart';
import '../../../../domain/models/vault_models.dart';

/// Explicit privacy safeguard dialog warning the user before exporting/sharing
/// a decrypted copy of a Vault file outside the secure enclave.
/// Runs the secure-share hand-off and reports the real outcome to the user.
Future<void> runSecureShare(
  BuildContext context,
  VaultShareService service,
  VaultItem item,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await service.shareDecrypted(item);
  final text = switch (outcome.status) {
    VaultShareStatus.opened =>
      'Opened a temporary decrypted copy. It is deleted automatically in a couple of minutes.',
    VaultShareStatus.noAppAvailable => 'No installed app can open or share this file type.',
    VaultShareStatus.failed => outcome.message ?? 'Sharing failed.',
  };
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

class SecureShareDialog extends StatelessWidget {
  final VaultItem item;

  const SecureShareDialog({
    super.key,
    required this.item,
  });

  static Future<bool> show(BuildContext context, VaultItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => SecureShareDialog(item: item),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.warning, size: 26),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'Security Warning',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: AppSpacing.roundedSm,
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'You are about to share a decrypted copy of this private file with an external application.',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'File: ${item.originalFileName}',
            style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Size: ${Formatters.formatFileSize(item.fileSize)}',
            style: AppTypography.bodySmall.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Once shared, FileZen can no longer guarantee the confidentiality or screenshot protection of this content outside the Vault.',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text('Proceed to Share'),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
