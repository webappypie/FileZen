# Phase 05 — Media Viewers & Playback Engine

## Objective
Establish high-performance, on-device media viewing and playback experiences for images, video, and audio: interactive image gallery with pan, pinch-to-zoom, 90° rotation, automated slideshow, and EXIF metadata extraction; video player with scrubber, playback speed selector, aspect ratio toggle, playlist navigation, and container metadata; audio player with timeline scrubber, repeat/shuffle modes, speed control, sleep timer countdown, and folder queue management; persistent floating mini audio player bar; and full integration into the file browser and universal search.

## Scope
- Domain Models & Enums:
  - `ImageMetadata`: Encapsulates resolution (`width`, `height`), `dateTaken`, camera make/model, lens, exposure time, aperture (`fNumber`), ISO, GPS coordinates, orientation, file size, and raw EXIF map.
  - `VideoMetadata`: Encapsulates duration, resolution, aspect ratio, file size, format.
  - `AudioMetadata`: Encapsulates title, artist, album, duration, file size, format.
  - `AudioTrack`: Model for individual audio files with path, title, artist, album, and duration.
  - `AudioPlaybackStatus`: Enum tracking `initial`, `loading`, `playing`, `paused`, `stopped`, `completed`, `error`.
  - `AudioRepeatMode`: Enum supporting `off`, `all`, `one`.
  - `AudioQueueState`: Manages playlist track collection, active track index, repeat mode, and shuffle mode.
- Media Metadata Extraction Engine:
  - `IMediaMetadataService` & `MediaMetadataService`:
    - Fast pure-Dart header probing for image dimensions across PNG, BMP, GIF, and JPEG without UI thread overhead.
    - EXIF parsing leveraging the `exif` package for camera parameters, shot settings, GPS latitude/longitude, and orientation.
    - ID3v1 and ID3v2 tag parsing for audio track titles, artists, and albums with null-byte stripping.
    - MP4/MOV container probing (`mvhd` atom) for video duration and resolution.
- Audio Playback Service:
  - `IAudioPlayerService` & `AudioPlayerService`:
    - Local audio playback using `audioplayers`.
    - Reactive broadcast streams for status, position, duration, queue state, and sleep timer.
    - Playlist navigation (`skipNext`, `skipPrevious`, `skipToIndex`, shuffle, repeat modes).
    - Playback speed adjustment (0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2.0x).
    - Sleep timer countdown with automatic audio pausing and stream notifications.
- Riverpod Presentation Architecture:
  - `media_providers.dart`:
    - `mediaMetadataServiceProvider`: Provider for metadata extraction.
    - `audioPlayerServiceProvider`: Singleton-like audio player lifecycle provider.
    - Reactive stream providers: `audioPlaybackStatusProvider`, `audioPositionProvider`, `audioDurationProvider`, `audioQueueProvider`, `audioSleepTimerProvider`.
    - Family metadata providers: `imageMetadataProvider`, `videoMetadataProvider`, `audioMetadataProvider`.
- Media Viewer UI & Components:
  - **`ImageViewerScreen`**:
    - Fullscreen immersive dark gallery.
    - `PageView.builder` for horizontal folder browsing.
    - `InteractiveViewer` with double-tap zoom, pinch-to-zoom, and smooth panning.
    - Clockwise 90° rotation toggle.
    - Automated slideshow mode (advances every 3.5 seconds with pause/resume).
    - Scroll-safe EXIF inspection bottom sheet with camera, lens, shot settings, resolution, and GPS data.
  - **`VideoPlayerScreen`**:
    - Video playback backed by ExoPlayer / Media3 via `video_player`.
    - Auto-hiding control overlays (fades after 3 seconds of inactivity).
    - Large central Play/Pause and 10-second skip forward/backward buttons.
    - Timeline scrubber slider with duration timestamps.
    - Playback speed selector (0.5x to 2.0x).
    - Aspect ratio toggle (fit vs fill screen).
    - Next/previous video navigation across directory siblings.
    - Scroll-safe video container metadata bottom sheet.
  - **`AudioPlayerScreen`**:
    - Fullscreen audio player with turntable art and category gradient.
    - Title, artist, and directory display.
    - Interactive timeline scrubber with live timestamp formatting.
    - Primary playback controls: Play/Pause, Next, Previous, 10s seek forward/rewind.
    - Shuffle and Repeat mode toggles (`off` -> `all` -> `one`).
    - Playback speed selector modal.
    - Sleep timer modal (15m, 30m, 45m, 60m, Turn Off) with active countdown badge.
    - Queue bottom sheet with track list and one-tap jumping.
  - **`MiniAudioPlayerBar`**:
    - Persistent floating mini player appearing above bottom navigation when audio is playing or paused.
    - Track title, play/pause toggle, next button, close button.
    - One-tap expansion into `AudioPlayerScreen`.
