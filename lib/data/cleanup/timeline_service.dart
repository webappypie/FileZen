
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/timeline_models.dart';
import '../../domain/repositories/i_storage_repository.dart';
import '../../domain/repositories/i_timeline_service.dart';
import '../database/app_database.dart';
import '../storage/file_walker.dart';

/// Implementation of ITimelineService aggregating local files into temporal buckets.
class TimelineService implements ITimelineService {
  final AppDatabase db;
  final IStorageRepository storageRepo;

  TimelineService({
    required this.db,
    required this.storageRepo,
  });

  @override
  Future<List<TimelineGroup>> getTimelineGroups({
    FileCategory? categoryFilter,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? targetPaths,
  }) async {
    final allFiles = await _collectFiles(targetPaths: targetPaths);

    // Apply filters
    var filtered = allFiles.where((f) {
      if (categoryFilter != null && f.category != categoryFilter) return false;
      if (startDate != null && f.modifiedAt.isBefore(startDate)) return false;
      if (endDate != null && f.modifiedAt.isAfter(endDate)) return false;
      return true;
    }).toList();

    // Sort newest modified first
    filtered.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(const Duration(days: 7));
    final monthStart = DateTime(now.year, now.month, 1);
    final yearStart = DateTime(now.year, 1, 1);

    final todayFiles = <FileEntity>[];
    final yesterdayFiles = <FileEntity>[];
    final thisWeekFiles = <FileEntity>[];
    final thisMonthFiles = <FileEntity>[];
    final earlierThisYearFiles = <FileEntity>[];
    final pastYearsFiles = <FileEntity>[];

    for (final file in filtered) {
      final date = file.modifiedAt;
      if (date.isAfter(todayStart) || date.isAtSameMomentAs(todayStart)) {
        todayFiles.add(file);
      } else if (date.isAfter(yesterdayStart) || date.isAtSameMomentAs(yesterdayStart)) {
        yesterdayFiles.add(file);
      } else if (date.isAfter(weekStart)) {
        thisWeekFiles.add(file);
      } else if (date.isAfter(monthStart)) {
        thisMonthFiles.add(file);
      } else if (date.isAfter(yearStart)) {
        earlierThisYearFiles.add(file);
      } else {
        pastYearsFiles.add(file);
      }
    }

    final groups = <TimelineGroup>[];

    if (todayFiles.isNotEmpty) {
      groups.add(TimelineGroup(
        bucket: TimelineBucket.today,
        label: 'Today',
        date: todayStart,
        files: todayFiles,
        totalBytes: todayFiles.fold(0, (sum, f) => sum + f.size),
      ));
    }

    if (yesterdayFiles.isNotEmpty) {
      groups.add(TimelineGroup(
        bucket: TimelineBucket.yesterday,
        label: 'Yesterday',
        date: yesterdayStart,
        files: yesterdayFiles,
        totalBytes: yesterdayFiles.fold(0, (sum, f) => sum + f.size),
      ));
    }

    if (thisWeekFiles.isNotEmpty) {
      groups.add(TimelineGroup(
        bucket: TimelineBucket.thisWeek,
        label: 'Earlier This Week',
        date: weekStart,
        files: thisWeekFiles,
        totalBytes: thisWeekFiles.fold(0, (sum, f) => sum + f.size),
      ));
    }

    if (thisMonthFiles.isNotEmpty) {
      groups.add(TimelineGroup(
        bucket: TimelineBucket.thisMonth,
        label: 'Earlier This Month',
        date: monthStart,
        files: thisMonthFiles,
        totalBytes: thisMonthFiles.fold(0, (sum, f) => sum + f.size),
      ));
    }

    if (earlierThisYearFiles.isNotEmpty) {
      // Subdivide earlier this year by month if there are files
      final monthMap = <int, List<FileEntity>>{};
      for (final f in earlierThisYearFiles) {
        monthMap.putIfAbsent(f.modifiedAt.month, () => []).add(f);
      }
      final sortedMonths = monthMap.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final m in sortedMonths) {
        final mFiles = monthMap[m]!;
        final mDate = DateTime(now.year, m, 1);
        final monthName = _monthName(m);
        groups.add(TimelineGroup(
          bucket: TimelineBucket.earlierThisYear,
          label: '$monthName ${now.year}',
          date: mDate,
          files: mFiles,
          totalBytes: mFiles.fold(0, (sum, f) => sum + f.size),
        ));
      }
    }

    if (pastYearsFiles.isNotEmpty) {
      final yearMap = <int, List<FileEntity>>{};
      for (final f in pastYearsFiles) {
        yearMap.putIfAbsent(f.modifiedAt.year, () => []).add(f);
      }
      final sortedYears = yearMap.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final y in sortedYears) {
        final yFiles = yearMap[y]!;
        final yDate = DateTime(y, 1, 1);
        groups.add(TimelineGroup(
          bucket: TimelineBucket.pastYears,
          label: '$y',
          date: yDate,
          files: yFiles,
          totalBytes: yFiles.fold(0, (sum, f) => sum + f.size),
        ));
      }
    }

    return groups;
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return 'Month $month';
  }

  Future<List<FileEntity>> _collectFiles({List<String>? targetPaths}) async {
    final records = await db.select(db.fileRecords).get();

    if (records.isNotEmpty) {
      return records
          .map((r) => FileEntity(
                id: r.id,
                path: r.path,
                name: r.name,
                extension: r.extension,
                size: r.size.toInt(),
                modifiedAt: r.modifiedAt,
                createdAt: r.createdAt,
                isDirectory: false,
                mimeType: r.mimeType,
                category: FileCategory.fromExtension(r.extension, r.mimeType),
              ))
          .toList();
    }

    // Index empty: walk explicitly requested roots only (see DeduplicationService).
    if (targetPaths == null) return const [];
    return FileWalker.files(targetPaths);
  }
}
