import 'package:flutter_test/flutter_test.dart';
import 'package:filezen/domain/models/audio_playback_models.dart';

void main() {
  group('AudioQueueState & Queue Navigation', () {
    const track1 = AudioTrack(id: '/music/track1.mp3', path: '/music/track1.mp3', title: 'Track One', artist: 'Artist A');
    const track2 = AudioTrack(id: '/music/track2.mp3', path: '/music/track2.mp3', title: 'Track Two', artist: 'Artist B');
    const track3 = AudioTrack(id: '/music/track3.mp3', path: '/music/track3.mp3', title: 'Track Three', artist: 'Artist C');

    test('initializes with empty state and null currentTrack', () {
      const queue = AudioQueueState();
      expect(queue.isEmpty, isTrue);
      expect(queue.isNotEmpty, isFalse);
      expect(queue.length, 0);
      expect(queue.currentTrack, isNull);
      expect(queue.hasNext, isFalse);
      expect(queue.hasPrevious, isFalse);
    });

    test('returns correct currentTrack when loaded with items', () {
      const queue = AudioQueueState(tracks: [track1, track2, track3], currentIndex: 1);
      expect(queue.length, 3);
      expect(queue.currentTrack, equals(track2));
      expect(queue.currentTrack?.title, 'Track Two');
      expect(queue.hasNext, isTrue);
      expect(queue.hasPrevious, isTrue);
    });

    test('boundary conditions for hasNext and hasPrevious with RepeatMode.off', () {
      const firstQueue = AudioQueueState(tracks: [track1, track2], currentIndex: 0);
      expect(firstQueue.hasPrevious, isFalse);
      expect(firstQueue.hasNext, isTrue);

      const lastQueue = AudioQueueState(tracks: [track1, track2], currentIndex: 1);
      expect(lastQueue.hasPrevious, isTrue);
      expect(lastQueue.hasNext, isFalse);
    });

    test('hasNext and hasPrevious are always true when RepeatMode.all is active', () {
      const firstQueue = AudioQueueState(
        tracks: [track1, track2],
        currentIndex: 0,
        repeatMode: AudioRepeatMode.all,
      );
      expect(firstQueue.hasPrevious, isTrue);
      expect(firstQueue.hasNext, isTrue);

      const lastQueue = AudioQueueState(
        tracks: [track1, track2],
        currentIndex: 1,
        repeatMode: AudioRepeatMode.all,
      );
      expect(lastQueue.hasPrevious, isTrue);
      expect(lastQueue.hasNext, isTrue);
    });

    test('AudioTrack copyWith preserves and modifies fields', () {
      final modified = track1.copyWith(
        title: 'Updated Title',
        duration: const Duration(minutes: 3, seconds: 45),
      );
      expect(modified.id, track1.id);
      expect(modified.path, track1.path);
      expect(modified.title, 'Updated Title');
      expect(modified.artist, 'Artist A');
      expect(modified.duration, const Duration(minutes: 3, seconds: 45));
    });
  });
}
