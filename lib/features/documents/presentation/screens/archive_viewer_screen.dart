import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/services/archive_service.dart';

class ArchiveEntryInfo {
  final String name;
  final int uncompressedSize;
  final int compressedSize;
  final bool isDirectory;

  const ArchiveEntryInfo({
    required this.name,
    required this.uncompressedSize,
    required this.compressedSize,
    required this.isDirectory,
  });
}

/// Archive browser screen for inspecting and safely extracting ZIP/archive containers.
class ArchiveViewerScreen extends StatefulWidget {
  const ArchiveViewerScreen({
    super.key,
    required this.filePath,
  });

  final String filePath;

  @override
  State<ArchiveViewerScreen> createState() => _ArchiveViewerScreenState();
}

class _ArchiveViewerScreenState extends State<ArchiveViewerScreen> {
  /// Inspecting decodes the whole archive in memory, so refuse anything that
  /// could exhaust the app's heap (compressed file size or inflated size).
  static const int _maxInspectFileBytes = 256 * 1024 * 1024;
  static const int _maxInspectInflatedBytes = 512 * 1024 * 1024;

  final ArchiveService _archiveService = ArchiveService();
  List<ArchiveEntryInfo> _entries = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _totalUncompressedSize = 0;
  bool _isExtracting = false;
  double _extractProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  Future<void> _loadArchive() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() {
          _errorMessage = 'Archive file not found';
          _isLoading = false;
        });
        return;
      }

      if (await file.length() > _maxInspectFileBytes) {
        setState(() {
          _errorMessage = 'Archive is too large to inspect on this device '
              '(limit ${Formatters.formatFileSize(_maxInspectFileBytes)}).';
          _isLoading = false;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      final ext = p.extension(widget.filePath).toLowerCase();

      // gzip stores the inflated size (mod 2^32) in its last 4 bytes; check it
      // before inflating so a tiny .gz cannot expand into gigabytes (gzip bomb).
      if ((ext == '.gz' || ext == '.tgz') && bytes.length > 4) {
        final tail = bytes.length - 4;
        final inflated = bytes[tail] |
            (bytes[tail + 1] << 8) |
            (bytes[tail + 2] << 16) |
            (bytes[tail + 3] << 24);
        if (inflated > _maxInspectInflatedBytes) {
          setState(() {
            _errorMessage = 'Archive expands to ${Formatters.formatFileSize(inflated)}, '
                'which is too large to inspect safely.';
            _isLoading = false;
          });
          return;
        }
      }

      final Archive archive;
      if (ext == '.zip') {
        archive = ZipDecoder().decodeBytes(bytes);
      } else if (ext == '.tar') {
        archive = TarDecoder().decodeBytes(bytes);
      } else if (ext == '.gz' || ext == '.tgz') {
        final decompressed = GZipDecoder().decodeBytes(bytes);
        if (ext == '.tgz') {
          archive = TarDecoder().decodeBytes(decompressed);
        } else {
          archive = Archive()..addFile(ArchiveFile(p.basenameWithoutExtension(widget.filePath), decompressed.length, decompressed));
        }
      } else {
        // Fallback try ZIP
        archive = ZipDecoder().decodeBytes(bytes);
      }

      int totalSize = 0;
      final entryList = <ArchiveEntryInfo>[];

      for (final entry in archive) {
        totalSize += entry.size;
        entryList.add(ArchiveEntryInfo(
          name: entry.name,
          uncompressedSize: entry.size,
          compressedSize: entry.rawContent?.length ?? entry.size,
          isDirectory: !entry.isFile,
        ));
      }

      setState(() {
        _entries = entryList;
        _totalUncompressedSize = totalSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to inspect archive: $e';
        _isLoading = false;
      });
    }
  }

  bool get _canExtract => p.extension(widget.filePath).toLowerCase() == '.zip';

  Future<void> _extractAll() async {
    final defaultDest = p.join(
      p.dirname(widget.filePath),
      p.basenameWithoutExtension(widget.filePath),
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extract Archive'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Extract ${_entries.length} items to:'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(defaultDest, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            ),
            const SizedBox(height: 10),
            Text('Total size: ${Formatters.formatFileSize(_totalUncompressedSize)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.folder_zip_rounded),
            label: const Text('Extract Here'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isExtracting = true;
      _extractProgress = 0.0;
    });

    final result = await _archiveService.extractZipArchive(
      zipFilePath: widget.filePath,
      destinationDirectory: defaultDest,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _extractProgress = p.ratio;
          });
        }
      },
    );

    if (!mounted) return;

    setState(() {
      _isExtracting = false;
    });

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archive extracted to $defaultDest'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Extraction failed: ${result.errorOrNull?.message}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.filePath);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (!_isLoading && _errorMessage == null)
              Text(
                '${_entries.length} items • ${Formatters.formatFileSize(_totalUncompressedSize)}',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.typeArchive,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
      body: _buildBody(isDark),
      bottomNavigationBar: (!_isLoading && _errorMessage == null && _entries.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: !_canExtract
                    ? Text(
                        'Extraction is available for ZIP archives only. This archive can be inspected here.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall,
                      )
                    : FilledButton.icon(
                  icon: const Icon(Icons.unarchive_rounded),
                  label: Text(_isExtracting ? 'Extracting (${(_extractProgress * 100).toInt()}%)...' : 'Extract All Files'),
                  onPressed: _isExtracting ? null : _extractAll,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Unable to open archive', style: AppTypography.titleMedium),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center, style: AppTypography.bodySmall),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return const Center(child: Text('Archive is empty'));
    }

    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: entry.isDirectory
                  ? AppColors.folderYellow.withValues(alpha: 0.15)
                  : AppColors.typeArchive.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              entry.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
              color: entry.isDirectory ? AppColors.folderYellow : AppColors.typeArchive,
              size: 20,
            ),
          ),
          title: Text(
            entry.name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: entry.isDirectory
              ? const Text('Folder', style: TextStyle(fontSize: 11))
              : Text(
                  Formatters.formatFileSize(entry.uncompressedSize),
                  style: const TextStyle(fontSize: 11),
                ),
        );
      },
    );
  }
}
