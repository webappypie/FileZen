import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../domain/models/notification_models.dart';
import '../../../ai/presentation/screens/ai_screen.dart';
import '../../../clean/presentation/screens/clean_screen.dart';
import '../../../clean/presentation/screens/duplicate_review_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../vault/presentation/screens/vault_screen.dart';
import '../providers/notification_providers.dart';
import '../widgets/notification_card.dart';
import '../widgets/notification_filter_chips.dart';

/// Notifications Center screen allowing users to inspect, filter, dismiss,
/// and take action on meaningful application events and system notices.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  void _handleDeepLink(BuildContext context, WidgetRef ref, AppNotification item) {
    ref.read(notificationControllerProvider).markAsRead(item.id);

    final route = item.actionRoute;
    if (route == null) return;

    Widget? targetScreen;
    if (route == '/clean') {
      targetScreen = const CleanScreen();
    } else if (route == '/clean/duplicates') {
      targetScreen = const DuplicateReviewScreen();
    } else if (route == '/vault') {
      targetScreen = const VaultScreen();
    } else if (route == '/ai') {
      targetScreen = const AiScreen();
    } else if (route == '/settings') {
      targetScreen = const SettingsScreen();
    }

    if (targetScreen != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => targetScreen!),
      );
    }
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Notifications?'),
        content: const Text('This will delete all notification cards from your history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(notificationControllerProvider).clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredAsync = ref.watch(filteredNotificationsProvider);
    final unreadCountAsync = ref.watch(unreadNotificationCountProvider);
    final unreadCount = unreadCountAsync.valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all_rounded),
              tooltip: 'Mark All as Read',
              onPressed: () {
                ref.read(notificationControllerProvider).markAllAsRead();
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More Options',
            onSelected: (val) {
              if (val == 'clear') {
                _confirmClearAll(context, ref);
              } else if (val == 'sync') {
                ref.read(notificationControllerProvider).syncRemoteNotifications(isOnline: true);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 20),
                    SizedBox(width: AppSpacing.sm),
                    Text('Clear All'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sync',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, size: 20),
                    SizedBox(width: AppSpacing.sm),
                    Text('Check Updates'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const NotificationFilterChips(),
          const Divider(height: 1),
          Expanded(
            child: filteredAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading notifications: $err')),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyView(
                    icon: Icons.notifications_none_rounded,
                    title: 'No Notifications',
                    subtitle: 'You are all caught up! Meaningful notifications will appear here.',
                  );
                }

                return ListView.separated(
                  padding: AppSpacing.screenPadding,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return NotificationCard(
                      item: item,
                      onTap: () {
                        if (!item.isRead) {
                          ref.read(notificationControllerProvider).markAsRead(item.id);
                        }
                      },
                      onDismissed: () {
                        ref.read(notificationControllerProvider).deleteNotification(item.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Dismissed: ${item.title}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      onActionPressed: item.actionRoute != null
                          ? () => _handleDeepLink(context, ref, item)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
