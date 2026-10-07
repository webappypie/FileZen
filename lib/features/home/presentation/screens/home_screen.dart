import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/wapcentral/wap_client_provider.dart';
import '../../../../domain/repositories/i_wap_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final wapService = ref.watch(wapServiceProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // WAPCentral Connectivity Status Badge
                  _buildServiceBadge(context, wapService),
                  const SizedBox(height: AppSpacing.sm),

                  // Storage Intelligence Overview Card
                  _buildStorageOverviewCard(context, isDark),
                  const SizedBox(height: AppSpacing.lg),

                  // Quick File Categories
                  Text(
                    'Categories',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildCategoriesGrid(context, isDark),
                  const SizedBox(height: AppSpacing.lg),

                  // Smart Collections Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Smart Collections',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Virtual • AI Organized',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildSmartCollectionsCard(context, isDark),
                  const SizedBox(height: AppSpacing.lg),

                  // Ask Your Files Entry Point
                  _buildAskYourFilesCard(context, isDark),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceBadge(BuildContext context, IWapService service) {
    final (label, icon, color) = switch (service.status) {
      WapServiceStatus.online => ('WAP Ecosystem Connected', Icons.check_circle_outline, AppColors.success),
      WapServiceStatus.checking => ('Connecting...', Icons.sync, AppColors.info),
      WapServiceStatus.offline => ('Local-First Mode (100% Offline)', Icons.offline_bolt_outlined, AppColors.secondary),
      WapServiceStatus.unconfigured => ('Local-First Mode (On-Device)', Icons.shield_outlined, AppColors.secondary),
      WapServiceStatus.error => ('Local-First Mode (Service Offline)', Icons.cloud_off_outlined, AppColors.warning),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppSpacing.roundedSm,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageOverviewCard(BuildContext context, bool isDark) {
    const totalBytes = 128 * 1024 * 1024 * 1024; // 128 GB
    const usedBytes = 46 * 1024 * 1024 * 1024; // 46 GB
    const freeBytes = totalBytes - usedBytes;
    const usedRatio = usedBytes / totalBytes;

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Internal Storage',
                      style: AppTypography.labelLarge.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${Formatters.formatFileSize(usedBytes)} used of ${Formatters.formatFileSize(totalBytes)}',
                      style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: AppSpacing.roundedSm,
                  ),
                  child: Text(
                    '${(usedRatio * 100).toInt()}%',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: AppSpacing.roundedSm,
              child: LinearProgressIndicator(
                value: usedRatio,
                minHeight: 8,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${Formatters.formatFileSize(freeBytes)} free available space',
              style: AppTypography.bodySmall.copyWith(
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesGrid(BuildContext context, bool isDark) {
    final categories = [
      ('Images', Icons.image_rounded, AppColors.typeImage, '1,420 files'),
      ('Videos', Icons.movie_rounded, AppColors.typeVideo, '124 files'),
      ('Audio', Icons.headphones_rounded, AppColors.typeAudio, '350 files'),
      ('Documents', Icons.description_rounded, AppColors.typeDocument, '88 files'),
      ('Downloads', Icons.download_rounded, AppColors.primary, '64 files'),
      ('Archives', Icons.archive_rounded, AppColors.typeArchive, '15 files'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (context, index) {
        final (title, icon, color, count) = categories[index];
        return Card(
          child: InkWell(
            borderRadius: AppSpacing.roundedMd,
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 22, color: color),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    title,
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    count,
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 10,
                      color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSmartCollectionsCard(BuildContext context, bool isDark) {
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: AppSpacing.roundedSm,
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent Tax Receipts & Invoices',
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '12 documents automatically grouped without moving files',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAskYourFilesCard(BuildContext context, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            const Icon(Icons.psychology_alt_rounded, size: 36, color: AppColors.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask Your Files',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Find documents, resumes, and receipts using natural query search',
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
    );
  }
}
