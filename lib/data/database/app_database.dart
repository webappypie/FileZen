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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
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
        },
      );

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
