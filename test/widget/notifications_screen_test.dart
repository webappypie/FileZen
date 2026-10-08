import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filezen/app/navigation/navigation_shell.dart';
import 'package:filezen/app/theme/app_theme.dart';
import 'package:filezen/domain/models/notification_models.dart';
import 'package:filezen/domain/models/storage_location.dart';
import 'package:filezen/domain/models/storage_intelligence_models.dart';
import 'package:filezen/domain/models/vault_models.dart';
import 'package:filezen/domain/repositories/i_permission_service.dart';
import 'package:filezen/domain/repositories/i_notification_repository.dart';
import 'package:filezen/features/ai/presentation/providers/ai_providers.dart';
import 'package:filezen/features/clean/presentation/providers/clean_providers.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/notifications/presentation/providers/notification_providers.dart';
import 'package:filezen/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:filezen/features/vault/presentation/providers/vault_providers.dart';

class _FakeNotificationRepository implements INotificationRepository {
  final List<AppNotification> _items;
  final StreamController<List<AppNotification>> _notifController =
      StreamController<List<AppNotification>>.broadcast();
  final StreamController<int> _unreadController =
      StreamController<int>.broadcast();

  _FakeNotificationRepository(List<AppNotification> initialItems)
      : _items = List.from(initialItems);

  void _emit() {
    _notifController.add(List.unmodifiable(_items));
    _unreadController.add(_items.where((i) => !i.isRead).length);
  }

  @override
  Future<List<AppNotification>> getNotifications() async => List.unmodifiable(_items);

  @override
  Stream<List<AppNotification>> watchNotifications() async* {
    yield List.unmodifiable(_items);
    yield* _notifController.stream;
  }

  @override
  Future<int> getUnreadCount() async => _items.where((i) => !i.isRead).length;

  @override
  Stream<int> watchUnreadCount() async* {
    yield _items.where((i) => !i.isRead).length;
    yield* _unreadController.stream;
  }

  @override
  Future<void> addNotification(AppNotification notification) async {
    _items.insert(0, notification);
    _emit();
  }

  @override
  Future<void> markAsRead(String id) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      _items[idx] = _items[idx].copyWith(isRead: true);
      _emit();
    }
  }

  @override
  Future<void> markAllAsRead() async {
    for (int i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(isRead: true);
    }
    _emit();
  }

  @override
  Future<void> deleteNotification(String id) async {
    _items.removeWhere((i) => i.id == id);
    _emit();
  }

  @override
  Future<void> clearAll() async {
    _items.clear();
    _emit();
  }

  @override
  Future<void> syncRemoteNotifications({bool isOnline = true}) async {}
}

class _FakePermissionNotifier extends StoragePermissionNotifier {
  _FakePermissionNotifier();

  @override
  Future<StoragePermissionStatus> build() async => StoragePermissionStatus.granted;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleNotifications = [
    AppNotification(
      id: 'notif_1',
      title: 'Welcome to FileZen',
      body: 'Your files, understood by AI.',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      isRead: false,
      type: NotificationType.system,
      priority: NotificationPriority.normal,
      actionRoute: '/settings',
      actionLabel: 'Settings',
    ),
    AppNotification(
      id: 'notif_2',
      title: 'Storage Optimization Ready',
      body: 'Check the Clean tab to review potential space-saving opportunities.',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      isRead: false,
      type: NotificationType.storage,
      priority: NotificationPriority.high,
      actionRoute: '/clean',
      actionLabel: 'Review Clean Hub',
    ),
    AppNotification(
      id: 'notif_3',
      title: 'AI Semantic Index Ready',
      body: 'On-device semantic indexing completed.',
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      isRead: true,
      type: NotificationType.ai,
      priority: NotificationPriority.normal,
      actionRoute: '/ai',
      actionLabel: 'Explore AI',
    ),
  ];

