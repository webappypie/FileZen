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

    test('schemaVersion matches current production baseline (v3)', () {
      expect(db.schemaVersion, equals(3));
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

  group('v2 -> v3 upgrade (lookup indexes, FTS rowid map, OCR state)', () {
    test('an existing v2 database is upgraded in place and its FTS rows stay deletable', () async {
      // Take the real v2 table definitions from the current schema.
      final reference = AppDatabase.forTesting(NativeDatabase.memory());
      final ddl = await reference.customSelect(
        "SELECT name, sql FROM sqlite_master WHERE name IN ('file_records', 'search_documents')",
      ).get();
      final sqlByName = {for (final r in ddl) r.read<String>('name'): r.read<String>('sql')};
      await reference.close();

      final upgraded = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
        raw.execute(sqlByName['file_records']!);
        raw.execute(sqlByName['search_documents']!);
        for (final id in ['a', 'b']) {
          raw.execute(
            'INSERT INTO file_records (id, path, name, extension, size, modified_at, created_at) '
            "VALUES ('$id', '/s/$id.txt', '$id.txt', '.txt', 1, 0, 0)",
          );
          raw.execute(
            'INSERT INTO search_documents (file_id, name, path, content, tags, category) '
            "VALUES ('$id', '$id.txt', '/s/$id.txt', 'legacy text $id', '', 'Documents')",
          );
        }
        raw.execute('PRAGMA user_version = 2');
      }));
      addTearDown(upgraded.close);

      final objects = await upgraded.customSelect(
        "SELECT name FROM sqlite_master WHERE type IN ('index', 'table')",
      ).get();
      final names = objects.map((r) => r.read<String>('name')).toSet();
      expect(names, containsAll(<String>[
        'idx_file_records_path',
        'idx_file_records_category_modified',
        'idx_file_records_modified',
        'idx_file_records_size',
        'search_doc_rowids',
        'ocr_state',
      ]));

      final mapped = await upgraded.customSelect('SELECT file_id FROM search_doc_rowids').get();
      expect(mapped.map((r) => r.read<String>('file_id')).toSet(), {'a', 'b'});

      expect(await upgraded.deleteSearchDocumentByFileId('a'), 1);
      expect(await upgraded.searchFts('legacy*').get(), hasLength(1));
      expect((await upgraded.searchFts('legacy*').get()).single.fileId, 'b');

      // Path lookups use the new index.
      final plan = await upgraded.customSelect(
        "EXPLAIN QUERY PLAN SELECT * FROM file_records WHERE path = '/s/b.txt'",
      ).get();
      expect(plan.map((r) => r.read<String>('detail')).join(' '), contains('idx_file_records_path'));
    });
  });
}
