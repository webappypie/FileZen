import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filezen/domain/models/audio_playback_models.dart';
import 'package:filezen/domain/models/media_metadata.dart';
import 'package:filezen/domain/repositories/i_audio_player_service.dart';
import 'package:filezen/domain/repositories/i_media_metadata_service.dart';
import 'package:filezen/features/media/presentation/providers/media_providers.dart';
import 'package:filezen/features/media/presentation/screens/audio_player_screen.dart';
import 'package:filezen/features/media/presentation/screens/image_viewer_screen.dart';
import 'package:filezen/features/media/presentation/widgets/mini_audio_player_bar.dart';

class FakeAudioPlayerService implements IAudioPlayerService {
  AudioQueueState _queue = const AudioQueueState(
    tracks: [
      AudioTrack(id: '/music/track1.mp3', path: '/music/track1.mp3', title: 'Mountain Echoes', artist: 'Zen Composer'),
      AudioTrack(id: '/music/track2.mp3', path: '/music/track2.mp3', title: 'Ocean Waves', artist: 'Zen Composer'),
    ],
    currentIndex: 0,
  );

  AudioPlaybackStatus _status = AudioPlaybackStatus.playing;
  Duration _position = const Duration(minutes: 1, seconds: 15);
  final Duration _duration = const Duration(minutes: 3, seconds: 45);
  double _speed = 1.0;
  Duration? _sleepTimer;

  final _statusController = StreamController<AudioPlaybackStatus>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _queueController = StreamController<AudioQueueState>.broadcast();
  final _sleepTimerController = StreamController<Duration?>.broadcast();

  @override
  AudioQueueState get currentQueue => _queue;

  @override
  AudioPlaybackStatus get currentStatus => _status;

  @override
  Duration get currentPosition => _position;

  @override
  Duration get totalDuration => _duration;

  @override
  double get playbackSpeed => _speed;

  @override
  Duration? get currentSleepTimer => _sleepTimer;

  @override
  Stream<AudioPlaybackStatus> get statusStream => _statusController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<AudioQueueState> get queueStream => _queueController.stream;

  @override
  Stream<Duration?> get sleepTimerStream => _sleepTimerController.stream;

  @override
  Future<void> setQueue(List<AudioTrack> tracks, {int initialIndex = 0, bool autoPlay = true}) async {
    _queue = _queue.copyWith(tracks: tracks, currentIndex: initialIndex);
    _queueController.add(_queue);
  }

  @override
  Future<void> play() async {
    _status = AudioPlaybackStatus.playing;
    _statusController.add(_status);
  }

  @override
  Future<void> pause() async {
    _status = AudioPlaybackStatus.paused;
    _statusController.add(_status);
  }

  @override
  Future<void> stop() async {
    _status = AudioPlaybackStatus.stopped;
    _statusController.add(_status);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionController.add(position);
  }

  @override
  Future<void> seekBy(Duration offset) async {
    _position += offset;
    _positionController.add(_position);
  }

  @override
  Future<void> skipNext() async {
    if (_queue.currentIndex < _queue.tracks.length - 1) {
      _queue = _queue.copyWith(currentIndex: _queue.currentIndex + 1);
      _queueController.add(_queue);
    }
  }

  @override
  Future<void> skipPrevious() async {
    if (_queue.currentIndex > 0) {
      _queue = _queue.copyWith(currentIndex: _queue.currentIndex - 1);
      _queueController.add(_queue);
    }
  }

  @override
  Future<void> skipToIndex(int index) async {
    _queue = _queue.copyWith(currentIndex: index);
    _queueController.add(_queue);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
  }

  @override
  Future<void> toggleRepeat() async {
    _queue = _queue.copyWith(
      repeatMode: _queue.repeatMode == AudioRepeatMode.off ? AudioRepeatMode.all : AudioRepeatMode.off,
    );
    _queueController.add(_queue);
  }

