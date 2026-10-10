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
import '../../../files/presentation/providers/storage_providers.dart';
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
              ref.invalidate(deviceStorageStatsProvider);
              ref.invalidate(storageOverviewProvider);
              ref.invalidate(topFoldersProvider);
              ref.invalidate(largestFilesProvider);
              ref.invalidate(storageTrendsProvider);
            },
          ),
        ],
      ),
      body: overviewAsync.when(
        loading: () => const LoadingView(message: 'Measuring storage...'),
        error: (err, _) => ErrorView(
          message: 'Unable to load storage overview: $err',
          onRetry: () => ref.invalidate(deviceStorageStatsProvider),
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

  /// Device usage (the shared OS measurement, identical to the Home card) and,
  /// separately, the total of indexed files. The bar shows indexed categories,
  /// then "System, apps & not indexed" (device used minus indexed), then free.
  Widget _buildMainStorageCard(BuildContext context, StorageOverview overview, bool isDark) {
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final hasTotals = overview.hasDeviceTotals && overview.totalBytes > 0;

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Internal Storage',
                        style: AppTypography.bodySmall.copyWith(color: secondary),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        hasTotals ? Formatters.formatFileSize(overview.usedBytes) : 'Unavailable',
                        style: AppTypography.headlineMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        hasTotals
                            ? 'used of ${Formatters.formatFileSize(overview.totalBytes)}'
                            : 'Device capacity could not be measured',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (hasTotals)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: AppSpacing.roundedMd,
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${overview.usedPercentLabel}%',
                          style: AppTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'Used',
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
            if (hasTotals) ...[
              const SizedBox(height: AppSpacing.md),
              _buildSegmentedBar(overview, isDark),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (hasTotals)
              Text(
                '${Formatters.formatFileSize(overview.freeBytes)} free',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Indexed files: ${Formatters.formatFileSize(overview.indexedBytes)} '
              '(${overview.indexedFileCount} files)',
              style: AppTypography.bodySmall.copyWith(color: secondary),
            ),
            if (hasTotals)
              Text(
                'System, apps & not indexed: ${Formatters.formatFileSize(overview.unindexedUsedBytes)}',
                style: AppTypography.bodySmall.copyWith(color: secondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedBar(StorageOverview overview, bool isDark) {
    final total = overview.totalBytes;
    int flexOf(int bytes) => bytes <= 0 ? 0 : ((bytes / total) * 1000).ceil();

    final segments = <Widget>[
      for (final cat in FileCategory.values)
        if (flexOf(overview.sizeForCategory(cat)) > 0)
          Expanded(
            flex: flexOf(overview.sizeForCategory(cat)),
            child: Container(color: cat.color),
          ),
      if (flexOf(overview.unindexedUsedBytes) > 0)
        Expanded(
          flex: flexOf(overview.unindexedUsedBytes),
          child: Container(color: isDark ? Colors.grey[600] : Colors.grey[500]),
        ),
      if (flexOf(overview.freeBytes) > 0)
        Expanded(
          flex: flexOf(overview.freeBytes),
          child: Container(color: isDark ? Colors.grey[800] : Colors.grey[300]),
        ),
    ];

    return ClipRRect(
      borderRadius: AppSpacing.roundedSm,
      child: SizedBox(height: 12, child: Row(children: segments)),
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
            // Share of the indexed total (not of device usage).
            final indexed = overview.indexedBytes;
            final percentage = indexed > 0
                ? (size / indexed * 100.0).toStringAsFixed(1)
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
                          '$count files • $percentage% of indexed',
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
        if (points.length < 2) {
          return Text(
            'History builds up from real measurements (one every 12 hours while you use FileZen).',
            style: AppTypography.bodySmall.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          );
        }

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
                      'Recent Usage',
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
        if (folders.isEmpty) return const Text('No indexed files yet');

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
        if (files.isEmpty) return const Text('No indexed files yet');

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
