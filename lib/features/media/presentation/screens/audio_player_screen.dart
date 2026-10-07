import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/audio_playback_models.dart';
import '../providers/media_providers.dart';

/// Full-screen audio player with playlist queue sheet, scrubbing, speed selector,
/// repeat/shuffle modes, sleep timer, and track metadata.
class AudioPlayerScreen extends ConsumerWidget {
  const AudioPlayerScreen({super.key});

  void _showSleepTimerDialog(BuildContext context, WidgetRef ref) {
    final player = ref.read(audioPlayerServiceProvider);
    final activeTimer = player.currentSleepTimer;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.bedtime_outlined, color: AppColors.primary, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Sleep Timer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              if (activeTimer != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Timer active: ${Formatters.formatDuration(activeTimer)} remaining',
                  style: const TextStyle(color: AppColors.primary, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              _timerOption(context, '15 Minutes', const Duration(minutes: 15), player),
              _timerOption(context, '30 Minutes', const Duration(minutes: 30), player),
              _timerOption(context, '45 Minutes', const Duration(minutes: 45), player),
              _timerOption(context, '60 Minutes', const Duration(minutes: 60), player),
              if (activeTimer != null)
                ListTile(
                  leading: const Icon(Icons.timer_off, color: AppColors.error),
                  title: const Text('Turn Off Timer', style: TextStyle(color: AppColors.error)),
                  onTap: () {
                    player.setSleepTimer(null);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _timerOption(BuildContext context, String title, Duration duration, dynamic player) {
    return ListTile(
      leading: const Icon(Icons.timer, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () {
        player.setSleepTimer(duration);
        Navigator.pop(context);
      },
    );
  }

  void _showQueueSheet(BuildContext context, WidgetRef ref, AudioQueueState queue) {
    final player = ref.read(audioPlayerServiceProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.queue_music, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Queue (${queue.length} tracks)',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: queue.tracks.length,
                  itemBuilder: (context, index) {
                    final track = queue.tracks[index];
                    final isCurrent = index == queue.currentIndex;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: Icon(
                        isCurrent ? Icons.play_circle_fill : Icons.music_note,
                        color: isCurrent ? AppColors.primary : Colors.white54,
                      ),
                      title: Text(
                        track.title,
                        style: TextStyle(
                          color: isCurrent ? AppColors.primary : Colors.white,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artist ?? p.basename(p.dirname(track.path)),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        player.skipToIndex(index);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSpeedModal(BuildContext context, WidgetRef ref) {
    final player = ref.read(audioPlayerServiceProvider);
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Playback Speed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              ...speeds.map((s) {
                final isSelected = (player.playbackSpeed - s).abs() < 0.01;
                return ListTile(
                  title: Text('${s}x', style: TextStyle(color: isSelected ? AppColors.primary : Colors.white)),
                  trailing: isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
                  onTap: () {
                    player.setSpeed(s);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerServiceProvider);
    final statusAsync = ref.watch(audioPlaybackStatusProvider);
    final positionAsync = ref.watch(audioPositionProvider);
    final durationAsync = ref.watch(audioDurationProvider);
    final queueAsync = ref.watch(audioQueueProvider);
    final sleepTimerAsync = ref.watch(audioSleepTimerProvider);

    final queue = queueAsync.value ?? player.currentQueue;
    final track = queue.currentTrack;
    final status = statusAsync.value ?? player.currentStatus;
    final position = positionAsync.value ?? player.currentPosition;
    final duration = durationAsync.value ?? player.totalDuration;
    final sleepTimer = sleepTimerAsync.value ?? player.currentSleepTimer;

    final isPlaying = status == AudioPlaybackStatus.playing;
    final maxMs = duration.inMilliseconds.toDouble();
    final curMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Scaffold(
      backgroundColor: AppColors.surfaceDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 30, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text(
          'NOW PLAYING',
          style: TextStyle(fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        actions: [
          IconButton(
            tooltip: 'Sleep Timer',
            icon: Badge(
              isLabelVisible: sleepTimer != null,
              smallSize: 8,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.bedtime_outlined, color: Colors.white),
            ),
            onPressed: () => _showSleepTimerDialog(context, ref),
          ),
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music, color: Colors.white),
            onPressed: () => _showQueueSheet(context, ref, queue),
          ),
        ],
      ),
      body: track == null
          ? const Center(child: Text('No track loaded', style: TextStyle(color: Colors.white70)))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Album Art Card / Waveform Placeholder
                  Center(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            AppColors.audioOrange.withValues(alpha: 0.8),
                            AppColors.surfaceContainerDark,
                          ],
                          radius: 0.8,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.audioOrange.withValues(alpha: 0.25),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: const Icon(
                            Icons.music_note,
                            size: 42,
                            color: AppColors.audioOrange,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Track Info
                  Column(
                    children: [
                      Text(
                        track.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track.artist ?? p.basename(p.dirname(track.path)),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white60,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),

                  // Scrubber & Timestamps
                  Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: AppColors.primary,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          value: maxMs > 0 ? curMs : 0.0,
                          min: 0.0,
                          max: maxMs > 0 ? maxMs : 1.0,
                          onChanged: (newMs) {
                            player.seek(Duration(milliseconds: newMs.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              Formatters.formatDuration(position),
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            Text(
                              Formatters.formatDuration(duration),
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Controls Row: Shuffle, Prev, Play/Pause, Next, Repeat
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Shuffle',
                        icon: Icon(
                          Icons.shuffle,
                          color: queue.isShuffle ? AppColors.primary : Colors.white38,
                        ),
                        onPressed: () => player.toggleShuffle(),
                      ),
                      IconButton(
                        iconSize: 36,
                        tooltip: 'Previous',
                        icon: const Icon(Icons.skip_previous, color: Colors.white),
                        onPressed: () => player.skipPrevious(),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                        child: IconButton(
                          iconSize: 42,
                          color: Colors.black,
                          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                          onPressed: () {
                            if (isPlaying) {
                              player.pause();
                            } else {
                              player.play();
                            }
                          },
                        ),
                      ),
                      IconButton(
                        iconSize: 36,
                        tooltip: 'Next',
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        onPressed: () => player.skipNext(),
                      ),
                      IconButton(
                        tooltip: 'Repeat',
                        icon: Icon(
                          queue.repeatMode == AudioRepeatMode.one
                              ? Icons.repeat_one
                              : Icons.repeat,
                          color: queue.repeatMode != AudioRepeatMode.off
                              ? AppColors.primary
                              : Colors.white38,
                        ),
                        onPressed: () => player.toggleRepeat(),
                      ),
                    ],
                  ),

                  // Secondary Toolbar: Rewind 10s, Speed, Forward 10s
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Rewind 10s',
                        icon: const Icon(Icons.replay_10, color: Colors.white60),
                        onPressed: () => player.seekBy(const Duration(seconds: -10)),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () => _showSpeedModal(context, ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${player.playbackSpeed}x',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        tooltip: 'Forward 10s',
                        icon: const Icon(Icons.forward_10, color: Colors.white60),
                        onPressed: () => player.seekBy(const Duration(seconds: 10)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
