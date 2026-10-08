import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Backup Exclusion & Vault Isolation Tests (P0-06)', () {
    test('AndroidManifest.xml explicitly disables backup and links exclusion rules', () async {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(await manifestFile.exists(), isTrue);

      final content = await manifestFile.readAsString();
      expect(content, contains('android:allowBackup="false"'));
      expect(content, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(content, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    });

    test('data_extraction_rules.xml excludes Vault directories and credentials', () async {
      final rulesFile = File('android/app/src/main/res/xml/data_extraction_rules.xml');
      expect(await rulesFile.exists(), isTrue);

      final content = await rulesFile.readAsString();
      expect(content, contains('<data-extraction-rules>'));
      expect(content, contains('<cloud-backup>'));
      expect(content, contains('<device-transfer>'));

      // Check exclusion targets
      expect(content, contains('path=".filezen_vault"'));
      expect(content, contains('path="vault"'));
      expect(content, contains('path="app_database.sqlite"'));
      expect(content, contains('path="FlutterSecureStorage"'));
    });

    test('backup_rules.xml excludes legacy cloud backup targets', () async {
      final rulesFile = File('android/app/src/main/res/xml/backup_rules.xml');
      expect(await rulesFile.exists(), isTrue);

      final content = await rulesFile.readAsString();
      expect(content, contains('<full-backup-content>'));
      expect(content, contains('path=".filezen_vault"'));
      expect(content, contains('path="vault"'));
      expect(content, contains('path="app_database.sqlite"'));
      expect(content, contains('path="FlutterSecureStorage"'));
    });
  });
}
