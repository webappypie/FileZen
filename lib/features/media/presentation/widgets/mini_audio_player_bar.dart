import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../app/theme/app_colors.dart';
import '../../../../domain/models/audio_playback_models.dart';
import '../providers/media_providers.dart';
import '../screens/audio_player_screen.dart';

/// Floating mini audio player bar displayed when an audio track is active in the background.
class MiniAudioPlayerBar extends ConsumerWidget {
  const MiniAudioPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerServiceProvider);
    final statusAsync = ref.watch(audioPlaybackStatusProvider);
    final queueAsync = ref.watch(audioQueueProvider);

    final status = statusAsync.value ?? player.currentStatus;
    final queue = queueAsync.value ?? player.currentQueue;
    final track = queue.currentTrack;

    // Only show if a track is loaded and status is not initial or stopped
    if (track == null ||
        status == AudioPlaybackStatus.initial ||
        status == AudioPlaybackStatus.stopped) {
      return const SizedBox.shrink();
    }

    final isPlaying = status == AudioPlaybackStatus.playing;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.audioOrange.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const AudioPlayerScreen(),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Animated / Glowing Icon
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.audioOrange.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.music_note,
                      color: AppColors.audioOrange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Track Info
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist ?? p.basename(p.dirname(track.path)),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Controls: Play/Pause, Next, Close
                  IconButton(
                    iconSize: 28,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                      color: AppColors.primary,
                    ),
                    onPressed: () {
                      if (isPlaying) {
                        player.pause();
                      } else {
                        player.play();
                      }
                    },
                  ),
                  IconButton(
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.skip_next, color: Colors.white70),
                    onPressed: queue.hasNext ? () => player.skipNext() : null,
                  ),
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: const Icon(Icons.close, color: Colors.white38),
                    onPressed: () => player.stop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
