import '../models/media_metadata.dart';

/// Clean Architecture interface for extracting metadata from image, video, and audio assets.
abstract class IMediaMetadataService {
  /// Extract EXIF and dimensions metadata from an image file.
  Future<ImageMetadata> extractImageMetadata(String filePath);

  /// Extract duration, resolution, and format details from a video file.
  Future<VideoMetadata> extractVideoMetadata(String filePath);

  /// Extract title, artist, album, duration, and format from an audio file.
  Future<AudioMetadata> extractAudioMetadata(String filePath);
}
