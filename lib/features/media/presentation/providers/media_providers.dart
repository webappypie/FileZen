import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/services/audio_player_service.dart';
import '../../../../data/services/media_metadata_service.dart';
import '../../../../domain/models/audio_playback_models.dart';
import '../../../../domain/models/media_metadata.dart';
import '../../../../domain/repositories/i_audio_player_service.dart';
import '../../../../domain/repositories/i_media_metadata_service.dart';

/// Provider for media metadata extraction service.
final mediaMetadataServiceProvider = Provider<IMediaMetadataService>((ref) {
  return const MediaMetadataService();
});

/// Global audio player service provider.
final audioPlayerServiceProvider = Provider<IAudioPlayerService>((ref) {
  final service = AudioPlayerService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// Stream of audio playback status.
final audioPlaybackStatusProvider = StreamProvider<AudioPlaybackStatus>((ref) {
  final player = ref.watch(audioPlayerServiceProvider);
  return player.statusStream;
});

/// Stream of audio position.
final audioPositionProvider = StreamProvider<Duration>((ref) {
  final player = ref.watch(audioPlayerServiceProvider);
  return player.positionStream;
});

/// Stream of audio total duration.
final audioDurationProvider = StreamProvider<Duration>((ref) {
  final player = ref.watch(audioPlayerServiceProvider);
  return player.durationStream;
});

/// Stream of audio queue state.
final audioQueueProvider = StreamProvider<AudioQueueState>((ref) {
  final player = ref.watch(audioPlayerServiceProvider);
  return player.queueStream;
});

/// Stream of active sleep timer countdown.
final audioSleepTimerProvider = StreamProvider<Duration?>((ref) {
  final player = ref.watch(audioPlayerServiceProvider);
  return player.sleepTimerStream;
});

/// Family provider extracting and caching image EXIF & dimension metadata.
final imageMetadataProvider = FutureProvider.family<ImageMetadata, String>((ref, filePath) async {
  final service = ref.watch(mediaMetadataServiceProvider);
  return service.extractImageMetadata(filePath);
});

/// Family provider extracting video container metadata.
final videoMetadataProvider = FutureProvider.family<VideoMetadata, String>((ref, filePath) async {
  final service = ref.watch(mediaMetadataServiceProvider);
  return service.extractVideoMetadata(filePath);
});

/// Family provider extracting audio ID3/container metadata.
final audioMetadataProvider = FutureProvider.family<AudioMetadata, String>((ref, filePath) async {
  final service = ref.watch(mediaMetadataServiceProvider);
  return service.extractAudioMetadata(filePath);
});