- Navigation & App Integration:
  - **`FilesScreen`**:
    - Tapping an image opens `ImageViewerScreen` with all sibling images in the directory.
    - Tapping a video opens `VideoPlayerScreen` with all sibling videos in the directory.
    - Tapping an audio file sets up the playlist queue and opens `AudioPlayerScreen`.
    - Context menu includes direct "View Image", "Play Video", and "Play Audio" actions.
    - `MiniAudioPlayerBar` embedded at the bottom.
  - **`SearchScreen`**:
    - File details dialog includes contextual "View Image", "Play Video", or "Play Audio" actions.
- Test Suite:
  - `test/unit/media_metadata_service_test.dart`: PNG, BMP, GIF dimension probing, ID3v1 parsing, video container inspection, non-existent file resilience.
  - `test/unit/audio_queue_test.dart`: Queue navigation, current track resolution, boundary conditions with repeat modes, copyWith immutability.
  - `test/widget/media_viewers_test.dart`: `ImageViewerScreen` (counter, zoom, rotation, EXIF sheet), `AudioPlayerScreen` (controls, sleep timer, queue modal), `MiniAudioPlayerBar` (active display, play/pause toggle).

## Out of Scope
- PDF Studio and document rendering engine (Phase 06).
- On-device ML Kit OCR models (Phase 07).
- Storage cleanup, duplicate analyzer, and large file detector (Phase 08).
- Secure Vault Keystore AES-256 encryption (Phase 09).
- Background notifications and WorkManager tasks (Phase 10).

## Dependencies
- `video_player: ^2.14.1`
- `audioplayers: ^6.8.1`
- `exif: ^3.3.0`
- `flutter_riverpod: ^2.6.1`
- `mime: ^2.1.0`
- `path: ^1.9.1`

## Modules & Files Created/Modified
- `pubspec.yaml` & `pubspec.lock` (Added `video_player`, `audioplayers`, `exif`)
- `lib/app/theme/app_colors.dart`
- `lib/core/utils/formatters.dart`
- `lib/domain/models/media_metadata.dart`
- `lib/domain/models/audio_playback_models.dart`
- `lib/domain/repositories/i_media_metadata_service.dart`
- `lib/domain/repositories/i_audio_player_service.dart`
- `lib/data/services/media_metadata_service.dart`
- `lib/data/services/audio_player_service.dart`
- `lib/features/media/presentation/providers/media_providers.dart`
- `lib/features/media/presentation/screens/image_viewer_screen.dart`
- `lib/features/media/presentation/screens/video_player_screen.dart`
- `lib/features/media/presentation/screens/audio_player_screen.dart`
- `lib/features/media/presentation/widgets/mini_audio_player_bar.dart`
- `lib/features/files/presentation/screens/files_screen.dart`
- `lib/features/search/presentation/screens/search_screen.dart`
- `test/unit/media_metadata_service_test.dart`
- `test/unit/audio_queue_test.dart`
- `test/widget/media_viewers_test.dart`
- `docs/04_Development_Roadmap/phase_05_media_playback.md`

## Verification & Test Results
- `flutter analyze`: **0 issues** found (clean static analysis).
- `flutter test`: **69 tests passing** (100% success rate across core, WAP client, database, search, file operations, media metadata extractor, audio queue, and media viewer widget suites).
