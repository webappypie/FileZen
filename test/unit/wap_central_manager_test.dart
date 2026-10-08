import 'dart:io';
import 'package:filezen/app/config/app_config.dart';
import 'package:filezen/data/notifications/notification_repository.dart';
import 'package:filezen/data/wapcentral/wap_central_manager.dart';
import 'package:filezen/data/wapcentral/wap_client_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late String monetizationPath;
  late String notifPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_wap_test_');
    monetizationPath = '${tempDir.path}/.filezen_monetization.json';
    notifPath = '${tempDir.path}/.filezen_notifications.json';
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('WapCentralManager Unit Tests', () {
    test('initializes gracefully in test mode without crashing', () async {
      const config = AppConfig(
        environment: 'testing',
        wapAppId: 'app_1791324566055',
        wapAppKey: 'wap_key_test',
        wapBaseUrl: 'http://127.0.0.1:58888',
      );

      final manager = WapCentralManager(
        config: config,
        customStoragePath: monetizationPath,
      );

      expect(manager.isInitialized, isFalse);

      await manager.initialize(testMode: true);

      expect(manager.isInitialized, isTrue);
      expect(manager.monetizationState.isAdFreePurchased, isFalse);
      expect(manager.monetizationState.shouldDisplayAds, isTrue);

      manager.dispose();
    });

    test('toggles and persists Ad-Free status across restarts', () async {
      const config = AppConfig(
        environment: 'testing',
        wapAppId: 'app_1791324566055',
        wapAppKey: 'wap_key_test',
        wapBaseUrl: 'http://127.0.0.1:58888',
      );

      final manager1 = WapCentralManager(
        config: config,
        customStoragePath: monetizationPath,
      );
      await manager1.initialize(testMode: true);

      expect(manager1.monetizationState.isAdFreePurchased, isFalse);
      expect(manager1.monetizationState.shouldDisplayAds, isTrue);

      // User purchases Ad-Free
      await manager1.setAdFreePurchased(true);

      expect(manager1.monetizationState.isAdFreePurchased, isTrue);
      expect(manager1.monetizationState.shouldDisplayAds, isFalse);

      manager1.dispose();

      // Launch fresh manager instance sharing the same persistence file
      final manager2 = WapCentralManager(
        config: config,
        customStoragePath: monetizationPath,
      );
      await manager2.initialize(testMode: true);

      // Ad-Free state must be restored
      expect(manager2.monetizationState.isAdFreePurchased, isTrue);
      expect(manager2.monetizationState.shouldDisplayAds, isFalse);

      manager2.dispose();
    });

    test('syncs notifications safely in offline mode without throwing', () async {
      const config = AppConfig(
        environment: 'testing',
        wapAppId: 'app_1791324566055',
        wapAppKey: 'wap_key_test',
        wapBaseUrl: 'http://127.0.0.1:58888',
      );

      final notifRepo = NotificationRepository(customStoragePath: notifPath);
      final manager = WapCentralManager(
        config: config,
        notificationRepository: notifRepo,
        customStoragePath: monetizationPath,
      );

      await manager.initialize(testMode: true);

      final imported = await manager.syncWapNotifications();
      expect(imported, isA<int>());
      expect(imported, greaterThanOrEqualTo(0));

      manager.dispose();
    });

    test('checks platform health safely when offline', () async {
      const config = AppConfig(
        environment: 'testing',
        wapAppId: 'app_1791324566055',
        wapAppKey: 'wap_key_test',
        wapBaseUrl: 'http://127.0.0.1:59999', // dummy offline port
      );

      final coreService = WapClientService(config: config);
      final manager = WapCentralManager(
        config: config,
        coreService: coreService,
        customStoragePath: monetizationPath,
      );

      final isHealthy = await manager.checkPlatformHealth();
      expect(isHealthy, isFalse);

      manager.dispose();
    });
  });
}
