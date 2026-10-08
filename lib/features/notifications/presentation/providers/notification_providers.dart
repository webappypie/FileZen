import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/notifications/notification_repository.dart';
import '../../../../domain/models/notification_models.dart';
import '../../../../domain/repositories/i_notification_repository.dart';

/// Provider for INotificationRepository instance.
final notificationRepositoryProvider = Provider<INotificationRepository>((ref) {
  return NotificationRepository();
});

/// Reactive stream provider for all notifications.
final notificationsStreamProvider = StreamProvider<List<AppNotification>>((ref) {
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.watchNotifications();
});

/// Reactive stream provider for unread count.
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.watchUnreadCount();
});

/// State provider for selected notification filter tab.
final notificationFilterProvider = StateProvider<NotificationFilter>((ref) {
  return NotificationFilter.all;
});

/// Filtered list of notifications according to the selected filter tab.
final filteredNotificationsProvider = Provider<AsyncValue<List<AppNotification>>>((ref) {
  final notificationsAsync = ref.watch(notificationsStreamProvider);
  final filter = ref.watch(notificationFilterProvider);

  return notificationsAsync.whenData((list) {
    switch (filter) {
      case NotificationFilter.all:
        return list;
      case NotificationFilter.unread:
        return list.where((n) => !n.isRead).toList();
      case NotificationFilter.storage:
        return list.where((n) => n.type == NotificationType.storage).toList();
      case NotificationFilter.security:
        return list.where((n) => n.type == NotificationType.security).toList();
      case NotificationFilter.ai:
        return list.where((n) => n.type == NotificationType.ai).toList();
      case NotificationFilter.system:
        return list.where((n) => n.type == NotificationType.system).toList();
    }
  });
});

/// Controller providing actions on notifications.
class NotificationController {
  final INotificationRepository _repo;

  NotificationController(this._repo);

  Future<void> markAsRead(String id) => _repo.markAsRead(id);
  Future<void> markAllAsRead() => _repo.markAllAsRead();
  Future<void> deleteNotification(String id) => _repo.deleteNotification(id);
  Future<void> clearAll() => _repo.clearAll();
  Future<void> syncRemoteNotifications({bool isOnline = true}) =>
      _repo.syncRemoteNotifications(isOnline: isOnline);
  Future<void> addNotification(AppNotification notification) =>
      _repo.addNotification(notification);
}

final notificationControllerProvider = Provider<NotificationController>((ref) {
  final repo = ref.watch(notificationRepositoryProvider);
  return NotificationController(repo);
});
