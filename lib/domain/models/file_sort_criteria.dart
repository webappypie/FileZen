import 'file_entity.dart';

/// Field criteria for sorting files.
enum FileSortField {
  name,
  date,
  size,
  type,
}

/// Sort direction.
enum SortDirection {
  ascending,
  descending,
}

/// Specifications for sorting file lists.
class FileSortCriteria {
  final FileSortField field;
  final SortDirection direction;
  final bool foldersFirst;

  const FileSortCriteria({
    this.field = FileSortField.name,
    this.direction = SortDirection.ascending,
    this.foldersFirst = true,
  });

  FileSortCriteria copyWith({
    FileSortField? field,
    SortDirection? direction,
    bool? foldersFirst,
  }) {
    return FileSortCriteria(
      field: field ?? this.field,
      direction: direction ?? this.direction,
      foldersFirst: foldersFirst ?? this.foldersFirst,
    );
  }

  /// Sorts a list of FileEntity objects in-place or returns sorted list.
  List<FileEntity> apply(List<FileEntity> list) {
    final sorted = List<FileEntity>.from(list);

    sorted.sort((a, b) {
      // 1. Folders first rule
      if (foldersFirst && a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }

      // 2. Field comparison
      int cmp;
      switch (field) {
        case FileSortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case FileSortField.date:
          cmp = a.modifiedAt.compareTo(b.modifiedAt);
          break;
        case FileSortField.size:
          cmp = a.size.compareTo(b.size);
          break;
        case FileSortField.type:
          cmp = a.extension.toLowerCase().compareTo(b.extension.toLowerCase());
          if (cmp == 0) {
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          break;
      }

      // 3. Direction reversal
      return direction == SortDirection.ascending ? cmp : -cmp;
    });

    return sorted;
  }
}
