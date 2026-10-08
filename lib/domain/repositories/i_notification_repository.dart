import '../models/notification_models.dart';

/// Repository interface managing local and remote in-app notifications.
abstract class INotificationRepository {
  /// Fetches the current list of all notifications, ordered newest first.
  Future<List<AppNotification>> getNotifications();

  /// Reactive stream broadcasting whenever notifications are added, updated, or deleted.
  Stream<List<AppNotification>> watchNotifications();

  /// Gets the count of unread notifications.
  Future<int> getUnreadCount();

  /// Reactive stream broadcasting unread notification count.
  Stream<int> watchUnreadCount();

  /// Adds a new notification to local storage and notifies listeners.
  Future<void> addNotification(AppNotification notification);

  /// Marks a specific notification as read.
  Future<void> markAsRead(String id);

  /// Marks all current notifications as read.
  Future<void> markAllAsRead();

  /// Deletes a specific notification permanently.
  Future<void> deleteNotification(String id);

  /// Clears all notifications.
  Future<void> clearAll();

  /// Synchronizes remote notifications if online; safely handles offline state without error.
  Future<void> syncRemoteNotifications({bool isOnline = true});
}
