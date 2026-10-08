import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/file_entity.dart';

/// Explicit confirmation dialog implementing the FileZen Destructive-Action Contract:
/// 1. Previews candidates
/// 2. Shows item count
/// 3. Shows size impact
/// 4. Requests explicit confirmation
/// 5. Uses recovery/trash where feasible
/// 6. Returns user decision
class DestructiveActionDialog extends StatefulWidget {
  final String title;
  final List<FileEntity> candidates;
  final List<String> emptyFolderPaths;
  final int totalBytes;
  final String actionLabel;
  final bool defaultMoveToTrash;

  const DestructiveActionDialog({
    super.key,
    required this.title,
    required this.candidates,
    this.emptyFolderPaths = const [],
    required this.totalBytes,
    this.actionLabel = 'Clean Now',
    this.defaultMoveToTrash = true,
  });

  static Future<({bool confirmed, bool moveToTrash})?> show(
    BuildContext context, {
    required String title,
    required List<FileEntity> candidates,
    List<String> emptyFolderPaths = const [],
    required int totalBytes,
    String actionLabel = 'Clean Now',
    bool defaultMoveToTrash = true,
  }) {
    return showDialog<({bool confirmed, bool moveToTrash})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DestructiveActionDialog(
        title: title,
        candidates: candidates,
        emptyFolderPaths: emptyFolderPaths,
        totalBytes: totalBytes,
        actionLabel: actionLabel,
        defaultMoveToTrash: defaultMoveToTrash,
      ),
    );
  }

  @override
  State<DestructiveActionDialog> createState() => _DestructiveActionDialogState();
}

class _DestructiveActionDialogState extends State<DestructiveActionDialog> {
  late bool _moveToTrash;

  @override
  void initState() {
    super.initState();
    _moveToTrash = widget.defaultMoveToTrash;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalItems = widget.candidates.length + widget.emptyFolderPaths.length;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _moveToTrash ? Icons.delete_sweep_outlined : Icons.warning_amber_rounded,
            color: _moveToTrash ? AppColors.warning : AppColors.error,
            size: 26,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              widget.title,
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Size impact and item count summary banner
            Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: (_moveToTrash ? AppColors.primary : AppColors.error).withValues(alpha: 0.1),
                borderRadius: AppSpacing.roundedSm,
                border: Border.all(
                  color: (_moveToTrash ? AppColors.primary : AppColors.error).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        '$totalItems',
                        style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Items Selected',
                        style: AppTypography.labelSmall.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    height: 32,
                    width: 1,
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                  ),
                  Column(
                    children: [
                      Text(
                        Formatters.formatFileSize(widget.totalBytes),
                        style: AppTypography.titleLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                      ),
                      Text(
                        'Space Freed',
                        style: AppTypography.labelSmall.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Candidate preview list (first few items)
            Text(
              'Candidate Preview (${widget.candidates.take(5).length} of $totalItems):',
              style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...widget.candidates.take(5).map(
                        (file) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 14, color: AppColors.secondary),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodySmall,
                                ),
                              ),
                              Text(
                                Formatters.formatFileSize(file.size),
                                style: AppTypography.labelSmall.copyWith(color: AppColors.lightTextSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ...widget.emptyFolderPaths.take(5).map(
                        (path) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_open_outlined, size: 14, color: AppColors.warning),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  path.split('/').last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodySmall,
                                ),
                              ),
                              Text(
                                'Empty Dir',
                                style: AppTypography.labelSmall.copyWith(color: AppColors.lightTextSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Safe Recovery Option Checkbox
            InkWell(
              onTap: () {
                setState(() {
                  _moveToTrash = !_moveToTrash;
                });
              },
              borderRadius: AppSpacing.roundedSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Checkbox(
                      value: _moveToTrash,
                      onChanged: (val) {
                        setState(() {
                          _moveToTrash = val ?? true;
                        });
                      },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Move to Recycle Bin (Safe & Recoverable)',
                            style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _moveToTrash
                                ? 'Items can be restored to original path at any time.'
                                : 'WARNING: Files will be permanently and irreversibly deleted.',
                            style: AppTypography.bodySmall.copyWith(
                              color: _moveToTrash
                                  ? (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)
                                  : AppColors.error,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop((confirmed: false, moveToTrash: _moveToTrash)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _moveToTrash ? AppColors.primary : AppColors.error,
          ),
          onPressed: () => Navigator.of(context).pop((confirmed: true, moveToTrash: _moveToTrash)),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
