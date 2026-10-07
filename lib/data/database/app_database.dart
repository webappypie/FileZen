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
}
