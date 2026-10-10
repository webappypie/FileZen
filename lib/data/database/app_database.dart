import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Database table for local file records and metadata.
class FileRecords extends Table {
  TextColumn get id => text()();
  TextColumn get path => text()();
  TextColumn get name => text()();
  TextColumn get extension => text()();
  Int64Column get size => int64()();
  DateTimeColumn get modifiedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get mimeType => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get category => text().nullable()();
  DateTimeColumn get indexedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [FileRecords],
  include: {'search_documents.drift'},
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createPerformanceSchema();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(fileRecords, fileRecords.indexedAt);
            await customStatement('''
              CREATE VIRTUAL TABLE IF NOT EXISTS search_documents USING fts5(
                file_id UNINDEXED,
                name,
                path,
                content,
                tags,
                category,
                tokenize = 'unicode61'
              );
            ''');
          }
          if (from < 3) {
            await _createPerformanceSchema();
            // Map every existing FTS row once so later deletes never scan.
            await customStatement(
              'INSERT OR REPLACE INTO search_doc_rowids (file_id, doc_rowid) '
              'SELECT file_id, rowid FROM search_documents',
            );
          }
        },
      );

  /// Schema v3: lookup indexes (every incremental-index check filters by path,
  /// category lists filter by category and sort by date, Storage Intelligence
  /// sorts by size) and a file_id -> FTS rowid map. `file_id` is an UNINDEXED
  /// FTS5 column, so `DELETE ... WHERE file_id = ?` scanned the whole FTS table
  /// on every re-index; deleting by rowid is a direct lookup.
  Future<void> _createPerformanceSchema() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_file_records_path ON file_records (path)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_file_records_category_modified ON file_records (category, modified_at)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_file_records_modified ON file_records (modified_at)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_file_records_size ON file_records (size)');
    await customStatement(
      'CREATE TABLE IF NOT EXISTS search_doc_rowids ('
      'file_id TEXT NOT NULL PRIMARY KEY, doc_rowid INTEGER NOT NULL)',
    );
    // Which image versions already went through OCR, so unchanged photos are
    // never recognised twice.
    await customStatement(
      'CREATE TABLE IF NOT EXISTS ocr_state ('
      'path TEXT NOT NULL PRIMARY KEY, size INTEGER NOT NULL, modified_ms INTEGER NOT NULL)',
    );
  }

  @override
  Future<int> insertSearchDocument(
    String fileId,
    String name,
    String path,
    String content,
    String tags,
    String category,
  ) async {
    final rowId = await super.insertSearchDocument(fileId, name, path, content, tags, category);
    await customStatement(
      'INSERT OR REPLACE INTO search_doc_rowids (file_id, doc_rowid) VALUES (?, ?)',
      [fileId, rowId],
    );
    return rowId;
  }

  @override
  Future<int> deleteSearchDocumentByFileId(String fileId) async {
    final mapped = await customSelect(
      'SELECT doc_rowid FROM search_doc_rowids WHERE file_id = ?',
      variables: [Variable<String>(fileId)],
    ).get();
    var deleted = 0;
    for (final row in mapped) {
      deleted += await customUpdate(
        'DELETE FROM search_documents WHERE rowid = ?',
        variables: [Variable<int>(row.read<int>('doc_rowid'))],
        updates: {searchDocuments},
        updateKind: UpdateKind.delete,
      );
    }
    if (mapped.isNotEmpty) {
      await customStatement('DELETE FROM search_doc_rowids WHERE file_id = ?', [fileId]);
    }
    return deleted;
  }

  @override
  Future<int> clearSearchDocuments() async {
    final cleared = await super.clearSearchDocuments();
    await customStatement('DELETE FROM search_doc_rowids');
    return cleared;
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'filezen_db',
      native: const DriftNativeOptions(
        shareAcrossIsolates: true,
      ),
    );
  }

  /// Returns a map of category names to their file counts.
  Future<Map<String, int>> getCategoryCounts() async {
    final countCol = fileRecords.id.count();
    final query = selectOnly(fileRecords)
      ..addColumns([fileRecords.category, countCol])
      ..groupBy([fileRecords.category]);
    final rows = await query.get();
    final result = <String, int>{};
    for (final row in rows) {
      final cat = row.read(fileRecords.category);
      if (cat != null) {
        result[cat] = row.read(countCol) ?? 0;
      }
    }
    return result;
  }

  /// Returns total file count for a specific category.
  Future<int> getFileCountForCategory(String category) async {
    final countCol = fileRecords.id.count();
    final query = selectOnly(fileRecords)
      ..addColumns([countCol])
      ..where(fileRecords.category.equals(category));
    final row = await query.getSingleOrNull();
    return row?.read(countCol) ?? 0;
  }

  /// Returns total count of files in the download folder.
  Future<int> getDownloadFilesCount() async {
    final countCol = fileRecords.id.count();
    final query = selectOnly(fileRecords)
      ..addColumns([countCol])
      ..where(fileRecords.path.like('%/Download/%') |
          fileRecords.path.like('%/Downloads/%') |
          fileRecords.path.like('%\\Download\\%') |
          fileRecords.path.like('%\\Downloads\\%'));
    final row = await query.getSingleOrNull();
    return row?.read(countCol) ?? 0;
  }

  /// Returns all file records for a specific category, sorted by modified date descending.
  Future<List<FileRecord>> getFilesForCategory(String category) {
    return (select(fileRecords)
          ..where((t) => t.category.equals(category))
          ..orderBy([(t) => OrderingTerm.desc(t.modifiedAt)]))
        .get();
  }

  /// Returns all file records located in Download directory.
  Future<List<FileRecord>> getDownloadFiles() {
    return (select(fileRecords)
          ..where((t) =>
              t.path.like('%/Download/%') |
              t.path.like('%/Downloads/%') |
              t.path.like('%\\Download\\%') |
              t.path.like('%\\Downloads\\%'))
          ..orderBy([(t) => OrderingTerm.desc(t.modifiedAt)]))
        .get();
  }
}
