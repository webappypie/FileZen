import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../domain/models/cleanup_models.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../files/presentation/providers/storage_providers.dart';
import '../providers/clean_providers.dart';
import '../widgets/destructive_action_dialog.dart';

/// Screen allowing preview, review, and safe cleanup for any specific hygiene category.
class CleanupCategoryScreen extends ConsumerStatefulWidget {
  final CleanupCandidateGroup candidateGroup;

  const CleanupCategoryScreen({
    super.key,
    required this.candidateGroup,
  });

  @override
  ConsumerState<CleanupCategoryScreen> createState() => _CleanupCategoryScreenState();
}

class _CleanupCategoryScreenState extends ConsumerState<CleanupCategoryScreen> {
  late List<FileEntity> _items;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.candidateGroup.items);
    // Select all candidates by default for quick review
    for (final item in _items) {
      _selectedPaths.add(item.path);
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPaths.length == _items.length) {
        _selectedPaths.clear();
      } else {
        _selectedPaths.addAll(_items.map((i) => i.path));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDirCategory = widget.candidateGroup.type == CleanupCategoryType.emptyFolders;

    final selectedItems = _items.where((i) => _selectedPaths.contains(i.path)).toList();
    final totalSelectedBytes = selectedItems.fold<int>(0, (sum, i) => sum + i.size);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.candidateGroup.title),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(
                _selectedPaths.length == _items.length ? 'Deselect All' : 'Select All',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: _items.isEmpty
          ? EmptyView(
              title: 'No Items Found',
              subtitle: '${widget.candidateGroup.title} are completely cleaned up.',
              icon: Icons.check_circle_outline_rounded,
            )
          : Column(
              children: [
                // Info header banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  color: isDark ? Colors.grey[900] : Colors.grey[100],
                  child: Row(
                    children: [
                      Icon(widget.candidateGroup.type.icon, size: 20, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          widget.candidateGroup.description,
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Candidate Items List
                Expanded(
                  child: ListView.separated(
                    padding: AppSpacing.screenPadding,
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final isSelected = _selectedPaths.contains(item.path);

                      return ListTile(
                        leading: Checkbox(
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedPaths.add(item.path);
                              } else {
                                _selectedPaths.remove(item.path);
                              }
                            });
                          },
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          item.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelSmall.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                        trailing: Text(
                          isDirCategory ? 'Empty' : Formatters.formatFileSize(item.size),
                          style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
                ),

                // Bottom Action Bar
                if (selectedItems.isNotEmpty)
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
                                  '${selectedItems.length} Selected',
                                  style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (!isDirCategory)
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
                            onPressed: () => _confirmAndClean(context, selectedItems, totalSelectedBytes, isDirCategory),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _confirmAndClean(
    BuildContext context,
    List<FileEntity> selected,
    int totalBytes,
    bool isDirCategory,
  ) async {
    final decision = await DestructiveActionDialog.show(
      context,
      title: 'Clean ${widget.candidateGroup.title}',
      candidates: isDirCategory ? [] : selected,
      emptyFolderPaths: isDirCategory ? selected.map((i) => i.path).toList() : [],
      totalBytes: totalBytes,
      actionLabel: 'Clean Items',
      defaultMoveToTrash: !isDirCategory,
    );

    if (decision == null || !decision.confirmed) return;

    final dedupService = ref.read(deduplicationServiceProvider);
    final plan = CleanupExecutionPlan(
      selectedFiles: isDirCategory ? [] : selected,
      emptyFolderPaths: isDirCategory ? selected.map((i) => i.path).toList() : [],
      totalBytesToFree: totalBytes,
      moveToTrash: decision.moveToTrash,
    );

    final result = await dedupService.executeCleanup(plan);

    if (!context.mounted) return;

    setState(() {
      _items.removeWhere((i) => _selectedPaths.contains(i.path));
      _selectedPaths.clear();
    });

    ref.invalidate(cleanupOpportunitiesProvider);
    ref.invalidate(deviceStorageStatsProvider);
    ref.invalidate(storageOverviewProvider);
    ref.read(trashItemsProvider.notifier).refresh();

    final message = decision.moveToTrash
        ? 'Moved ${result.itemsCleaned} items to Recycle Bin (${Formatters.formatFileSize(result.bytesFreed)} freed)'
        : 'Cleaned ${result.itemsCleaned} items (${Formatters.formatFileSize(result.bytesFreed)} freed)';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
