import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:filezen/data/notifications/notification_repository.dart';
import 'package:filezen/domain/models/notification_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationRepository (Persistence, Streams, & Event Triggers)', () {
    late Directory tempDir;
    late String storagePath;
    late NotificationRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('notification_test_');
      storagePath = p.join(tempDir.path, 'notifications.json');
      repo = NotificationRepository(customStoragePath: storagePath);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('pre-seeds default starter notifications on fresh storage', () async {
      final list = await repo.getNotifications();
      expect(list.isNotEmpty, isTrue);
      expect(list.length, greaterThanOrEqualTo(3));

      final hasWelcome = list.any((n) => n.id == 'seed_welcome');
      final hasHygiene = list.any((n) => n.id == 'seed_hygiene');
      final hasAi = list.any((n) => n.id == 'seed_ai');

      expect(hasWelcome, isTrue);
      expect(hasHygiene, isTrue);
      expect(hasAi, isTrue);
    });

    test('calculates unread count correctly', () async {
      final list = await repo.getNotifications();
      final expectedUnread = list.where((n) => !n.isRead).length;

      final count = await repo.getUnreadCount();
      expect(count, expectedUnread);
      expect(count, greaterThan(0));
    });

    test('adds new notification, prepends to list, and emits stream updates', () async {
      final newNotification = AppNotification(
        id: 'custom_alert_1',
        title: 'New Storage Alert',
        body: 'Over 85% disk storage is occupied.',
        timestamp: DateTime.now(),
        isRead: false,
        type: NotificationType.storage,
        priority: NotificationPriority.high,
        actionRoute: '/clean',
        actionLabel: 'Review',
      );

      final unreadBefore = await repo.getUnreadCount();
      await repo.addNotification(newNotification);

      final list = await repo.getNotifications();
      expect(list.first.id, 'custom_alert_1');
      expect(list.first.title, 'New Storage Alert');

      final unreadAfter = await repo.getUnreadCount();
      expect(unreadAfter, unreadBefore + 1);
    });

    test('marks individual notification as read', () async {
      final list = await repo.getNotifications();
      final unreadItem = list.firstWhere((n) => !n.isRead);

      await repo.markAsRead(unreadItem.id);

      final updatedList = await repo.getNotifications();
      final updatedItem = updatedList.firstWhere((n) => n.id == unreadItem.id);
      expect(updatedItem.isRead, isTrue);
    });

    test('markAllAsRead sets all items to read and resets unread count to 0', () async {
      await repo.markAllAsRead();

      final list = await repo.getNotifications();
      for (final item in list) {
        expect(item.isRead, isTrue);
      }

      final unread = await repo.getUnreadCount();
      expect(unread, 0);
    });

    test('deletes individual notification', () async {
      final listBefore = await repo.getNotifications();
      final targetId = listBefore.first.id;

      await repo.deleteNotification(targetId);

      final listAfter = await repo.getNotifications();
      expect(listAfter.any((n) => n.id == targetId), isFalse);
      expect(listAfter.length, listBefore.length - 1);
    });

    test('clearAll removes all notifications', () async {
      await repo.clearAll();

      final list = await repo.getNotifications();
      expect(list.isEmpty, isTrue);

      final unread = await repo.getUnreadCount();
      expect(unread, 0);
    });

    test('persists items to disk and restores them on new repository instance', () async {
      final customItem = AppNotification(
        id: 'persisted_test_id',
        title: 'Persistence Verification',
        body: 'This must survive repository restarts.',
        timestamp: DateTime.now(),
        isRead: false,
        type: NotificationType.security,
      );

      await repo.addNotification(customItem);

      // Create a second repository pointing to the same storage file
      final secondRepo = NotificationRepository(customStoragePath: storagePath);
      final restoredList = await secondRepo.getNotifications();

      expect(restoredList.any((n) => n.id == 'persisted_test_id'), isTrue);
      final restoredItem = restoredList.firstWhere((n) => n.id == 'persisted_test_id');
      expect(restoredItem.title, 'Persistence Verification');
      expect(restoredItem.type, NotificationType.security);
    });

    test('handles offline synchronization safely without error', () async {
      // Must not throw exception when offline
      await expectLater(
        repo.syncRemoteNotifications(isOnline: false),
        completes,
      );
    });

    test('synchronizes remote announcement when online', () async {
      await repo.syncRemoteNotifications(isOnline: true);

      final list = await repo.getNotifications();
      final hasRemote = list.any((n) => n.id == 'remote_v1_announcement');
      expect(hasRemote, isTrue);
    });

    test('factory helpers generate structured event notifications', () {
      final storageAlert = NotificationRepository.createStorageWarning(
        usedRatio: 0.885,
        freeBytes: 15 * 1024 * 1024 * 1024,
      );
      expect(storageAlert.type, NotificationType.storage);
      expect(storageAlert.priority, NotificationPriority.high);
      expect(storageAlert.title, contains('88.5%'));
      expect(storageAlert.actionRoute, '/clean');

      final dupeAlert = NotificationRepository.createDuplicateDetectedAlert(
        duplicateCount: 14,
        recoverableBytes: 450 * 1024 * 1024,
      );
      expect(dupeAlert.type, NotificationType.storage);
      expect(dupeAlert.title, contains('14 Duplicate Files Found'));
      expect(dupeAlert.actionRoute, '/clean/duplicates');

      final vaultAlert = NotificationRepository.createVaultEventAlert(
        eventDescription: 'Session locked after timeout',
      );
      expect(vaultAlert.type, NotificationType.security);
      expect(vaultAlert.body, 'Session locked after timeout');
      expect(vaultAlert.actionRoute, '/vault');
    });
  });
}
