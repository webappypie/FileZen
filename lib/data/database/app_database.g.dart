// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $FileRecordsTable extends FileRecords
    with TableInfo<$FileRecordsTable, FileRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FileRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extensionMeta = const VerificationMeta(
    'extension',
  );
  @override
  late final GeneratedColumn<String> extension = GeneratedColumn<String>(
    'extension',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<BigInt> size = GeneratedColumn<BigInt>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    path,
    name,
    extension,
    size,
    modifiedAt,
    createdAt,
    mimeType,
    isFavorite,
    category,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<FileRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('extension')) {
      context.handle(
        _extensionMeta,
        extension.isAcceptableOrUnknown(data['extension']!, _extensionMeta),
      );
    } else if (isInserting) {
      context.missing(_extensionMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FileRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FileRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      extension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extension'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}size'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
    );
  }

  @override
  $FileRecordsTable createAlias(String alias) {
    return $FileRecordsTable(attachedDatabase, alias);
  }
}

class FileRecord extends DataClass implements Insertable<FileRecord> {
  final String id;
  final String path;
  final String name;
  final String extension;
  final BigInt size;
  final DateTime modifiedAt;
  final DateTime createdAt;
  final String? mimeType;
  final bool isFavorite;
  final String? category;
  const FileRecord({
    required this.id,
    required this.path,
    required this.name,
    required this.extension,
    required this.size,
    required this.modifiedAt,
    required this.createdAt,
    this.mimeType,
    required this.isFavorite,
    this.category,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['path'] = Variable<String>(path);
    map['name'] = Variable<String>(name);
    map['extension'] = Variable<String>(extension);
    map['size'] = Variable<BigInt>(size);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    map['is_favorite'] = Variable<bool>(isFavorite);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    return map;
  }

  FileRecordsCompanion toCompanion(bool nullToAbsent) {
    return FileRecordsCompanion(
      id: Value(id),
      path: Value(path),
      name: Value(name),
      extension: Value(extension),
      size: Value(size),
      modifiedAt: Value(modifiedAt),
      createdAt: Value(createdAt),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      isFavorite: Value(isFavorite),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
    );
  }

  factory FileRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FileRecord(
      id: serializer.fromJson<String>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      name: serializer.fromJson<String>(json['name']),
      extension: serializer.fromJson<String>(json['extension']),
      size: serializer.fromJson<BigInt>(json['size']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      category: serializer.fromJson<String?>(json['category']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'path': serializer.toJson<String>(path),
      'name': serializer.toJson<String>(name),
      'extension': serializer.toJson<String>(extension),
      'size': serializer.toJson<BigInt>(size),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'mimeType': serializer.toJson<String?>(mimeType),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'category': serializer.toJson<String?>(category),
    };
  }

  FileRecord copyWith({
    String? id,
    String? path,
    String? name,
    String? extension,
    BigInt? size,
    DateTime? modifiedAt,
    DateTime? createdAt,
    Value<String?> mimeType = const Value.absent(),
    bool? isFavorite,
    Value<String?> category = const Value.absent(),
  }) => FileRecord(
    id: id ?? this.id,
    path: path ?? this.path,
    name: name ?? this.name,
    extension: extension ?? this.extension,
    size: size ?? this.size,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    createdAt: createdAt ?? this.createdAt,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    isFavorite: isFavorite ?? this.isFavorite,
    category: category.present ? category.value : this.category,
  );
  FileRecord copyWithCompanion(FileRecordsCompanion data) {
    return FileRecord(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      name: data.name.present ? data.name.value : this.name,
      extension: data.extension.present ? data.extension.value : this.extension,
      size: data.size.present ? data.size.value : this.size,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      category: data.category.present ? data.category.value : this.category,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FileRecord(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('name: $name, ')
          ..write('extension: $extension, ')
          ..write('size: $size, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('mimeType: $mimeType, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('category: $category')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    path,
    name,
    extension,
    size,
    modifiedAt,
    createdAt,
    mimeType,
    isFavorite,
    category,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileRecord &&
          other.id == this.id &&
          other.path == this.path &&
          other.name == this.name &&
          other.extension == this.extension &&
          other.size == this.size &&
          other.modifiedAt == this.modifiedAt &&
          other.createdAt == this.createdAt &&
          other.mimeType == this.mimeType &&
          other.isFavorite == this.isFavorite &&
          other.category == this.category);
}

class FileRecordsCompanion extends UpdateCompanion<FileRecord> {
  final Value<String> id;
  final Value<String> path;
  final Value<String> name;
  final Value<String> extension;
  final Value<BigInt> size;
  final Value<DateTime> modifiedAt;
  final Value<DateTime> createdAt;
  final Value<String?> mimeType;
  final Value<bool> isFavorite;
  final Value<String?> category;
  final Value<int> rowid;
  const FileRecordsCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.name = const Value.absent(),
    this.extension = const Value.absent(),
    this.size = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.category = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FileRecordsCompanion.insert({
    required String id,
    required String path,
    required String name,
    required String extension,
    required BigInt size,
    required DateTime modifiedAt,
    required DateTime createdAt,
    this.mimeType = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.category = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       path = Value(path),
       name = Value(name),
       extension = Value(extension),
       size = Value(size),
       modifiedAt = Value(modifiedAt),
       createdAt = Value(createdAt);
  static Insertable<FileRecord> custom({
    Expression<String>? id,
    Expression<String>? path,
    Expression<String>? name,
    Expression<String>? extension,
    Expression<BigInt>? size,
    Expression<DateTime>? modifiedAt,
    Expression<DateTime>? createdAt,
    Expression<String>? mimeType,
    Expression<bool>? isFavorite,
    Expression<String>? category,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (name != null) 'name': name,
      if (extension != null) 'extension': extension,
      if (size != null) 'size': size,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (mimeType != null) 'mime_type': mimeType,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (category != null) 'category': category,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FileRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? path,
    Value<String>? name,
    Value<String>? extension,
    Value<BigInt>? size,
    Value<DateTime>? modifiedAt,
    Value<DateTime>? createdAt,
    Value<String?>? mimeType,
    Value<bool>? isFavorite,
    Value<String?>? category,
    Value<int>? rowid,
  }) {
    return FileRecordsCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      extension: extension ?? this.extension,
      size: size ?? this.size,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt ?? this.createdAt,
      mimeType: mimeType ?? this.mimeType,
      isFavorite: isFavorite ?? this.isFavorite,
      category: category ?? this.category,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (extension.present) {
      map['extension'] = Variable<String>(extension.value);
    }
    if (size.present) {
      map['size'] = Variable<BigInt>(size.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FileRecordsCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('name: $name, ')
          ..write('extension: $extension, ')
          ..write('size: $size, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('mimeType: $mimeType, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('category: $category, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FileRecordsTable fileRecords = $FileRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [fileRecords];
}

typedef $$FileRecordsTableCreateCompanionBuilder =
    FileRecordsCompanion Function({
      required String id,
      required String path,
      required String name,
      required String extension,
      required BigInt size,
      required DateTime modifiedAt,
      required DateTime createdAt,
      Value<String?> mimeType,
      Value<bool> isFavorite,
      Value<String?> category,
      Value<int> rowid,
    });
typedef $$FileRecordsTableUpdateCompanionBuilder =
    FileRecordsCompanion Function({
      Value<String> id,
      Value<String> path,
      Value<String> name,
      Value<String> extension,
      Value<BigInt> size,
      Value<DateTime> modifiedAt,
      Value<DateTime> createdAt,
      Value<String?> mimeType,
      Value<bool> isFavorite,
      Value<String?> category,
      Value<int> rowid,
    });

class $$FileRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $FileRecordsTable> {
  $$FileRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extension => $composableBuilder(
    column: $table.extension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FileRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $FileRecordsTable> {
  $$FileRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extension => $composableBuilder(
    column: $table.extension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FileRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FileRecordsTable> {
  $$FileRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get extension =>
      $composableBuilder(column: $table.extension, builder: (column) => column);

  GeneratedColumn<BigInt> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);
}

class $$FileRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FileRecordsTable,
          FileRecord,
          $$FileRecordsTableFilterComposer,
          $$FileRecordsTableOrderingComposer,
          $$FileRecordsTableAnnotationComposer,
          $$FileRecordsTableCreateCompanionBuilder,
          $$FileRecordsTableUpdateCompanionBuilder,
          (
            FileRecord,
            BaseReferences<_$AppDatabase, $FileRecordsTable, FileRecord>,
          ),
          FileRecord,
          PrefetchHooks Function()
        > {
  $$FileRecordsTableTableManager(_$AppDatabase db, $FileRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FileRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FileRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FileRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> extension = const Value.absent(),
                Value<BigInt> size = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileRecordsCompanion(
                id: id,
                path: path,
                name: name,
                extension: extension,
                size: size,
                modifiedAt: modifiedAt,
                createdAt: createdAt,
                mimeType: mimeType,
                isFavorite: isFavorite,
                category: category,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String path,
                required String name,
                required String extension,
                required BigInt size,
                required DateTime modifiedAt,
                required DateTime createdAt,
                Value<String?> mimeType = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileRecordsCompanion.insert(
                id: id,
                path: path,
                name: name,
                extension: extension,
                size: size,
                modifiedAt: modifiedAt,
                createdAt: createdAt,
                mimeType: mimeType,
                isFavorite: isFavorite,
                category: category,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FileRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FileRecordsTable,
      FileRecord,
      $$FileRecordsTableFilterComposer,
      $$FileRecordsTableOrderingComposer,
      $$FileRecordsTableAnnotationComposer,
      $$FileRecordsTableCreateCompanionBuilder,
      $$FileRecordsTableUpdateCompanionBuilder,
      (
        FileRecord,
        BaseReferences<_$AppDatabase, $FileRecordsTable, FileRecord>,
      ),
      FileRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FileRecordsTableTableManager get fileRecords =>
      $$FileRecordsTableTableManager(_db, _db.fileRecords);
}
