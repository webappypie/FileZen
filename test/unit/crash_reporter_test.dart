import 'dart:io';
import 'package:filezen/data/monitoring/crash_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late String storagePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_crash_test_');
    storagePath = '${tempDir.path}/.filezen_crash_reports.json';
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CrashReporter Unit Tests', () {
    test('records and persists scrubbed crash report', () async {
      final reporter = CrashReporter(customStoragePath: storagePath);

      final fakeError = FormatException('Invalid JSON payload at /storage/emulated/0/Download/secret.txt');
      final fakeStack = StackTrace.fromString(
        '#0 Object.check (C:\\Users\\azadt\\develop\\test.dart:12:4)\n'
        '#1 Bearer wap_key_999888777authSecret\n'
        '#2 user email test@example.com logged in',
      );

      await reporter.recordError(fakeError, fakeStack, isFatal: true);

      final reports = await reporter.getCrashReports();
      expect(reports.length, equals(1));
      final report = reports.first;

      expect(report.isFatal, isTrue);
      // Verify path scrubbing
      expect(report.message.contains('/storage/emulated/0/Download/secret.txt'), isFalse);
      expect(report.message.contains('[EXTERNAL_STORAGE_PATH]'), isTrue);

      // Verify secret redaction
      expect(report.stackTrace!.contains('wap_key_999888777authSecret'), isFalse);
      expect(report.stackTrace!.contains('[REDACTED_APP_KEY]'), isTrue);
      expect(report.stackTrace!.contains('test@example.com'), isFalse);
      expect(report.stackTrace!.contains('[REDACTED_EMAIL]'), isTrue);
    });

    test('reloads persisted crash reports on new instance', () async {
      final reporter1 = CrashReporter(customStoragePath: storagePath);
      await reporter1.recordError(Exception('Failure 1'), StackTrace.empty);
      await reporter1.recordError(Exception('Failure 2'), StackTrace.empty);

      final reporter2 = CrashReporter(customStoragePath: storagePath);
      final reports = await reporter2.getCrashReports();
      expect(reports.length, equals(2));
      expect(reports[0].message, contains('Failure 2'));
      expect(reports[1].message, contains('Failure 1'));
    });

    test('drops incoming reports when disabled', () async {
      final reporter = CrashReporter(customStoragePath: storagePath, initialEnabled: false);
      expect(reporter.isEnabled, isFalse);

      await reporter.recordError(Exception('Should be dropped'), StackTrace.empty);

      final reports = await reporter.getCrashReports();
      expect(reports, isEmpty);
    });

    test('clears stored crash reports', () async {
      final reporter = CrashReporter(customStoragePath: storagePath);
      await reporter.recordError(Exception('Will be deleted'), StackTrace.empty);

      expect((await reporter.getCrashReports()).length, equals(1));

      await reporter.clearCrashReports();
      expect((await reporter.getCrashReports()), isEmpty);

      // Verify cleared state persists
      final reporterReloaded = CrashReporter(customStoragePath: storagePath);
      expect((await reporterReloaded.getCrashReports()), isEmpty);
    });
  });
}