  @override
  Future<void> toggleShuffle() async {
    _queue = _queue.copyWith(isShuffle: !_queue.isShuffle);
    _queueController.add(_queue);
  }

  @override
  void setSleepTimer(Duration? duration) {
    _sleepTimer = duration;
    _sleepTimerController.add(duration);
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _positionController.close();
    await _durationController.close();
    await _queueController.close();
    await _sleepTimerController.close();
  }
}

class FakeMediaMetadataService implements IMediaMetadataService {
  @override
  Future<ImageMetadata> extractImageMetadata(String filePath) async {
    return const ImageMetadata(
      fileSize: 2048500,
      mimeType: 'image/jpeg',
      width: 4032,
      height: 3024,
      cameraMake: 'Google',
      cameraModel: 'Pixel 9 Pro',
      fNumber: '1.68',
      iso: '50',
    );
  }

  @override
  Future<VideoMetadata> extractVideoMetadata(String filePath) async {
    return const VideoMetadata(
      fileSize: 15400000,
      format: 'MP4',
      duration: Duration(minutes: 2, seconds: 30),
      width: 1920,
      height: 1080,
    );
  }

  @override
  Future<AudioMetadata> extractAudioMetadata(String filePath) async {
    return const AudioMetadata(
      title: 'Mountain Echoes',
      fileSize: 5200000,
      format: 'MP3',
      duration: Duration(minutes: 3, seconds: 45),
      artist: 'Zen Composer',
      album: 'Nature Sessions',
    );
  }
}

void main() {
  testWidgets('ImageViewerScreen renders app bar, counter, and handles controls', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaMetadataServiceProvider.overrideWithValue(FakeMediaMetadataService()),
        ],
        child: const MaterialApp(
          home: ImageViewerScreen(
            imagePaths: ['/tmp/sample1.jpg', '/tmp/sample2.jpg'],
            initialIndex: 0,
          ),
        ),
      ),
    );

    expect(find.text('sample1.jpg'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // Verify tool buttons
    expect(find.byIcon(Icons.rotate_right), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    // Open EXIF info sheet
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('4032 × 3024'), findsOneWidget);
    expect(find.text('Google Pixel 9 Pro'), findsOneWidget);
  });

  testWidgets('AudioPlayerScreen renders now playing, controls, sleep timer, and queue', (tester) async {
    final fakePlayer = FakeAudioPlayerService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakePlayer),
          mediaMetadataServiceProvider.overrideWithValue(FakeMediaMetadataService()),
        ],
        child: const MaterialApp(
          home: AudioPlayerScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('Mountain Echoes'), findsOneWidget);
    expect(find.text('Zen Composer'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);

    // Open Sleep Timer Dialog
    await tester.tap(find.byIcon(Icons.bedtime_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Sleep Timer'), findsOneWidget);
    expect(find.text('15 Minutes'), findsOneWidget);
    expect(find.text('30 Minutes'), findsOneWidget);

    // Dismiss bottom sheet
    await tester.tap(find.text('15 Minutes'));
    await tester.pumpAndSettle();
    expect(fakePlayer.currentSleepTimer, const Duration(minutes: 15));

    // Open Queue Sheet
    await tester.tap(find.byIcon(Icons.queue_music));
    await tester.pumpAndSettle();

    expect(find.text('Queue (2 tracks)'), findsOneWidget);
    expect(find.text('Ocean Waves'), findsOneWidget);
  });

  testWidgets('MiniAudioPlayerBar renders active track and triggers play/pause', (tester) async {
    final fakePlayer = FakeAudioPlayerService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakePlayer),
        ],
        child: const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: MiniAudioPlayerBar(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Mountain Echoes'), findsOneWidget);
    expect(find.text('Zen Composer'), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

    // Tap pause button on mini player
    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pumpAndSettle();

    expect(fakePlayer.currentStatus, AudioPlaybackStatus.paused);
  });
}
