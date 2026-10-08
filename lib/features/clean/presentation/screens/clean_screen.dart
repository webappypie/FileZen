import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/cleanup_models.dart';
import '../../../../domain/models/storage_intelligence_models.dart';
import '../providers/clean_providers.dart';
import 'cleanup_category_screen.dart';
import 'duplicate_review_screen.dart';
import 'storage_analysis_screen.dart';
import 'timeline_screen.dart';
import 'trash_screen.dart';

/// Storage Hygiene & Deduplication Engine Hub Screen.
/// Strictly enforces the Zero Silent Deletions Contract:
/// - Previews candidates
/// - Quantifies item count and size impact
/// - Requests explicit confirmation
/// - Supports recovery via Recycle Bin
class CleanScreen extends ConsumerWidget {
  const CleanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final overviewAsync = ref.watch(storageOverviewProvider);
    final opportunitiesAsync = ref.watch(cleanupOpportunitiesProvider);
    final trashAsync = ref.watch(trashItemsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(storageOverviewProvider);
          ref.invalidate(cleanupOpportunitiesProvider);
          ref.invalidate(exactDuplicatesProvider);
          ref.read(trashItemsProvider.notifier).refresh();
        },
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            // Safety Contract Banner
            _buildSafetyContractBanner(context, isDark),
            const SizedBox(height: AppSpacing.md),

            // Storage Intelligence Overview Card
            overviewAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) => ErrorView(
                message: 'Failed to load storage overview: $e',
                onRetry: () => ref.invalidate(storageOverviewProvider),
              ),
              data: (overview) => _buildStorageOverviewCard(context, overview, isDark),
            ),
            const SizedBox(height: AppSpacing.md),

            // Hub Navigation Shortcut Buttons: Storage Analysis | Timeline | Recycle Bin
            _buildHubNavigationRow(context, trashAsync, isDark),
            const SizedBox(height: AppSpacing.lg),

            // Featured Exact Duplicates Card
            _buildDuplicatesBanner(context, isDark),
            const SizedBox(height: AppSpacing.lg),

            // Cleanup Opportunities Section
            Text(
              'Reviewable Cleanup Opportunities',
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Select an opportunity to review individual candidate files before performing safe cleanup.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            opportunitiesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: LoadingView(message: 'Analyzing storage hygiene & cleanup opportunities...'),
              ),
              error: (err, _) => ErrorView(
                message: 'Failed to scan opportunities: $err',
                onRetry: () => ref.invalidate(cleanupOpportunitiesProvider),
              ),
              data: (opportunities) {
                if (opportunities.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Storage is Optimal',
                                  style: AppTypography.titleMedium.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'No redundant files, duplicates, or stale data detected.',
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

                return Column(
                  children: opportunities.map((group) {
                    return _buildOpportunityTile(context, group, isDark);
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyContractBanner(BuildContext context, bool isDark) {
    return Container(
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
    );
  }

  Widget _buildStorageOverviewCard(
    BuildContext context,
    StorageOverview overview,
    bool isDark,
  ) {
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
                      'Internal Storage Usage',
                      style: AppTypography.labelLarge.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${Formatters.formatFileSize(overview.usedBytes)} used of ${Formatters.formatFileSize(overview.totalBytes)}',
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
                    '${overview.usedPercentage.toStringAsFixed(1)}%',
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
                value: overview.usedRatio,
                minHeight: 10,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${Formatters.formatFileSize(overview.freeBytes)} available space',
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const StorageAnalysisScreen()),
                    );
                  },
                  child: Text(
                    'Deep Analysis →',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubNavigationRow(
    BuildContext context,
    AsyncValue<List<dynamic>> trashAsync,
    bool isDark,
  ) {
    final trashCount = trashAsync.maybeWhen(data: (items) => items.length, orElse: () => 0);

    return Row(
      children: [
        Expanded(
          child: _buildShortcutCard(
            context: context,
            icon: Icons.pie_chart_outline_rounded,
            title: 'Analysis',
            color: AppColors.primary,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StorageAnalysisScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _buildShortcutCard(
            context: context,
            icon: Icons.history_rounded,
            title: 'Timeline',
            color: AppColors.secondary,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TimelineScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _buildShortcutCard(
            context: context,
            icon: Icons.delete_outline_rounded,
            title: 'Recycle Bin',
            badgeText: trashCount > 0 ? '$trashCount' : null,
            color: AppColors.warning,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrashScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? badgeText,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppSpacing.roundedMd,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[100],
          borderRadius: AppSpacing.roundedMd,
          border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 26),
                if (badgeText != null)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              title,
              style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDuplicatesBanner(BuildContext context, bool isDark) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DuplicateReviewScreen()),
        );
      },
      borderRadius: AppSpacing.roundedMd,
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppSpacing.roundedMd,
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.copy_all_rounded, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exact Duplicate Files Engine',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Tiered SHA-256 / MD5 hashing with automated "Keep Original" protection.',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildOpportunityTile(
    BuildContext context,
    CleanupCandidateGroup group,
    bool isDark,
  ) {
    final isExact = group.type == CleanupCategoryType.exactDuplicates;
    final isDir = group.type == CleanupCategoryType.emptyFolders;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(group.type.icon, color: AppColors.primary, size: 24),
        ),
        title: Text(
          group.title,
          style: AppTypography.titleMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${group.itemCount} items • ${group.description}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isDir ? '${group.itemCount} dirs' : Formatters.formatFileSize(group.totalSize),
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
        onTap: () {
          if (isExact) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DuplicateReviewScreen()),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CleanupCategoryScreen(candidateGroup: group),
              ),
            );
          }
        },
      ),
    );
  }
}
