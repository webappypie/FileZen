import 'package:filezen/data/monitoring/analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnalyticsService Unit Tests', () {
    late AnalyticsService service;

    setUp(() {
      service = AnalyticsService();
    });

    test('logs non-identifying telemetry events', () async {
      await service.logEvent('button_clicked', parameters: {
        'button_id': 'clean_duplicates',
        'item_count': 15,
      });

      final events = service.getRecentEvents();
      expect(events.length, equals(1));
      expect(events.first.name, equals('button_clicked'));
      expect(events.first.parameters['button_id'], equals('clean_duplicates'));
      expect(events.first.parameters['item_count'], equals(15));
    });

    test('strictly redacts sensitive PII parameter keys and values', () async {
      await service.logEvent('file_action', parameters: {
        'file_path': '/storage/emulated/0/DCIM/passport.jpg',
        'file_name': 'tax_return_2025.pdf',
        'user_token': 'Bearer wap_key_secret1234567890',
        'category': 'documents',
      });

      final events = service.getRecentEvents();
      expect(events.length, equals(1));
      final params = events.first.parameters;

      // Sensitive keys must be redacted
      expect(params['file_path'], equals('[REDACTED]'));
      expect(params['file_name'], equals('[REDACTED]'));
      expect(params['user_token'], equals('[REDACTED]'));

      // Safe parameter preserved
      expect(params['category'], equals('documents'));
    });

    test('logs screen views with standardized screen_name parameter', () async {
      await service.logScreenView('VaultScreen');

      final events = service.getRecentEvents();
      expect(events.length, equals(1));
      expect(events.first.name, equals('screen_view'));
      expect(events.first.parameters['screen_name'], equals('VaultScreen'));
    });

    test('drops all events when user opts out', () async {
      await service.setEnabled(false);
      expect(service.isEnabled, isFalse);

      await service.logEvent('search_performed', parameters: {'query_len': 4});
      expect(service.getRecentEvents(), isEmpty);
    });

    test('clears recorded events', () async {
      await service.logEvent('event_1');
      await service.logEvent('event_2');

      expect(service.getRecentEvents().length, equals(2));

      service.clearEvents();
      expect(service.getRecentEvents(), isEmpty);
    });
  });
}