  Widget buildTestableWidget(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: child,
      ),
    );
  }

  group('NotificationsScreen Widget Tests', () {
    testWidgets('renders notifications screen with header, filter chips, and cards', (tester) async {
      final fakeRepo = _FakeNotificationRepository(sampleNotifications);

      await tester.pumpWidget(
        buildTestableWidget(
          const NotificationsScreen(),
          overrides: [
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Unread (2)'), findsOneWidget);
      expect(find.text('Storage'), findsOneWidget);
      expect(find.text('Welcome to FileZen'), findsOneWidget);
      expect(find.text('Storage Optimization Ready'), findsOneWidget);
      expect(find.text('AI Semantic Index Ready'), findsOneWidget);
      expect(find.text('Review Clean Hub'), findsOneWidget);
    });

    testWidgets('filters list by selecting filter chips', (tester) async {
      final fakeRepo = _FakeNotificationRepository(sampleNotifications);

      await tester.pumpWidget(
        buildTestableWidget(
          const NotificationsScreen(),
          overrides: [
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Unread
      await tester.tap(find.text('Unread (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to FileZen'), findsOneWidget);
      expect(find.text('Storage Optimization Ready'), findsOneWidget);
      expect(find.text('AI Semantic Index Ready'), findsNothing);

      // Switch to Storage
      await tester.tap(find.text('Storage'));
      await tester.pumpAndSettle();

      expect(find.text('Storage Optimization Ready'), findsOneWidget);
      expect(find.text('Welcome to FileZen'), findsNothing);
    });

    testWidgets('tapping Mark All as Read button marks all notifications as read', (tester) async {
      final fakeRepo = _FakeNotificationRepository(sampleNotifications);

      await tester.pumpWidget(
        buildTestableWidget(
          const NotificationsScreen(),
          overrides: [
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Mark All as Read'), findsOneWidget);

      await tester.tap(find.byTooltip('Mark All as Read'));
      await tester.pumpAndSettle();

      expect(await fakeRepo.getUnreadCount(), 0);
    });

    testWidgets('clear all notifications empties the list and displays EmptyView', (tester) async {
      final fakeRepo = _FakeNotificationRepository(sampleNotifications);

      await tester.pumpWidget(
        buildTestableWidget(
          const NotificationsScreen(),
          overrides: [
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Open menu
      await tester.tap(find.byTooltip('More Options'));
      await tester.pumpAndSettle();

      // Tap Clear All
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      // Confirmation dialog
      expect(find.text('Clear All Notifications?'), findsOneWidget);
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      expect(find.text('No Notifications'), findsOneWidget);
      expect(find.text('You are all caught up! Meaningful notifications will appear here.'), findsOneWidget);
    });

    testWidgets('tapping deep link action opens target screen', (tester) async {
      final fakeRepo = _FakeNotificationRepository(sampleNotifications);

      await tester.pumpWidget(
        buildTestableWidget(
          const NotificationsScreen(),
          overrides: [
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            storageOverviewProvider.overrideWith(
              (ref) => Future.value(const StorageOverview(
                totalBytes: 100,
                usedBytes: 50,
                freeBytes: 50,
                categorySizes: {},
                categoryCounts: {},
              )),
            ),
            cleanupOpportunitiesProvider.overrideWith((ref) => Future.value([])),
            exactDuplicatesProvider.overrideWith((ref) => Future.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap action button on Storage card
      await tester.tap(find.text('Review Clean Hub'));
      await tester.pumpAndSettle();

      // CleanScreen should now be mounted
      expect(find.text('Zero Silent Deletions Contract'), findsOneWidget);
    });
  });

  group('NavigationShell Notification Badge Tests', () {
    testWidgets('displays red badge dot when unreadCount > 0 and hides when unreadCount == 0', (tester) async {
      const fakeLocation = StorageLocation(
        id: 'test_internal',
        name: 'Internal Storage',
        path: '/mock/storage/emulated/0',
        totalBytes: 128 * 1024 * 1024 * 1024,
        freeBytes: 64 * 1024 * 1024 * 1024,
      );

      final fakeRepo = _FakeNotificationRepository(sampleNotifications);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            storagePermissionStateProvider.overrideWith(() => _FakePermissionNotifier()),
            storageLocationsProvider.overrideWith((ref) => Future.value([fakeLocation])),
            smartCollectionsProvider.overrideWith((ref) => Future.value([])),
            storageOverviewProvider.overrideWith(
              (ref) => Future.value(const StorageOverview(
                totalBytes: 100,
                usedBytes: 50,
                freeBytes: 50,
                categorySizes: {},
                categoryCounts: {},
              )),
            ),
            cleanupOpportunitiesProvider.overrideWith((ref) => Future.value([])),
            vaultSecurityConfigProvider.overrideWith(
              (ref) => Future.value(const VaultSecurityConfig(isPinConfigured: true)),
            ),
          ],
          child: const MaterialApp(
            home: NavigationShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unread count is initially 2 -> red dot container should be in the tree
      final badgeFinder = find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == Colors.redAccent,
      );
      expect(badgeFinder, findsOneWidget);

      // Mark all read
      await fakeRepo.markAllAsRead();
      await tester.pumpAndSettle();

      // Red dot container should now be gone!
      expect(badgeFinder, findsNothing);
    });
  });
}
