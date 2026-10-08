import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/timeline_models.dart';
import '../providers/clean_providers.dart';

/// Screen presenting files chronologically categorized by calendar periods
/// (Today, Yesterday, This Week, This Month, Earlier This Year, Past Years).
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  FileCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final timelineAsync = ref.watch(timelineGroupsProvider(_selectedCategory));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Timeline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Timeline',
            onPressed: () => ref.invalidate(timelineGroupsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All Files'),
                  selected: _selectedCategory == null,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = null;
                    });
                  },
                ),
                const SizedBox(width: AppSpacing.xs),
                ...[
                  FileCategory.image,
                  FileCategory.video,
                  FileCategory.document,
                  FileCategory.audio,
                  FileCategory.archive,
                ].map((cat) {
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: FilterChip(
                      avatar: Icon(cat.icon, size: 16, color: cat.color),
                      label: Text(cat.displayName),
                      selected: _selectedCategory == cat,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = selected ? cat : null;
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),

          // Timeline Content
          Expanded(
            child: timelineAsync.when(
              loading: () => const LoadingView(message: 'Assembling chronological timeline...'),
              error: (err, _) => ErrorView(
                message: 'Failed to load timeline: $err',
                onRetry: () => ref.invalidate(timelineGroupsProvider(_selectedCategory)),
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  return const EmptyView(
                    title: 'Timeline is Empty',
                    subtitle: 'No files match the active time period or category filter.',
                    icon: Icons.history_rounded,
                  );
                }

                return ListView.builder(
                  padding: AppSpacing.screenPadding,
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return _buildTimelineGroup(context, group, isDark);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineGroup(BuildContext context, TimelineGroup group, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _iconForBucket(group.bucket),
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    group.label,
                    style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.grey[200],
                  borderRadius: AppSpacing.roundedSm,
                ),
                child: Text(
                  '${group.count} files • ${Formatters.formatFileSize(group.totalBytes)}',
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Files in this group
        Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            children: group.files.map((file) {
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
                  style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('File: ${file.name} (${Formatters.formatFileSize(file.size)})')),
                  );
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  IconData _iconForBucket(TimelineBucket bucket) {
    return switch (bucket) {
      TimelineBucket.today => Icons.today_rounded,
      TimelineBucket.yesterday => Icons.history_rounded,
      TimelineBucket.thisWeek => Icons.date_range_rounded,
      TimelineBucket.thisMonth => Icons.calendar_month_rounded,
      TimelineBucket.earlierThisYear => Icons.calendar_today_rounded,
      TimelineBucket.pastYears => Icons.archive_outlined,
    };
  }
}
