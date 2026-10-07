import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/audio_playback_models.dart';
import '../../domain/repositories/i_audio_player_service.dart';

/// Service implementing IAudioPlayerService using audioplayers and background-safe controllers.
class AudioPlayerService implements IAudioPlayerService {
  AudioPlayerService({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _initListeners();
  }

  final AudioPlayer _player;

  final _statusController = StreamController<AudioPlaybackStatus>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _queueController = StreamController<AudioQueueState>.broadcast();
  final _sleepTimerController = StreamController<Duration?>.broadcast();

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  Timer? _sleepTimer;

  AudioPlaybackStatus _status = AudioPlaybackStatus.initial;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AudioQueueState _queue = const AudioQueueState();
  double _speed = 1.0;
  Duration? _currentSleepTimer;

  void _initListeners() {
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      switch (state) {
        case PlayerState.playing:
          _updateStatus(AudioPlaybackStatus.playing);
          break;
        case PlayerState.paused:
          _updateStatus(AudioPlaybackStatus.paused);
          break;
        case PlayerState.stopped:
          _updateStatus(AudioPlaybackStatus.stopped);
          break;
        case PlayerState.completed:
          _handleTrackCompleted();
          break;
        default:
          break;
      }
    }, onError: (err) {
      AppLogger.error('AudioPlayer state error: $err', 'AudioPlayerService');
      _updateStatus(AudioPlaybackStatus.error);
    });

    _posSub = _player.onPositionChanged.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      _duration = dur;
      _durationController.add(dur);
    });
  }

  void _updateStatus(AudioPlaybackStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void _updateQueue(AudioQueueState queue) {
    _queue = queue;
    _queueController.add(queue);
  }

  Future<void> _handleTrackCompleted() async {
    _updateStatus(AudioPlaybackStatus.completed);

    if (_queue.repeatMode == AudioRepeatMode.one) {
      await seek(Duration.zero);
      await play();
      return;
    }

    if (_queue.hasNext) {
      await skipNext();
    } else if (_queue.repeatMode == AudioRepeatMode.all && _queue.isNotEmpty) {
      await skipToIndex(0);
    } else {
      await stop();
    }
  }

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
  Duration? get currentSleepTimer => _currentSleepTimer;

  @override
  Future<void> setQueue(List<AudioTrack> tracks, {int initialIndex = 0, bool autoPlay = true}) async {
    if (tracks.isEmpty) {
      await stop();
      _updateQueue(const AudioQueueState());
      return;
    }

    final validIndex = initialIndex.clamp(0, tracks.length - 1);
    _updateQueue(_queue.copyWith(tracks: tracks, currentIndex: validIndex));

    if (autoPlay) {
      await _playTrack(tracks[validIndex]);
    }
  }

  Future<void> _playTrack(AudioTrack track) async {
    try {
      _updateStatus(AudioPlaybackStatus.loading);
      await _player.stop();
      await _player.setSource(DeviceFileSource(track.path));
      await _player.setPlaybackRate(_speed);
      await _player.resume();
      _updateStatus(AudioPlaybackStatus.playing);
    } catch (e) {
      AppLogger.error('Failed to play audio track ${track.path}: $e', 'AudioPlayerService');
      _updateStatus(AudioPlaybackStatus.error);
    }
  }

  @override
  Future<void> play() async {
    final track = _queue.currentTrack;
    if (track == null) return;

    if (_status == AudioPlaybackStatus.paused) {
      await _player.resume();
      _updateStatus(AudioPlaybackStatus.playing);
    } else {
      await _playTrack(track);
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _updateStatus(AudioPlaybackStatus.paused);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _position = Duration.zero;
    _positionController.add(Duration.zero);
    _updateStatus(AudioPlaybackStatus.stopped);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _position = position;
    _positionController.add(position);
  }

  @override
  Future<void> seekBy(Duration offset) async {
    final newPos = _position + offset;
    final clamped = Duration(
      milliseconds: newPos.inMilliseconds.clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : double.infinity.toInt()),
    );
    await seek(clamped);
  }

  @override
  Future<void> skipNext() async {
    if (_queue.isEmpty) return;

    int nextIdx;
    if (_queue.isShuffle && _queue.tracks.length > 1) {
      // Pick random index different from current
      final indexes = List.generate(_queue.tracks.length, (i) => i)..remove(_queue.currentIndex);
      indexes.shuffle();
      nextIdx = indexes.first;
    } else if (_queue.currentIndex < _queue.tracks.length - 1) {
      nextIdx = _queue.currentIndex + 1;
    } else if (_queue.repeatMode == AudioRepeatMode.all) {
      nextIdx = 0;
    } else {
      return;
    }

    await skipToIndex(nextIdx);
  }

  @override
  Future<void> skipPrevious() async {
    if (_queue.isEmpty) return;

    // If more than 3 seconds in, restart current track
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    int prevIdx;
    if (_queue.currentIndex > 0) {
      prevIdx = _queue.currentIndex - 1;
    } else if (_queue.repeatMode == AudioRepeatMode.all) {
      prevIdx = _queue.tracks.length - 1;
    } else {
      await seek(Duration.zero);
      return;
    }

    await skipToIndex(prevIdx);
  }

  @override
  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _queue.tracks.length) return;
    _updateQueue(_queue.copyWith(currentIndex: index));
    await _playTrack(_queue.tracks[index]);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _player.setPlaybackRate(speed);
  }

  @override
  Future<void> toggleRepeat() async {
    final nextMode = switch (_queue.repeatMode) {
      AudioRepeatMode.off => AudioRepeatMode.all,
      AudioRepeatMode.all => AudioRepeatMode.one,
      AudioRepeatMode.one => AudioRepeatMode.off,
    };
    _updateQueue(_queue.copyWith(repeatMode: nextMode));
  }

  @override
  Future<void> toggleShuffle() async {
    _updateQueue(_queue.copyWith(isShuffle: !_queue.isShuffle));
  }

  @override
  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _currentSleepTimer = duration;
    _sleepTimerController.add(duration);

    if (duration == null || duration <= Duration.zero) return;

    var remainingSeconds = duration.inSeconds;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remainingSeconds--;
      if (remainingSeconds <= 0) {
        timer.cancel();
        _currentSleepTimer = null;
        _sleepTimerController.add(null);
        pause();
      } else {
        _currentSleepTimer = Duration(seconds: remainingSeconds);
        _sleepTimerController.add(_currentSleepTimer);
      }
    });
  }

  @override
  Future<void> dispose() async {
    _sleepTimer?.cancel();
    await _stateSub?.cancel();
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _player.dispose();
    await _statusController.close();
    await _positionController.close();
    await _durationController.close();
    await _queueController.close();
    await _sleepTimerController.close();
  }
}
