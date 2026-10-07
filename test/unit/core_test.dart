import 'package:filezen/core/error/app_error.dart';
import 'package:filezen/core/logging/app_logger.dart';
import 'package:filezen/core/result/result.dart';
import 'package:filezen/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters', () {
    test('formatFileSize formats byte counts correctly', () {
      expect(Formatters.formatFileSize(0), '0 B');
      expect(Formatters.formatFileSize(512), '512 B');
      expect(Formatters.formatFileSize(1024), '1.0 KB');
      expect(Formatters.formatFileSize(10 * 1024 * 1024), '10 MB');
      expect(Formatters.formatFileSize((1.5 * 1024 * 1024 * 1024).toInt()), '1.5 GB');
    });

    test('formatDate handles relative and past dates', () {
      final now = DateTime.now();
      expect(Formatters.formatDate(now), 'Just now');
      expect(
        Formatters.formatDate(now.subtract(const Duration(minutes: 15))),
        '15 mins ago',
      );
      expect(
        Formatters.formatDate(now.subtract(const Duration(hours: 3))),
        '3 hours ago',
      );
      expect(
        Formatters.formatDate(now.subtract(const Duration(days: 1))),
        'Yesterday',
      );
    });

    test('truncate handles short and long strings', () {
      expect(Formatters.truncate('FileZen', 10), 'FileZen');
      expect(Formatters.truncate('A very long file name that needs truncation', 10), 'A very lon...');
    });
  });

  group('Result Type', () {
    test('Result.success holds data and isSuccess is true', () {
      final result = Result.success('payload');
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.dataOrNull, 'payload');
      expect(result.errorOrNull, isNull);

      final mapped = result.map((val) => val.length);
      expect(mapped.dataOrNull, 7);
    });

    test('Result.failure holds error and isFailure is true', () {
      final error = FileNotFoundError(path: '/storage/sample.txt');
      final result = Result<String>.failure(error);

      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.dataOrNull, isNull);
      expect(result.errorOrNull, equals(error));

      final handled = result.when(
        success: (val) => 'got $val',
        failure: (err) => 'handled ${err.message}',
      );
      expect(handled, contains('handled'));
    });
  });

  group('AppLogger Redaction', () {
    test('redact strips wap_key secrets and authorization tokens', () {
      const secret = 'Connecting with wap_key_b3314615802b82d33b53540deaf007681d118d27 to gateway';
      final redacted = AppLogger.redact(secret);
      expect(redacted.contains('b3314615802b82d33b53540deaf007681d118d27'), isFalse);
      expect(redacted, contains('[REDACTED_APP_KEY]'));
    });
  });
}
