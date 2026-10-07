import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/empty_view.dart';

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  bool isRead;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<NotificationItem> _notifications = [
    NotificationItem(
      id: '1',
      title: 'Welcome to FileZen',
      body: 'Your files, understood by AI. All local operations work 100% offline.',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      isRead: false,
    ),
    NotificationItem(
      id: '2',
      title: 'Storage Optimization Ready',
      body: 'Check the Clean tab to review potential space-saving opportunities safely.',
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      isRead: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _notifications.clear());
              },
              child: const Text('Clear All'),
            ),
        ],
      ),
      body: _notifications.isEmpty
          ? const EmptyView(
              icon: Icons.notifications_none_rounded,
              title: 'No Notifications',
              subtitle: 'You are all caught up. Meaningful notifications will appear here.',
            )
          : ListView.separated(
              padding: AppSpacing.screenPadding,
              itemCount: _notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final item = _notifications[index];
                return Dismissible(
                  key: Key(item.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: AppSpacing.roundedMd,
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    setState(() => _notifications.removeAt(index));
                  },
                  child: Card(
                    color: item.isRead
                        ? null
                        : (isDark
                            ? AppColors.primaryDark.withValues(alpha: 0.1)
                            : AppColors.primary.withValues(alpha: 0.05)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      leading: Icon(
                        item.isRead ? Icons.mark_email_read_outlined : Icons.mark_email_unread_rounded,
                        color: item.isRead ? AppColors.lightTextSecondary : AppColors.primary,
                      ),
                      title: Text(
                        item.title,
                        style: AppTypography.titleMedium.copyWith(
                          fontSize: 15,
                          fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        item.body,
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                      onTap: () {
                        setState(() => item.isRead = true);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
