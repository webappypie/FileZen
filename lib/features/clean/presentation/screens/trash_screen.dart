import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/trash_item.dart';
import '../providers/clean_providers.dart';

/// Screen presenting files currently residing in the Recycle Bin / Trash with 1-click restoration.
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  final Set<String> _selectedIds = {};

  void _toggleSelectAll(List<TrashItem> items) {
    setState(() {
      if (_selectedIds.length == items.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(items.map((i) => i.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final trashAsync = ref.watch(trashItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin (Trash)'),
        actions: [
          trashAsync.maybeWhen(
            data: (items) => items.isNotEmpty
                ? PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'empty') {
                        _confirmEmptyTrash(context);
                      } else if (val == 'select_all') {
                        _toggleSelectAll(items);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'select_all',
                        child: Text(_selectedIds.length == items.length ? 'Deselect All' : 'Select All'),
                      ),
                      const PopupMenuItem(
                        value: 'empty',
                        child: Text(
                          'Empty Recycle Bin',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: trashAsync.when(
        loading: () => const LoadingView(message: 'Loading recycle bin items...'),
        error: (err, _) => ErrorView(
          message: 'Unable to access recycle bin: $err',
          onRetry: () => ref.read(trashItemsProvider.notifier).refresh(),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'Recycle Bin is Empty',
              subtitle: 'No files are currently in the Recycle Bin. Files moved here during cleanup can be restored anytime.',
              icon: Icons.delete_outline_rounded,
            );
          }

          final selectedItems = items.where((i) => _selectedIds.contains(i.id)).toList();
          final totalTrashBytes = items.fold<int>(0, (sum, i) => sum + i.size);

          return Column(
            children: [
              // Safe Recovery Contract Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                color: AppColors.info.withValues(alpha: isDark ? 0.15 : 0.08),
                child: Row(
                  children: [
                    const Icon(Icons.security_update_good_rounded, color: AppColors.info, size: 22),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Safe Recovery Active (${Formatters.formatFileSize(totalTrashBytes)} total)',
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.info,
                            ),
                          ),
                          Text(
                            'Files can be restored back to their exact original folder at any time.',
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Items List
              Expanded(
                child: ListView.separated(
                  padding: AppSpacing.screenPadding,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = _selectedIds.contains(item.id);

                    return ListTile(
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedIds.add(item.id);
                            } else {
                              _selectedIds.remove(item.id);
                            }
                          });
                        },
                      ),
                      title: Text(
                        item.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Original: ${item.originalPath}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSmall.copyWith(
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            'Deleted: ${item.trashedAt.month}/${item.trashedAt.day}/${item.trashedAt.year} • ${Formatters.formatFileSize(item.size)}',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.restore_rounded, color: AppColors.success),
                            tooltip: 'Restore to original path',
                            onPressed: () => _restoreItem(context, item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
                            tooltip: 'Permanently delete',
                            onPressed: () => _confirmPermanentDelete(context, item),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Bottom Batch Action Bar
              if (selectedItems.isNotEmpty)
                SafeArea(
                  child: Container(
                    padding: AppSpacing.cardPadding,
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${selectedItems.length} Selected',
                          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.restore_rounded, size: 18),
                          label: const Text('Restore All'),
                          onPressed: () => _batchRestore(context, selectedItems),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                          icon: const Icon(Icons.delete_forever_rounded, size: 18),
                          label: const Text('Delete'),
                          onPressed: () => _batchPermanentDelete(context, selectedItems),
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

  Future<void> _restoreItem(BuildContext context, TrashItem item) async {
    final success = await ref.read(trashItemsProvider.notifier).restore(item);
    if (!context.mounted) return;
    if (success) {
      setState(() => _selectedIds.remove(item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored ${item.fileName} to ${item.originalPath}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restore ${item.fileName}')),
      );
    }
  }

  Future<void> _batchRestore(BuildContext context, List<TrashItem> items) async {
    final success = await ref.read(trashItemsProvider.notifier).batchRestore(items);
    if (!context.mounted) return;
    if (success) {
      setState(() => _selectedIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully restored ${items.length} files')),
      );
    }
  }

  Future<void> _confirmPermanentDelete(BuildContext context, TrashItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Permanently Delete File?'),
        content: Text('Are you sure you want to permanently delete "${item.fileName}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(trashItemsProvider.notifier).permanentlyDelete(item);
      if (!context.mounted) return;
      setState(() => _selectedIds.remove(item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permanently deleted ${item.fileName}')),
      );
    }
  }

  Future<void> _batchPermanentDelete(BuildContext context, List<TrashItem> items) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Permanently Delete Selected Files?'),
        content: Text('Are you sure you want to delete ${items.length} files forever? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(trashItemsProvider.notifier).batchPermanentlyDelete(items);
      if (!context.mounted) return;
      setState(() => _selectedIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permanently deleted ${items.length} files')),
      );
    }
  }

  Future<void> _confirmEmptyTrash(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Empty Recycle Bin?'),
        content: const Text(
          'All files in the Recycle Bin will be permanently and irreversibly purged from storage. Do you wish to proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Empty Bin'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(trashItemsProvider.notifier).emptyTrash();
      if (!context.mounted) return;
      setState(() => _selectedIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recycle Bin emptied successfully')),
      );
    }
  }
}
