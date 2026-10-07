import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/media_metadata.dart';
import '../providers/media_providers.dart';

/// Immersive image gallery viewer with pinch-to-zoom, pan, rotation, slideshow, and EXIF inspection.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
  });

  final List<String> imagePaths;
  final int initialIndex;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showOverlays = true;
  bool _isSlideshowRunning = false;
  Timer? _slideshowTimer;
  final Map<int, int> _rotations = {}; // index -> quarterTurns (0..3)

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imagePaths.isNotEmpty ? widget.imagePaths.length - 1 : 0);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _toggleOverlays() {
    setState(() {
      _showOverlays = !_showOverlays;
    });
  }

  void _rotateCurrent() {
    setState(() {
      final current = _rotations[_currentIndex] ?? 0;
      _rotations[_currentIndex] = (current + 1) % 4;
    });
  }

  void _toggleSlideshow() {
    setState(() {
      _isSlideshowRunning = !_isSlideshowRunning;
    });

    _slideshowTimer?.cancel();
    _slideshowTimer = null;

    if (_isSlideshowRunning) {
      _slideshowTimer = Timer.periodic(const Duration(milliseconds: 3500), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_currentIndex < widget.imagePaths.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        } else {
          // Loop back to start
          _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  void _showImageInfo(String currentPath) {
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
            final metadataAsync = ref.watch(imageMetadataProvider(currentPath));
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
                      const Icon(Icons.info_outline, color: AppColors.primary, size: 22),
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
                    data: (meta) => _buildExifDetails(meta, currentPath),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (err, _) => Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text('Failed to load EXIF: $err', style: const TextStyle(color: Colors.white70)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExifDetails(ImageMetadata meta, String path) {
    return Column(
      children: [
        _infoRow('Resolution', meta.resolutionString),
        _infoRow('File Size', Formatters.formatFileSize(meta.fileSize)),
        _infoRow('MIME Type', meta.mimeType),
        if (meta.dateTaken != null) _infoRow('Date Taken', Formatters.formatDateTime(meta.dateTaken!)),
        if (meta.cameraMake != null || meta.cameraModel != null) _infoRow('Camera', meta.cameraString),
        if (meta.lensModel != null) _infoRow('Lens', meta.lensModel!),
        if (meta.fNumber != null || meta.exposureTime != null || meta.iso != null)
          _infoRow(
            'Shot Settings',
            [
              if (meta.fNumber != null) 'f/${meta.fNumber}',
              if (meta.exposureTime != null) '${meta.exposureTime}s',
              if (meta.iso != null) 'ISO ${meta.iso}',
              if (meta.focalLength != null) meta.focalLength!,
            ].join('  •  '),
          ),
        if (meta.hasGps) _infoRow('GPS Location', meta.formattedGps),
        _infoRow('Path', path, isPath: true),
      ],
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
    if (widget.imagePaths.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
        body: const Center(child: Text('No images to view', style: TextStyle(color: Colors.white70))),
      );
    }

    final currentPath = widget.imagePaths[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable Gallery
          GestureDetector(
            onTap: _toggleOverlays,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.imagePaths.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final path = widget.imagePaths[index];
                final quarterTurns = _rotations[index] ?? 0;

                return Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: RotatedBox(
                      quarterTurns: quarterTurns,
                      child: Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.broken_image_outlined, size: 64, color: Colors.white38),
                                const SizedBox(height: 12),
                                Text(
                                  'Unable to load image\n${p.basename(path)}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Slideshow indicator
          if (_isSlideshowRunning)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.slideshow, size: 16, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text('Slideshow playing', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),

          // Top Overlay AppBar
          AnimatedOpacity(
            opacity: _showOverlays ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showOverlays,
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
                            '${_currentIndex + 1} of ${widget.imagePaths.length}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _isSlideshowRunning ? 'Stop Slideshow' : 'Start Slideshow',
                      icon: Icon(
                        _isSlideshowRunning ? Icons.pause_circle_filled : Icons.play_circle_outline,
                        color: _isSlideshowRunning ? AppColors.primary : Colors.white,
                      ),
                      onPressed: _toggleSlideshow,
                    ),
                    IconButton(
                      tooltip: 'Rotate 90°',
                      icon: const Icon(Icons.rotate_right, color: Colors.white),
                      onPressed: _rotateCurrent,
                    ),
                    IconButton(
                      tooltip: 'Image Info & EXIF',
                      icon: const Icon(Icons.info_outline, color: Colors.white),
                      onPressed: () => _showImageInfo(currentPath),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
