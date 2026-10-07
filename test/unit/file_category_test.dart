import 'package:filezen/domain/models/file_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileCategory Resolution', () {
    test('resolves category from common file extensions', () {
      expect(FileCategory.fromExtension('jpg'), FileCategory.image);
      expect(FileCategory.fromExtension('png'), FileCategory.image);
      expect(FileCategory.fromExtension('.webp'), FileCategory.image);
      expect(FileCategory.fromExtension('mp4'), FileCategory.video);
      expect(FileCategory.fromExtension('mkv'), FileCategory.video);
      expect(FileCategory.fromExtension('mp3'), FileCategory.audio);
      expect(FileCategory.fromExtension('flac'), FileCategory.audio);
      expect(FileCategory.fromExtension('pdf'), FileCategory.document);
      expect(FileCategory.fromExtension('docx'), FileCategory.document);
      expect(FileCategory.fromExtension('zip'), FileCategory.archive);
      expect(FileCategory.fromExtension('tar.gz'), FileCategory.archive);
      expect(FileCategory.fromExtension('apk'), FileCategory.apk);
      expect(FileCategory.fromExtension('unknown_ext'), FileCategory.other);
    });

    test('resolves category from MIME type when available', () {
      expect(FileCategory.fromExtension('bin', 'image/jpeg'), FileCategory.image);
      expect(FileCategory.fromExtension('bin', 'video/mp4'), FileCategory.video);
      expect(FileCategory.fromExtension('bin', 'audio/mpeg'), FileCategory.audio);
      expect(FileCategory.fromExtension('bin', 'application/pdf'), FileCategory.document);
    });
  });
}
