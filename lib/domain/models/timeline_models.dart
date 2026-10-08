import 'file_entity.dart';

/// Temporal buckets for chronological timeline view.
enum TimelineBucket {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This Week'),
  thisMonth('This Month'),
  earlierThisYear('Earlier This Year'),
  pastYears('Past Years');

  final String displayName;
  const TimelineBucket(this.displayName);
}

/// Chronological grouping of files by calendar timeline.
class TimelineGroup {
  final TimelineBucket bucket;
  final String label;
  final DateTime date;
  final List<FileEntity> files;
  final int totalBytes;

  const TimelineGroup({
    required this.bucket,
    required this.label,
    required this.date,
    required this.files,
    required this.totalBytes,
  });

  int get count => files.length;
}
