import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/notification_models.dart';
import '../../domain/repositories/i_notification_repository.dart';

/// Implementation of INotificationRepository supporting local JSON file persistence,
/// reactive live streams, pre-seeded meaningful events, and safe offline synchronization.
class NotificationRepository implements INotificationRepository {
  final String? customStoragePath;

  NotificationRepository({this.customStoragePath});

  final StreamController<List<AppNotification>> _notificationsController =
      StreamController<List<AppNotification>>.broadcast();

  final StreamController<int> _unreadCountController =
      StreamController<int>.broadcast();

  List<AppNotification>? _cachedItems;
  bool _initialized = false;

  Future<File> _getStorageFile() async {
    if (customStoragePath != null) {
      final file = File(customStoragePath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, '.filezen_notifications.json'));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized && _cachedItems != null) return;

    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final text = await file.readAsString();
        if (text.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(text) as List<dynamic>;
          _cachedItems = jsonList
              .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      AppLogger.warning('Failed to load notifications from disk: $e', 'Notifications');
    }

    // Pre-seed starter notifications if storage is empty
    _cachedItems ??= _generateDefaultNotifications();
    _initialized = true;
    _emitUpdate();
  }

  List<AppNotification> _generateDefaultNotifications() {
    final now = DateTime.now();
    return [
      AppNotification(
        id: 'seed_welcome',
        title: 'Welcome to FileZen',
        body: 'Your files, understood by AI. All local operations work 100% offline without telemetry leakage.',
        timestamp: now.subtract(const Duration(minutes: 10)),
        isRead: false,
        type: NotificationType.system,
        priority: NotificationPriority.normal,
        actionRoute: '/settings',
        actionLabel: 'Settings',
      ),
      AppNotification(
        id: 'seed_hygiene',
        title: 'Zero Silent Deletions Contract',
        body: 'Storage cleaning is always explicit. Duplicate detection leaves your original files safe.',
        timestamp: now.subtract(const Duration(hours: 1)),
        isRead: false,
        type: NotificationType.storage,
        priority: NotificationPriority.high,
        actionRoute: '/clean',
        actionLabel: 'Review Clean Hub',
      ),
      AppNotification(
        id: 'seed_ai',
        title: 'On-Device AI Engine Ready',
        body: 'Natural language search, semantic concept matching, and OCR operate strictly on your device.',
        timestamp: now.subtract(const Duration(hours: 3)),
        isRead: true,
        type: NotificationType.ai,
        priority: NotificationPriority.normal,
        actionRoute: '/ai',
        actionLabel: 'Explore AI Search',
      ),
    ];
  }

  Future<void> _persist() async {
    if (_cachedItems == null) return;
    try {
      final file = await _getStorageFile();
      final jsonString = jsonEncode(_cachedItems!.map((i) => i.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (e) {
      AppLogger.error('Failed to persist notifications: $e', 'Notifications');
    }
  }

  void _emitUpdate() {
    if (_cachedItems == null) return;

    // Sort newest first
    _cachedItems!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final unread = _cachedItems!.where((i) => !i.isRead).length;

    _notificationsController.add(List.unmodifiable(_cachedItems!));
    _unreadCountController.add(unread);
  }

  @override
  Future<List<AppNotification>> getNotifications() async {
    await _ensureInitialized();
    return List.unmodifiable(_cachedItems!);
  }

  @override
  Stream<List<AppNotification>> watchNotifications() async* {
    await _ensureInitialized();
    yield List.unmodifiable(_cachedItems!);
    yield* _notificationsController.stream;
  }

  @override
  Future<int> getUnreadCount() async {
    await _ensureInitialized();
    return _cachedItems!.where((i) => !i.isRead).length;
  }

  @override
  Stream<int> watchUnreadCount() async* {
    await _ensureInitialized();
    yield _cachedItems!.where((i) => !i.isRead).length;
    yield* _unreadCountController.stream;
  }

  @override
  Future<void> addNotification(AppNotification notification) async {
    await _ensureInitialized();
    _cachedItems!.removeWhere((i) => i.id == notification.id);
    _cachedItems!.insert(0, notification);
    await _persist();
    _emitUpdate();
    AppLogger.info('Notification added: ${notification.title}', 'Notifications');
  }

  @override
  Future<void> markAsRead(String id) async {
    await _ensureInitialized();
    final index = _cachedItems!.indexWhere((i) => i.id == id);
    if (index != -1 && !_cachedItems![index].isRead) {
      _cachedItems![index] = _cachedItems![index].copyWith(isRead: true);
      await _persist();
      _emitUpdate();
    }
  }

  @override
  Future<void> markAllAsRead() async {
    await _ensureInitialized();
    bool changed = false;
    for (int i = 0; i < _cachedItems!.length; i++) {
      if (!_cachedItems![i].isRead) {
        _cachedItems![i] = _cachedItems![i].copyWith(isRead: true);
        changed = true;
      }
    }
    if (changed) {
      await _persist();
      _emitUpdate();
    }
  }

  @override
  Future<void> deleteNotification(String id) async {
    await _ensureInitialized();
    final countBefore = _cachedItems!.length;
    _cachedItems!.removeWhere((i) => i.id == id);
    if (_cachedItems!.length != countBefore) {
      await _persist();
      _emitUpdate();
    }
  }

  @override
  Future<void> clearAll() async {
    await _ensureInitialized();
    _cachedItems!.clear();
    await _persist();
    _emitUpdate();
    AppLogger.info('Cleared all notifications', 'Notifications');
  }

  @override
  Future<void> syncRemoteNotifications({bool isOnline = true}) async {
    await _ensureInitialized();

    if (!isOnline) {
      AppLogger.info('Offline mode: skipped remote notification synchronization safely.', 'Notifications');
      return;
    }

    // In online mode, verify whether administrative or system announcements should be appended
    const remoteNoticeId = 'remote_v1_announcement';
    final alreadyReceived = _cachedItems!.any((n) => n.id == remoteNoticeId);

    if (!alreadyReceived) {
      final remoteNotice = AppNotification(
        id: remoteNoticeId,
        title: 'FileZen Cloud Sync Preview',
        body: 'New end-to-end encrypted cloud backup protocol and transfer options are ready to explore.',
        timestamp: DateTime.now(),
        isRead: false,
        type: NotificationType.system,
        priority: NotificationPriority.normal,
        actionRoute: '/settings',
        actionLabel: 'View Sync Options',
      );
      await addNotification(remoteNotice);
      AppLogger.info('Synchronized remote announcement', 'Notifications');
    }
  }

  /// Event factory: Generates a high-priority Storage Warning notification.
  static AppNotification createStorageWarning({
    required double usedRatio,
    required int freeBytes,
  }) {
    final percent = (usedRatio * 100).toStringAsFixed(1);
    final freeFormatted = Formatters.formatFileSize(freeBytes);
    return AppNotification(
      id: 'storage_alert_${DateTime.now().millisecondsSinceEpoch}',
      title: 'High Storage Alert ($percent% Used)',
      body: 'Your device only has $freeFormatted remaining. Review cleanup opportunities safely.',
      timestamp: DateTime.now(),
      isRead: false,
      type: NotificationType.storage,
      priority: NotificationPriority.high,
      actionRoute: '/clean',
      actionLabel: 'Open Clean Hub',
    );
  }

  /// Event factory: Generates a Duplicate Files Detected notification.
  static AppNotification createDuplicateDetectedAlert({
    required int duplicateCount,
    required int recoverableBytes,
  }) {
    final sizeStr = Formatters.formatFileSize(recoverableBytes);
    return AppNotification(
      id: 'dupe_alert_${DateTime.now().millisecondsSinceEpoch}',
      title: '$duplicateCount Duplicate Files Found',
      body: 'Free up to $sizeStr safely without touching original files.',
      timestamp: DateTime.now(),
      isRead: false,
      type: NotificationType.storage,
      priority: NotificationPriority.normal,
      actionRoute: '/clean/duplicates',
      actionLabel: 'Review Duplicates',
    );
  }

  /// Event factory: Generates a Vault Security Event notification.
  static AppNotification createVaultEventAlert({
    required String eventDescription,
  }) {
    return AppNotification(
      id: 'vault_event_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Vault Security Notice',
      body: eventDescription,
      timestamp: DateTime.now(),
      isRead: false,
      type: NotificationType.security,
      priority: NotificationPriority.high,
      actionRoute: '/vault',
      actionLabel: 'Open Vault',
    );
  }
}
