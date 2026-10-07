import '../models/audio_playback_models.dart';

/// Clean Architecture interface for managing audio playback, playlist queues, and sleep timers.
abstract class IAudioPlayerService {
  /// Stream of playback status updates (playing, paused, stopped, etc.).
  Stream<AudioPlaybackStatus> get statusStream;

  /// Stream of current playback timestamp position.
  Stream<Duration> get positionStream;

  /// Stream of current track duration.
  Stream<Duration> get durationStream;

  /// Stream of playlist queue updates.
  Stream<AudioQueueState> get queueStream;

  /// Stream of active sleep timer countdown (remaining duration or null when inactive).
  Stream<Duration?> get sleepTimerStream;

  /// Current queue state.
  AudioQueueState get currentQueue;

  /// Current playback status.
  AudioPlaybackStatus get currentStatus;

  /// Current playback position timestamp.
  Duration get currentPosition;

  /// Total duration of active track.
  Duration get totalDuration;

  /// Current playback speed multiplier.
  double get playbackSpeed;

  /// Active sleep timer remaining duration, or null if disabled.
  Duration? get currentSleepTimer;

  /// Set the playlist queue and optionally start playing immediately.
  Future<void> setQueue(List<AudioTrack> tracks, {int initialIndex = 0, bool autoPlay = true});

  /// Resume or start playback.
  Future<void> play();

  /// Pause current playback.
  Future<void> pause();

  /// Stop current playback and reset position.
  Future<void> stop();

  /// Seek to a specific timestamp in the current track.
  Future<void> seek(Duration position);

  /// Skip forward or backward relative to current position.
  Future<void> seekBy(Duration offset);

  /// Skip to the next track in the queue.
  Future<void> skipNext();

  /// Skip to the previous track in the queue.
  Future<void> skipPrevious();

  /// Jump directly to a track index in the queue.
  Future<void> skipToIndex(int index);

  /// Adjust the playback speed multiplier (e.g. 0.5x, 1.0x, 1.5x, 2.0x).
  Future<void> setSpeed(double speed);

  /// Cycle through repeat modes (off -> all -> one -> off).
  Future<void> toggleRepeat();

  /// Toggle shuffle mode on or off.
  Future<void> toggleShuffle();

  /// Set or cancel the sleep timer.
  void setSleepTimer(Duration? duration);

  /// Dispose player resources.
  Future<void> dispose();
}
