import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase Drift Foundation', () {
    test('inserts and queries a FileRecord successfully', () async {
      final now = DateTime.now();

      await db.into(db.fileRecords).insert(
            FileRecordsCompanion.insert(
              id: 'file_001',
              path: '/storage/emulated/0/Download/contract.pdf',
              name: 'contract.pdf',
              extension: 'pdf',
              size: BigInt.from(1024 * 500),
              modifiedAt: now,
              createdAt: now,
              mimeType: const Value('application/pdf'),
              isFavorite: const Value(true),
              category: const Value('Documents'),
            ),
          );

      final records = await db.select(db.fileRecords).get();

      expect(records.length, 1);
      final record = records.first;
      expect(record.id, 'file_001');
      expect(record.name, 'contract.pdf');
      expect(record.extension, 'pdf');
      expect(record.size, BigInt.from(1024 * 500));
      expect(record.isFavorite, isTrue);
      expect(record.category, 'Documents');
    });

    test('supports query filtering and updates', () async {
      final now = DateTime.now();

      await db.into(db.fileRecords).insert(
            FileRecordsCompanion.insert(
              id: 'file_002',
              path: '/storage/emulated/0/DCIM/photo.jpg',
              name: 'photo.jpg',
              extension: 'jpg',
              size: BigInt.from(1024 * 1024 * 2),
              modifiedAt: now,
              createdAt: now,
              category: const Value('Images'),
            ),
          );

      final images = await (db.select(db.fileRecords)..where((t) => t.category.equals('Images'))).get();
      expect(images.length, 1);
      expect(images.first.name, 'photo.jpg');

      // Update favorite status
      await (db.update(db.fileRecords)..where((t) => t.id.equals('file_002'))).write(
        const FileRecordsCompanion(isFavorite: Value(true)),
      );

      final updated = await (db.select(db.fileRecords)..where((t) => t.id.equals('file_002'))).getSingle();
      expect(updated.isFavorite, isTrue);
    });
  });
}
