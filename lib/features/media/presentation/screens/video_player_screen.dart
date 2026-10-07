import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../providers/media_providers.dart';

/// Immersive video player screen with playback scrubbing, speed selector,
/// aspect ratio toggling, playlist navigation, and metadata inspector.
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.videoPaths,
    this.initialIndex = 0,
  });

  final List<String> videoPaths;
  final int initialIndex;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  late int _currentIndex;
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isFillMode = false;
  double _playbackSpeed = 1.0;
  Timer? _hideControlsTimer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.videoPaths.isNotEmpty ? widget.videoPaths.length - 1 : 0);
    _initVideo(_currentIndex);
  }

  Future<void> _initVideo(int index) async {
    _hideControlsTimer?.cancel();
    await _controller?.dispose();
    _controller = null;
    setState(() {
      _errorMessage = null;
      _isPlaying = false;
    });

    if (widget.videoPaths.isEmpty) return;
    final path = widget.videoPaths[index];

    try {
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      await controller.setPlaybackSpeed(_playbackSpeed);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      controller.addListener(_videoListener);
      await controller.play();

      setState(() {
        _isPlaying = true;
      });
      _startHideControlsTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to play video: $e';
        });
      }
    }
  }

  void _videoListener() {
    if (!mounted || _controller == null) return;
    final isPlaying = _controller!.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() {
        _isPlaying = isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls && _isPlaying) {
      _startHideControlsTimer();
    }
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_isPlaying) {
      _controller!.pause();
      _hideControlsTimer?.cancel();
    } else {
      _controller!.play();
      _startHideControlsTimer();
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  void _seekRelative(int seconds) {
    if (_controller == null) return;
    final current = _controller!.value.position;
    final target = current + Duration(seconds: seconds);
    final total = _controller!.value.duration;
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(0, total.inMilliseconds),
    );
    _controller!.seekTo(clamped);
    _startHideControlsTimer();
  }

  void _nextVideo() {
    if (_currentIndex < widget.videoPaths.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _initVideo(_currentIndex);
    }
  }

  void _prevVideo() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _initVideo(_currentIndex);
    }
  }

  void _cycleSpeed() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final nextIdx = (speeds.indexOf(_playbackSpeed) + 1) % speeds.length;
    final nextSpeed = speeds[nextIdx];
    setState(() {
      _playbackSpeed = nextSpeed;
    });
    _controller?.setPlaybackSpeed(nextSpeed);
    _startHideControlsTimer();
  }

  void _showVideoInfo(String currentPath) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final metadataAsync = ref.watch(videoMetadataProvider(currentPath));
            final filename = p.basename(currentPath);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.movie_outlined, color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          filename,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  metadataAsync.when(
                    data: (meta) => Column(
                      children: [
                        _infoRow('Format', meta.format),
                        _infoRow(
                          'Duration',
                          _controller != null
                              ? Formatters.formatDuration(_controller!.value.duration)
                              : Formatters.formatDuration(meta.duration),
                        ),
                        if (_controller != null && _controller!.value.size.width > 0)
                          _infoRow(
                            'Resolution',
                            '${_controller!.value.size.width.toInt()} × ${_controller!.value.size.height.toInt()}',
                          )
                        else
                          _infoRow('Resolution', meta.resolutionString),
                        _infoRow('File Size', Formatters.formatFileSize(meta.fileSize)),
                        _infoRow('Path', currentPath, isPath: true),
                      ],
                    ),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (err, _) => Text('Error: $err', style: const TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _infoRow(String label, String value, {bool isPath = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: isPath ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.white54, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w400),
              maxLines: isPath ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videoPaths.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
        body: const Center(child: Text('No video to play', style: TextStyle(color: Colors.white70))),
      );
    }

    final currentPath = widget.videoPaths[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video Canvas
          GestureDetector(
            onTap: _toggleControls,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: _errorMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 54, color: AppColors.error),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    )
                  : (_controller != null && _controller!.value.isInitialized)
                      ? AspectRatio(
                          aspectRatio: _isFillMode
                              ? MediaQuery.of(context).size.aspectRatio
                              : _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        )
                      : const CircularProgressIndicator(color: AppColors.primary),
            ),
          ),

          // Overlay Controls
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Stack(
                children: [
                  // Top Header Gradient
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 8, right: 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black87, Colors.transparent],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.basename(currentPath),
                                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${_currentIndex + 1} of ${widget.videoPaths.length}',
                                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Video Details',
                            icon: const Icon(Icons.info_outline, color: Colors.white),
                            onPressed: () => _showVideoInfo(currentPath),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Center Controls: Rewind 10, Play/Pause, Forward 10
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 42,
                          color: Colors.white,
                          icon: const Icon(Icons.replay_10),
                          onPressed: () => _seekRelative(-10),
                        ),
                        const SizedBox(width: 32),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black45,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: IconButton(
                            iconSize: 56,
                            color: Colors.white,
                            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                            onPressed: _togglePlayPause,
                          ),
                        ),
                        const SizedBox(width: 32),
                        IconButton(
                          iconSize: 42,
                          color: Colors.white,
                          icon: const Icon(Icons.forward_10),
                          onPressed: () => _seekRelative(10),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Controls Gradient & Scrubber
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom + 8,
                        left: 16,
                        right: 16,
                        top: 16,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black87],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Scrubber & Timestamps
                          if (_controller != null && _controller!.value.isInitialized)
                            ValueListenableBuilder(
                              valueListenable: _controller!,
                              builder: (context, VideoPlayerValue value, _) {
                                final pos = value.position;
                                final dur = value.duration;
                                final maxMs = dur.inMilliseconds.toDouble();
                                final curMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs);

                                return Column(
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
                                          _controller!.seekTo(Duration(milliseconds: newMs.toInt()));
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            Formatters.formatDuration(pos),
                                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          ),
                                          Text(
                                            Formatters.formatDuration(dur),
                                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                          // Control Buttons Row: Prev, Speed, Next, Aspect Ratio
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Previous Video',
                                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                                    onPressed: _currentIndex > 0 ? _prevVideo : null,
                                  ),
                                  IconButton(
                                    tooltip: 'Next Video',
                                    icon: const Icon(Icons.skip_next, color: Colors.white),
                                    onPressed: _currentIndex < widget.videoPaths.length - 1 ? _nextVideo : null,
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: _cycleSpeed,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.white38),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${_playbackSpeed}x',
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: _isFillMode ? 'Fit Screen' : 'Fill Screen',
                                    icon: Icon(_isFillMode ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                                    onPressed: () {
                                      setState(() {
                                        _isFillMode = !_isFillMode;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
