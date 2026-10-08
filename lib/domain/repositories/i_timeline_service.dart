import '../models/file_category.dart';
import '../models/timeline_models.dart';

/// Contract for generating chronological timeline feeds of files.
abstract class ITimelineService {
  /// Aggregates and groups files chronologically into calendar timeline buckets
  /// (Today, Yesterday, This Week, This Month, Earlier This Year, Past Years).
  Future<List<TimelineGroup>> getTimelineGroups({
    FileCategory? categoryFilter,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? targetPaths,
  });
}
