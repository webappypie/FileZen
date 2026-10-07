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

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [FileRecords])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'filezen_db',
      native: const DriftNativeOptions(
        shareAcrossIsolates: true,
      ),
    );
  }
}
