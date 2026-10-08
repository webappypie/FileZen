import 'dart:io';
import 'package:filezen/app/config/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Release Gate Checklist Verification Tests (Phase 13)', () {
    test('application identifiers and Android SDK targets adhere to release spec', () {
      expect(AppConstants.appName, equals('FileZen'));
      expect(AppConstants.androidPackageId, equals('com.webappypie.filezen'));
      expect(AppConstants.minAndroidSdk, equals(24)); // Android 7.0 (Nougat)
      expect(AppConstants.targetAndroidSdk, equals(35)); // Android 15
      expect(AppConstants.appVersion, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    });

    test('WAPCentral platform baseline constants match authoritative guide', () {
      expect(AppConstants.wapAppId, equals('app_1791324566055'));
      expect(AppConstants.wapBaseUrl, equals('https://wapcentral-prod.web.app/api/platform/v1'));
      expect(AppConstants.firebaseProjectId, equals('filezen-510822'));
      expect(AppConstants.firebaseProjectNumber, equals('424198485420'));
    });

    test('source code audit: zero hardcoded secrets or production private keys in lib/', () async {
      final libDir = Directory('lib');
      expect(await libDir.exists(), isTrue);

      final forbiddenPatterns = [
        RegExp(r'AIza[0-9A-Za-z-_]{35}'), // Google API key
        RegExp(r'sk-[a-zA-Z0-9]{20,}'), // OpenAI API key
        RegExp(r'ghp_[a-zA-Z0-9]{20,}'), // GitHub Personal Access Token
        RegExp(r'-----BEGIN PRIVATE KEY-----'), // Private PEM key
      ];

      final dartFiles = await libDir
          .list(recursive: true)
          .where((f) => f is File && f.path.endsWith('.dart'))
          .cast<File>()
          .toList();

      expect(dartFiles, isNotEmpty);

      for (final file in dartFiles) {
        final content = await file.readAsString();
        for (final pattern in forbiddenPatterns) {
          final match = pattern.hasMatch(content);
          expect(
            match,
            isFalse,
            reason: 'File ${file.path} contains potential forbidden secret matching $pattern',
          );
        }
      }
    });
  });
}
