import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';

class CleanScreen extends StatelessWidget {
  const CleanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cleanupCategories = [
      (
        'Exact Duplicate Files',
        'Cryptographically matched files occupying wasted space.',
        '142 MB',
        Icons.copy_all_rounded,
        AppColors.warning,
      ),
      (
        'Similar & Blurry Photos',
        'Burst photos, similar angle duplicates, and out-of-focus media.',
        '320 MB',
        Icons.photo_library_outlined,
        AppColors.typeImage,
      ),
      (
        'Large Files (> 100 MB)',
        'Uncompressed videos, archives, and offline caches.',
        '4.2 GB',
        Icons.donut_large_rounded,
        AppColors.typeVideo,
      ),
      (
        'Old APK Installers',
        'Package installer files left in Downloads folder.',
        '280 MB',
        Icons.android_rounded,
        AppColors.typeApk,
      ),
      (
        'Empty Folders',
        '12 empty directories from uninstalled apps.',
        '0 B',
        Icons.folder_off_outlined,
        AppColors.lightTextSecondary,
      ),
    ];

    return Scaffold(
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // Safety Contract Banner
          Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: AppSpacing.roundedMd,
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.info, size: 28),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zero Silent Deletions Contract',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.info,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'FileZen never deletes content automatically. Every cleanup action requires your explicit preview, review, and confirmation.',
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

          Text(
            'Cleanup Opportunities',
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),

          ...cleanupCategories.map(
            (cat) => Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cat.$5.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(cat.$4, color: cat.$5, size: 24),
                ),
                title: Text(
                  cat.$1,
                  style: AppTypography.titleMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  cat.$2,
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                trailing: Text(
                  cat.$3,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Cleanup analysis engine activates in Phase 08 (${cat.$1})')),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
