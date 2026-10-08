import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Database Migration & Schema Evolution Tests (Phase 13 Hardening)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('schemaVersion matches current production baseline (v2)', () {
      expect(db.schemaVersion, equals(2));
    });

    test('fileRecords table supports indexedAt and FTS5 search documents table exists', () async {
      // Insert a mock record with indexedAt populated
      final now = DateTime.now();
      await db.into(db.fileRecords).insert(
            FileRecordsCompanion.insert(
              id: 'file_v2_migration_test',
              path: '/storage/emulated/0/Documents/test.txt',
              name: 'test.txt',
              extension: 'txt',
              size: BigInt.from(1024),
              modifiedAt: now,
              createdAt: now,
              indexedAt: Value(now),
              category: const Value('documents'),
            ),
          );

      final records = await db.select(db.fileRecords).get();
      expect(records.length, equals(1));
      expect(records.first.id, equals('file_v2_migration_test'));
      expect(records.first.indexedAt, isNotNull);
      expect(
        records.first.indexedAt!.millisecondsSinceEpoch ~/ 1000,
        equals(now.millisecondsSinceEpoch ~/ 1000),
      );

      // Test inserting and querying FTS5 search documents
      await db.customStatement('''
        INSERT INTO search_documents (file_id, name, path, content, tags, category)
        VALUES ('file_v2_migration_test', 'test.txt', '/storage/emulated/0/Documents/test.txt', 'flutter sqlite drift migration test', 'test,migration', 'documents');
      ''');

      final searchResults = await db.customSelect('''
        SELECT file_id, name FROM search_documents WHERE search_documents MATCH 'migration'
      ''').get();

      expect(searchResults.length, equals(1));
      expect(searchResults.first.read<String>('file_id'), equals('file_v2_migration_test'));
    });
  });
}
