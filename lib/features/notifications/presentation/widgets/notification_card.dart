import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/models/notification_models.dart';

/// Interactive card presenting an in-app notification with dismissible swipe,
/// read/unread visual styling, and optional action button.
class NotificationCard extends StatelessWidget {
  final AppNotification item;
  final VoidCallback onTap;
  final VoidCallback onDismissed;
  final VoidCallback? onActionPressed;

  const NotificationCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDismissed,
    this.onActionPressed,
  });

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: AppSpacing.roundedMd,
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
      ),
      onDismissed: (_) => onDismissed(),
      child: Card(
        elevation: item.isRead ? 0 : 1,
        color: item.isRead
            ? null
            : (isDark
                ? item.type.color.withValues(alpha: 0.12)
                : item.type.color.withValues(alpha: 0.06)),
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.roundedMd,
          side: BorderSide(
            color: item.isRead
                ? (isDark ? Colors.white10 : Colors.black12)
                : item.type.color.withValues(alpha: 0.35),
            width: item.isRead ? 0.5 : 1.2,
          ),
        ),
        child: InkWell(
          borderRadius: AppSpacing.roundedMd,
          onTap: onTap,
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: Icon, Category Badge, Timestamp, Unread Dot
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: item.type.color.withValues(alpha: isDark ? 0.25 : 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.type.icon,
                        color: item.type.color,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      item.type.displayName.toUpperCase(),
                      style: AppTypography.labelSmall.copyWith(
                        color: item.type.color,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatRelativeTime(item.timestamp),
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (!item.isRead) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item.type.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // Title
                Text(
                  item.title,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: item.isRead ? FontWeight.w600 : FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),

                // Body
                Text(
                  item.body,
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    height: 1.35,
                  ),
                ),

                // Optional Action Button
                if (item.actionLabel != null && onActionPressed != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: item.type.color,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                      label: Text(
                        item.actionLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      onPressed: onActionPressed,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
