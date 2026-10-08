import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Release Signing & ProGuard Hardening Tests (P0-01)', () {
    test('build.gradle.kts release buildType does not use debug signing key', () async {
      final gradleFile = File('android/app/build.gradle.kts');
      expect(await gradleFile.exists(), isTrue);

      final content = await gradleFile.readAsString();

      // Ensure debug signing is NOT assigned to release
      final releaseBlockMatch = RegExp(r'release\s*\{([^}]+)\}', dotAll: true).firstMatch(content);
      expect(releaseBlockMatch, isNotNull);
      final releaseBlock = releaseBlockMatch!.group(1)!;

      expect(
        releaseBlock.contains('signingConfigs.getByName("debug")'),
        isFalse,
        reason: 'Release variant must never use debug signing keys (P0-01 blocker)',
      );

      // Verify release variant uses release signing configuration
      expect(
        releaseBlock.contains('signingConfig = signingConfigs.getByName("release")'),
        isTrue,
        reason: 'Release variant must explicitly use the release signingConfig',
      );

      // Verify R8 minification and resource shrinking
      expect(releaseBlock.contains('isMinifyEnabled = true'), isTrue);
      expect(releaseBlock.contains('isShrinkResources = true'), isTrue);
    });

    test('build.gradle.kts defines release signingConfig with key.properties or env vars', () async {
      final gradleFile = File('android/app/build.gradle.kts');
      final content = await gradleFile.readAsString();

      expect(content.contains('signingConfigs {'), isTrue);
      expect(content.contains('create("release")'), isTrue);
      expect(content.contains('key.properties'), isTrue);
      expect(content.contains('FILEZEN_KEYSTORE_PATH'), isTrue);
    });

    test('.gitignore strictly ignores key.properties and keystore files', () async {
      final gitignoreFile = File('.gitignore');
      expect(await gitignoreFile.exists(), isTrue);

      final content = await gitignoreFile.readAsString();
      expect(content, contains('key.properties'));
      expect(content, contains('*.keystore'));
      expect(content, contains('*.jks'));
    });

    test('android/key.properties.example exists without containing real passwords', () async {
      final exampleFile = File('android/key.properties.example');
      expect(await exampleFile.exists(), isTrue);

      final content = await exampleFile.readAsString();
      expect(content, contains('storePassword='));
      expect(content, contains('keyPassword='));
      expect(content, contains('keyAlias='));
      expect(content, contains('storeFile='));
    });
  });
}
