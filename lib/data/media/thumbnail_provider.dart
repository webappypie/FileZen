import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'thumbnail_service.dart';

/// App-wide video thumbnail cache (one instance so concurrency is bounded globally).
final thumbnailServiceProvider = Provider<ThumbnailService>((ref) => ThumbnailService());
