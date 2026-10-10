import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/cleanup_models.dart';
import '../../../../domain/models/deduplication_models.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../files/presentation/providers/storage_providers.dart';
import '../providers/clean_providers.dart';
import '../widgets/destructive_action_dialog.dart';

/// Screen presenting exact duplicate clusters with "Keep Original" protection,
/// side-by-side comparison, smart selection, and safe cleanup.
class DuplicateReviewScreen extends ConsumerStatefulWidget {
  const DuplicateReviewScreen({super.key});

  @override
  ConsumerState<DuplicateReviewScreen> createState() => _DuplicateReviewScreenState();
}

class _DuplicateReviewScreenState extends ConsumerState<DuplicateReviewScreen> {
  final Set<String> _selectedFilePaths = {};
  bool _initializedSelection = false;

  void _initializeSmartSelection(List<DuplicateGroup> groups) {
    if (_initializedSelection) return;
    _selectedFilePaths.clear();
    // Default smart select: select all redundant copies, keep original untouched
    for (final group in groups) {
      for (final copy in group.duplicateFiles) {
        _selectedFilePaths.add(copy.path);
      }
    }
    _initializedSelection = true;
  }

  void _toggleSelectAllDuplicates(List<DuplicateGroup> groups) {
    setState(() {
      final allRedundantPaths = groups
          .expand((g) => g.duplicateFiles)
          .map((f) => f.path)
          .toSet();

      if (_selectedFilePaths.containsAll(allRedundantPaths)) {
        _selectedFilePaths.clear();
      } else {
        _selectedFilePaths.addAll(allRedundantPaths);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final duplicatesAsync = ref.watch(exactDuplicatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exact Duplicate Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rescan Duplicates',
            onPressed: () {
              setState(() {
                _initializedSelection = false;
                _selectedFilePaths.clear();
              });
              ref.invalidate(exactDuplicatesProvider);
            },
          ),
        ],
      ),
      body: duplicatesAsync.when(
        loading: () => const LoadingView(message: 'Computing cryptographic checksums and analyzing file clusters...'),
        error: (err, _) => ErrorView(
          message: 'Failed to scan duplicate files: $err',
          onRetry: () => ref.invalidate(exactDuplicatesProvider),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return const EmptyView(
              title: 'No Duplicate Files Found',
              subtitle: 'All files on your storage are unique. Zero redundant space detected.',
              icon: Icons.check_circle_outline_rounded,
            );
          }

          if (!_initializedSelection) {
            _initializeSmartSelection(groups);
          }

          final allRedundantFiles = groups.expand((g) => g.duplicateFiles).toList();
          final selectedFiles = allRedundantFiles
              .where((f) => _selectedFilePaths.contains(f.path))
              .toList();
          final totalSelectedBytes = selectedFiles.fold<int>(0, (sum, f) => sum + f.size);

          return Column(
            children: [
              // Summary and Smart-Select Header Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                color: isDark ? Colors.grey[900] : Colors.grey[100],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${groups.length} Duplicate Sets',
                          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${allRedundantFiles.length} redundant copies found',
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      icon: Icon(
                        _selectedFilePaths.length == allRedundantFiles.length
                            ? Icons.deselect_rounded
                            : Icons.auto_awesome_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      label: Text(
                        _selectedFilePaths.length == allRedundantFiles.length
                            ? 'Deselect All'
                            : 'Smart Select Copies',
                      ),
                      onPressed: () => _toggleSelectAllDuplicates(groups),
                    ),
                  ],
                ),
              ),

              // Duplicate Clusters List
              Expanded(
                child: ListView.builder(
                  padding: AppSpacing.screenPadding,
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return _buildGroupCard(context, group, isDark);
                  },
                ),
              ),

              // Bottom Clean Action Bar
              if (selectedFiles.isNotEmpty)
                SafeArea(
                  child: Container(
                    padding: AppSpacing.cardPadding,
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${selectedFiles.length} Copies Selected',
                                style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Free up ${Formatters.formatFileSize(totalSelectedBytes)}',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                          ),
                          icon: const Icon(Icons.delete_sweep_rounded),
                          label: const Text('Clean Selected'),
                          onPressed: () => _confirmAndClean(context, selectedFiles, totalSelectedBytes),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupCard(BuildContext context, DuplicateGroup group, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.roundedMd,
        side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group header: checksum and size
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fingerprint_rounded, size: 16, color: AppColors.secondary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      group.checksum.length > 12 ? '${group.checksum.substring(0, 12)}...' : group.checksum,
                      style: AppTypography.labelSmall.copyWith(
                        fontFamily: 'monospace',
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: AppSpacing.roundedSm,
                  ),
                  child: Text(
                    'Save ${Formatters.formatFileSize(group.recoverableSize)}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: AppSpacing.lg),

            // 1. Primary Original File (Keep)
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.06),
                borderRadius: AppSpacing.roundedSm,
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: AppSpacing.roundedSm,
                    ),
                    child: Text(
                      'KEEP ORIGINAL',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.primaryFile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          group.primaryFile.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelSmall.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Formatters.formatFileSize(group.fileSize),
                    style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // 2. Redundant Duplicate Copies (Selectable)
            ...group.duplicateFiles.map((copy) {
              final isSelected = _selectedFilePaths.contains(copy.path);
              return Container(
                margin: const EdgeInsets.only(top: AppSpacing.xs),
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedFilePaths.add(copy.path);
                          } else {
                            _selectedFilePaths.remove(copy.path);
                          }
                        });
                      },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            copy.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall,
                          ),
                          Text(
                            copy.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSmall.copyWith(
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      Formatters.formatFileSize(copy.size),
                      style: AppTypography.labelSmall.copyWith(color: AppColors.lightTextSecondary),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndClean(
    BuildContext context,
    List<FileEntity> filesToClean,
    int totalBytes,
  ) async {
    final decision = await DestructiveActionDialog.show(
      context,
      title: 'Clean Duplicate Files',
      candidates: filesToClean,
      totalBytes: totalBytes,
      actionLabel: 'Clean Duplicates',
      defaultMoveToTrash: true,
    );

    if (decision == null || !decision.confirmed) return;

    final dedupService = ref.read(deduplicationServiceProvider);
    final plan = CleanupExecutionPlan(
      selectedFiles: filesToClean,
      totalBytesToFree: totalBytes,
      moveToTrash: decision.moveToTrash,
    );

    final result = await dedupService.executeCleanup(plan);

    if (!context.mounted) return;

    // Refresh state
    setState(() {
      _selectedFilePaths.clear();
      _initializedSelection = false;
    });
    ref.invalidate(exactDuplicatesProvider);
    ref.invalidate(cleanupOpportunitiesProvider);
    ref.invalidate(deviceStorageStatsProvider);
    ref.invalidate(storageOverviewProvider);
    ref.read(trashItemsProvider.notifier).refresh();

    final message = decision.moveToTrash
        ? 'Safely moved ${result.itemsCleaned} duplicates to Recycle Bin (${Formatters.formatFileSize(result.bytesFreed)} freed)'
        : 'Permanently deleted ${result.itemsCleaned} duplicates (${Formatters.formatFileSize(result.bytesFreed)} freed)';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: decision.moveToTrash
            ? SnackBarAction(
                label: 'View Trash',
                onPressed: () {
                  // Navigate to Trash
                },
              )
            : null,
      ),
    );
  }
}
