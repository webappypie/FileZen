import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../domain/models/notification_models.dart';
import '../providers/notification_providers.dart';

/// Horizontal scrolling filter chips allowing users to filter notifications by category or unread state.
class NotificationFilterChips extends ConsumerWidget {
  const NotificationFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFilter = ref.watch(notificationFilterProvider);
    final unreadCountAsync = ref.watch(unreadNotificationCountProvider);
    final unreadCount = unreadCountAsync.valueOrNull ?? 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: NotificationFilter.values.map((filter) {
          final isSelected = selectedFilter == filter;
          String label = filter.label;
          if (filter == NotificationFilter.unread && unreadCount > 0) {
            label = '${filter.label} ($unreadCount)';
          }

          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              showCheckmark: false,
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary : null,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
              onSelected: (_) {
                ref.read(notificationFilterProvider.notifier).state = filter;
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
