import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/storage_intelligence_models.dart';
import '../providers/clean_providers.dart';

/// Screen presenting deep-dive storage intelligence, category breakdown,
/// directory hierarchy treemap, largest files, and usage trends.
class StorageAnalysisScreen extends ConsumerWidget {
  const StorageAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final overviewAsync = ref.watch(storageOverviewProvider);
    final topFoldersAsync = ref.watch(topFoldersProvider);
    final largestFilesAsync = ref.watch(largestFilesProvider);
    final trendsAsync = ref.watch(storageTrendsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Intelligence'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Storage Metrics',
            onPressed: () {
              ref.invalidate(storageOverviewProvider);
              ref.invalidate(topFoldersProvider);
              ref.invalidate(largestFilesProvider);
              ref.invalidate(storageTrendsProvider);
            },
          ),
        ],
      ),
      body: overviewAsync.when(
        loading: () => const LoadingView(message: 'Analyzing internal storage structures...'),
        error: (err, _) => ErrorView(
          message: 'Unable to load storage overview: $err',
          onRetry: () => ref.invalidate(storageOverviewProvider),
        ),
        data: (overview) {
          return ListView(
            padding: AppSpacing.screenPadding,
            children: [
              // Main Storage Overview Ring & Metric Card
              _buildMainStorageCard(context, overview, isDark),
              const SizedBox(height: AppSpacing.lg),

              // Category Breakdown Section
              Text(
                'Category Occupancy',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildCategoryBreakdownCard(context, overview, isDark),
              const SizedBox(height: AppSpacing.lg),

              // Storage Growth & Usage Trends
              Text(
                'Usage Trends & History',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildTrendsSection(context, trendsAsync, isDark),
              const SizedBox(height: AppSpacing.lg),

              // Top Directories
              Text(
                'Top Space-Consuming Folders',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildTopFoldersSection(context, topFoldersAsync, isDark),
              const SizedBox(height: AppSpacing.lg),

              // Largest Individual Files
              Text(
                'Largest Files',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildLargestFilesSection(context, largestFilesAsync, isDark),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMainStorageCard(BuildContext context, StorageOverview overview, bool isDark) {
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Internal Storage',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      Formatters.formatFileSize(overview.usedBytes),
                      style: AppTypography.headlineMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'used of ${Formatters.formatFileSize(overview.totalBytes)}',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: AppSpacing.roundedMd,
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${overview.usedPercentage.toStringAsFixed(1)}%',
                        style: AppTypography.titleLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Occupied',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Segmented Progress Bar
            ClipRRect(
              borderRadius: AppSpacing.roundedSm,
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    ...FileCategory.values.map((cat) {
                      final size = overview.sizeForCategory(cat);
                      if (size <= 0) return const SizedBox.shrink();
                      final ratio = (size / overview.totalBytes).clamp(0.01, 1.0);
                      return Expanded(
                        flex: (ratio * 1000).toInt(),
                        child: Container(color: cat.color),
                      );
                    }),
                    // Free space segment
                    Expanded(
                      flex: ((overview.freeBytes / overview.totalBytes).clamp(0.01, 1.0) * 1000).toInt(),
                      child: Container(color: isDark ? Colors.grey[800] : Colors.grey[300]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${Formatters.formatFileSize(overview.freeBytes)} Available Free',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '100% On-Device Safe',
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdownCard(BuildContext context, StorageOverview overview, bool isDark) {
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          children: FileCategory.values.map((cat) {
            final size = overview.sizeForCategory(cat);
            final count = overview.countForCategory(cat);
            final percentage = overview.usedBytes > 0
                ? (size / overview.usedBytes * 100.0).toStringAsFixed(1)
                : '0.0';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: cat.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.displayName,
                          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '$count files • $percentage%',
                          style: AppTypography.labelSmall.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Formatters.formatFileSize(size),
                    style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTrendsSection(
    BuildContext context,
    AsyncValue<List<StorageTrendPoint>> trendsAsync,
    bool isDark,
  ) {
    return trendsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Trends unavailable: $e'),
      data: (points) {
        if (points.isEmpty) return const SizedBox.shrink();

        return Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Last 30 Days Growth',
                      style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.12),
                        borderRadius: AppSpacing.roundedSm,
                      ),
                      child: Text(
                        'Tracked Locally',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.info,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ...points.reversed.take(4).map((pt) {
                  final formattedDate =
                      '${pt.timestamp.month}/${pt.timestamp.day}/${pt.timestamp.year}';
                  final deltaStr = pt.changeDeltaBytes > 0
                      ? '+${Formatters.formatFileSize(pt.changeDeltaBytes)}'
                      : (pt.changeDeltaBytes < 0
                          ? '-${Formatters.formatFileSize(pt.changeDeltaBytes.abs())}'
                          : '0 B');

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formattedDate,
                          style: AppTypography.bodySmall,
                        ),
                        Text(
                          Formatters.formatFileSize(pt.usedBytes),
                          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          deltaStr,
                          style: AppTypography.labelSmall.copyWith(
                            color: pt.changeDeltaBytes > 0 ? AppColors.warning : AppColors.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopFoldersSection(
    BuildContext context,
    AsyncValue<List<FolderStorageItem>> topFoldersAsync,
    bool isDark,
  ) {
    return topFoldersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Unable to load folders: $e'),
      data: (folders) {
        if (folders.isEmpty) return const Text('No folder data available');

        return Card(
          child: Column(
            children: folders.map((f) {
              return ListTile(
                dense: true,
                leading: const Icon(Icons.folder_rounded, color: AppColors.warning),
                title: Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${f.fileCount} files • ${f.path}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    fontSize: 10,
                  ),
                ),
                trailing: Text(
                  Formatters.formatFileSize(f.sizeBytes),
                  style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w700),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildLargestFilesSection(
    BuildContext context,
    AsyncValue<List<dynamic>> largestFilesAsync,
    bool isDark,
  ) {
    return largestFilesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Unable to load largest files: $e'),
      data: (files) {
        if (files.isEmpty) return const Text('No large files recorded');

        return Card(
          child: Column(
            children: files.take(5).map((file) {
              return ListTile(
                dense: true,
                leading: Icon(file.category.icon, color: file.category.color),
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    fontSize: 10,
                  ),
                ),
                trailing: Text(
                  Formatters.formatFileSize(file.size),
                  style: AppTypography.labelSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
