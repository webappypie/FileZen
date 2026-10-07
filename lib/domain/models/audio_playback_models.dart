/// Domain models for audio queue, track details, and playback state.
library;

enum AudioPlaybackStatus {
  initial,
  loading,
  playing,
  paused,
  stopped,
  completed,
  error,
}

enum AudioRepeatMode {
  off,
  all,
  one,
}

class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.path,
    required this.title,
    this.artist,
    this.album,
    this.duration,
  });

  final String id;
  final String path;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;

  AudioTrack copyWith({
    String? id,
    String? path,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
  }) {
    return AudioTrack(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioTrack && runtimeType == other.runtimeType && id == other.id && path == other.path;

  @override
  int get hashCode => id.hashCode ^ path.hashCode;
}

class AudioQueueState {
  const AudioQueueState({
    this.tracks = const [],
    this.currentIndex = 0,
    this.repeatMode = AudioRepeatMode.off,
    this.isShuffle = false,
  });

  final List<AudioTrack> tracks;
  final int currentIndex;
  final AudioRepeatMode repeatMode;
  final bool isShuffle;

  bool get isEmpty => tracks.isEmpty;
  bool get isNotEmpty => tracks.isNotEmpty;
  int get length => tracks.length;

  AudioTrack? get currentTrack {
    if (tracks.isEmpty || currentIndex < 0 || currentIndex >= tracks.length) {
      return null;
    }
    return tracks[currentIndex];
  }

  bool get hasNext {
    if (tracks.isEmpty) return false;
    if (repeatMode != AudioRepeatMode.off) return true;
    return currentIndex < tracks.length - 1;
  }

  bool get hasPrevious {
    if (tracks.isEmpty) return false;
    if (repeatMode != AudioRepeatMode.off) return true;
    return currentIndex > 0;
  }

  AudioQueueState copyWith({
    List<AudioTrack>? tracks,
    int? currentIndex,
    AudioRepeatMode? repeatMode,
    bool? isShuffle,
  }) {
    return AudioQueueState(
      tracks: tracks ?? this.tracks,
      currentIndex: currentIndex ?? this.currentIndex,
      repeatMode: repeatMode ?? this.repeatMode,
      isShuffle: isShuffle ?? this.isShuffle,
    );
  }
}
