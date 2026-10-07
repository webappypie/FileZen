/// Domain models representing extracted media metadata across images, videos, and audio.
class ImageMetadata {
  const ImageMetadata({
    required this.fileSize,
    required this.mimeType,
    this.width,
    this.height,
    this.dateTaken,
    this.cameraMake,
    this.cameraModel,
    this.lensModel,
    this.focalLength,
    this.fNumber,
    this.exposureTime,
    this.iso,
    this.latitude,
    this.longitude,
    this.orientation,
    this.rawExifTags = const {},
  });

  final int fileSize;
  final String mimeType;
  final int? width;
  final int? height;
  final DateTime? dateTaken;
  final String? cameraMake;
  final String? cameraModel;
  final String? lensModel;
  final String? focalLength;
  final String? fNumber;
  final String? exposureTime;
  final String? iso;
  final double? latitude;
  final double? longitude;
  final int? orientation;
  final Map<String, String> rawExifTags;

  String get resolutionString {
    if (width != null && height != null) {
      return '$width × $height';
    }
    return 'Unknown';
  }

  bool get hasGps => latitude != null && longitude != null;

  String get formattedGps {
    if (hasGps) {
      return '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
    }
    return 'None';
  }

  String get cameraString {
    final make = cameraMake ?? '';
    final model = cameraModel ?? '';
    if (make.isEmpty && model.isEmpty) return 'Unknown';
    if (model.toLowerCase().contains(make.toLowerCase())) return model;
    return '$make $model'.trim();
  }
}

class VideoMetadata {
  const VideoMetadata({
    required this.fileSize,
    required this.format,
    required this.duration,
    this.width,
    this.height,
    this.aspectRatio,
  });

  final int fileSize;
  final String format;
  final Duration duration;
  final int? width;
  final int? height;
  final double? aspectRatio;

  String get resolutionString {
    if (width != null && height != null) {
      return '$width × $height';
    }
    return 'Unknown';
  }
}

class AudioMetadata {
  const AudioMetadata({
    required this.title,
    required this.fileSize,
    required this.format,
    required this.duration,
    this.artist,
    this.album,
  });

  final String title;
  final int fileSize;
  final String format;
  final Duration duration;
  final String? artist;
  final String? album;

  String get artistOrUnknown => (artist != null && artist!.isNotEmpty) ? artist! : 'Unknown Artist';
  String get albumOrUnknown => (album != null && album!.isNotEmpty) ? album! : 'Unknown Album';
}
