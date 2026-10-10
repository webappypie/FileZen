import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/navigation/navigation_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/file_thumbnail_widget.dart';
import '../../../../data/wapcentral/wap_client_provider.dart';
import '../../../../domain/models/ai_models.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/repositories/i_wap_service.dart';
import '../../../ai/presentation/providers/ai_providers.dart';
import '../../../ai/presentation/screens/collection_detail_screen.dart';
import '../../../clean/presentation/screens/storage_analysis_screen.dart';
import '../../../cloud/presentation/screens/cloud_sources_screen.dart';
import '../../../files/presentation/providers/category_files_providers.dart';
import '../../../files/presentation/providers/storage_providers.dart';
import '../../../files/presentation/resolvers/file_viewer_resolver.dart';
import '../../../files/presentation/screens/category_files_screen.dart';
import '../../../monitoring/presentation/widgets/filezen_ad_banner.dart';
import '../../../transfer/presentation/screens/network_hub_screen.dart';

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
                  _buildStorageOverviewCard(context, ref, isDark),
                  const SizedBox(height: AppSpacing.lg),

                  // Quick File Categories
                  Text(
                    'Categories',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildCategoriesGrid(context, ref, isDark),
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
                  _buildSmartCollectionsCard(context, ref, isDark),
                  const SizedBox(height: AppSpacing.lg),

                  // Ask Your Files Entry Point
                  _buildAskYourFilesCard(context, ref, isDark),
                  const SizedBox(height: AppSpacing.lg),

                  // Network Transfer & Cloud Sources Section
                  _buildNetworkCloudSection(context, isDark),
                  const SizedBox(height: AppSpacing.md),

                  // Non-intrusive Ad/Promo banner (collapses if ad-free or offline)
                  const FileZenAdBanner(),
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

  /// Device storage card. Reads the shared [deviceStorageStatsProvider] — the
  /// same measurement Storage Intelligence uses — so both screens agree.
  Widget _buildStorageOverviewCard(BuildContext context, WidgetRef ref, bool isDark) {
    final statsAsync = ref.watch(deviceStorageStatsProvider);
    final stats = statsAsync.valueOrNull;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final tertiary = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

    final String headline;
    final String footer;
    if (statsAsync.isLoading && stats == null) {
      headline = 'Measuring storage…';
      footer = '';
    } else if (stats == null) {
      headline = 'Device storage unavailable';
      footer = 'Open Analysis for indexed file totals';
    } else {
      headline =
          '${Formatters.formatFileSize(stats.usedBytes)} used of ${Formatters.formatFileSize(stats.totalBytes)}';
      footer = '${Formatters.formatFileSize(stats.freeBytes)} free';
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StorageAnalysisScreen()),
        );
      },
      borderRadius: AppSpacing.roundedMd,
      child: Card(
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
                          style: AppTypography.labelLarge.copyWith(color: secondary),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          headline,
                          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  if (stats != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: AppSpacing.roundedSm,
                      ),
                      child: Text(
                        '${stats.usedPercentLabel}%',
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
                  // Indeterminate only while the first measurement is in flight.
                  value: stats?.usedRatio ?? (statsAsync.isLoading ? null : 0),
                  minHeight: 8,
                  backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      footer,
                      style: AppTypography.bodySmall.copyWith(color: tertiary),
                    ),
                  ),
                  Text(
                    'Analysis →',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesGrid(BuildContext context, WidgetRef ref, bool isDark) {
    final countsAsync = ref.watch(categoryFileCountsProvider);
    final counts = countsAsync.valueOrNull ?? {};

    final categories = [
      ('Images', Icons.image_rounded, AppColors.typeImage, FileCategory.image, counts['Images'] ?? 0),
      ('Videos', Icons.movie_rounded, AppColors.typeVideo, FileCategory.video, counts['Videos'] ?? 0),
      ('Audio', Icons.headphones_rounded, AppColors.typeAudio, FileCategory.audio, counts['Audio'] ?? 0),
      ('Documents', Icons.description_rounded, AppColors.typeDocument, FileCategory.document, counts['Documents'] ?? 0),
      ('Downloads', Icons.download_rounded, AppColors.primary, null, counts['Downloads'] ?? 0),
      ('Archives', Icons.archive_rounded, AppColors.typeArchive, FileCategory.archive, counts['Archives'] ?? 0),
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
        final (title, icon, color, category, count) = categories[index];
        final countText = countsAsync.isLoading
            ? '...'
            : '$count item${count == 1 ? '' : 's'}';

        return Card(
          child: InkWell(
            borderRadius: AppSpacing.roundedMd,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CategoryFilesScreen(
                    category: category,
                    categoryTitle: title,
                    isDownloads: title == 'Downloads',
                  ),
                ),
              );
            },
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
                    countText,
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

  Widget _buildSmartCollectionsCard(BuildContext context, WidgetRef ref, bool isDark) {
    const receiptsCol = SmartCollection(
      id: 'invoices_receipts',
      title: 'Invoices & Receipts',
      description: 'Financial receipts, invoices, statements, and payment confirmations',
      ruleType: SmartCollectionRuleType.receiptsAndInvoices,
      iconCodePoint: 0xf00b8,
      colorHex: 0xFF10B981,
    );
    final filesAsync = ref.watch(collectionFilesProvider('invoices_receipts'));
    final files = filesAsync.valueOrNull ?? [];

    return Card(
      child: InkWell(
        borderRadius: AppSpacing.roundedMd,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CollectionDetailScreen(collection: receiptsCol),
            ),
          );
        },
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          filesAsync.isLoading
                              ? 'Checking indexed receipts...'
                              : (files.isEmpty
                                  ? '0 documents • Scanned automatically when invoices/receipts are indexed'
                                  : '${files.length} document${files.length == 1 ? '' : 's'} automatically grouped without moving files'),
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                ],
              ),
              if (files.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.xs),
                ...files.take(2).map(
                  (file) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: FileThumbnailWidget(file: file, size: 36),
                    title: Text(
                      file.name,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${Formatters.formatFileSize(file.size)} • ${Formatters.formatDate(file.modifiedAt)}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                    onTap: () => FileViewerResolver.openFile(context, ref, file, files),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAskYourFilesCard(BuildContext context, WidgetRef ref, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
      child: InkWell(
        borderRadius: AppSpacing.roundedMd,
        onTap: () {
          ref.read(currentTabProvider.notifier).state = 2;
        },
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
              const Icon(Icons.arrow_forward_rounded, color: AppColors.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkCloudSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Network & Cloud',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'LAN • WebDAV',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Card(
                child: InkWell(
                  borderRadius: AppSpacing.roundedMd,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NetworkHubScreen(),
                      ),
                    );
                  },
                  child: Padding(
                    padding: AppSpacing.cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.wifi_tethering_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Wi-Fi Share & LAN',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Browser link & WebDAV',
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Card(
                child: InkWell(
                  borderRadius: AppSpacing.roundedMd,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CloudSourcesScreen(),
                      ),
                    );
                  },
                  child: Padding(
                    padding: AppSpacing.cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.cloud_queue_rounded,
                            color: AppColors.accent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Cloud Drives',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Not available yet',
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
