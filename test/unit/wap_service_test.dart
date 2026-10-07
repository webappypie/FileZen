import 'package:filezen/app/config/app_config.dart';
import 'package:filezen/data/wapcentral/wap_client_service.dart';
import 'package:filezen/domain/repositories/i_wap_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WapClientService', () {
    test('reports unconfigured when key is empty and returns false without throwing', () async {
      const config = AppConfig(
        environment: 'testing',
        wapAppId: 'app_1791324566055',
        wapAppKey: '', // No key supplied
        wapBaseUrl: 'https://wapcentral-prod.web.app/api/platform/v1',
      );

      final service = WapClientService(config: config);

      expect(service.isConfigured, isFalse);
      expect(service.isOnline, isFalse);
      expect(service.status, equals(WapServiceStatus.unconfigured));

      final health = await service.checkHealth();
      expect(health, isFalse);
      expect(service.status, equals(WapServiceStatus.unconfigured));

      service.dispose();
    });

    test('operates in offline mode without crashing if gateway is unreachable', () async {
      const config = AppConfig(
        environment: 'testing',
        wapAppId: 'app_1791324566055',
        wapAppKey: 'wap_key_test_unreachable',
        wapBaseUrl: 'http://127.0.0.1:59999/api/platform/v1', // Unreachable dummy port
      );

      final service = WapClientService(config: config);

      expect(service.isConfigured, isTrue);
      expect(service.status, equals(WapServiceStatus.offline));

      // checkHealth should safely handle connection failure and maintain local-first mode
      final health = await service.checkHealth();
      expect(health, isFalse);
      expect(service.isOnline, isFalse);
      expect(service.status, equals(WapServiceStatus.offline));

      service.dispose();
    });
  });
}
