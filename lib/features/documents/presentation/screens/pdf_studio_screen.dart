import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/document_models.dart';
import '../providers/document_providers.dart';
import 'pdf_viewer_screen.dart';

/// PDF Studio suite providing Images-to-PDF compilation, PDF merging, and page extraction tools.
class PdfStudioScreen extends ConsumerStatefulWidget {
  const PdfStudioScreen({
    super.key,
    this.initialSourcePdfPath,
  });

  final String? initialSourcePdfPath;

  @override
  ConsumerState<PdfStudioScreen> createState() => _PdfStudioScreenState();
}

class _PdfStudioScreenState extends ConsumerState<PdfStudioScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Images to PDF state
  final _imgTitleController = TextEditingController(text: 'Scanned Document');
  final _imgPathsController = TextEditingController();
  bool _isProcessingImg = false;
  PdfOperationResult? _imgResult;

  // Merge PDFs state
  final _mergePdfsController = TextEditingController();
  final _mergeOutputController = TextEditingController(text: 'Merged_Document.pdf');
  bool _isProcessingMerge = false;
  PdfOperationResult? _mergeResult;

  // Extract Pages state
  late final TextEditingController _extractSourceController;
  final _extractPagesController = TextEditingController(text: '1, 2');
  final _extractOutputController = TextEditingController(text: 'Extracted_Pages.pdf');
  bool _isProcessingExtract = false;
  PdfOperationResult? _extractResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _extractSourceController = TextEditingController(text: widget.initialSourcePdfPath ?? '');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _imgTitleController.dispose();
    _imgPathsController.dispose();
    _mergePdfsController.dispose();
    _mergeOutputController.dispose();
    _extractSourceController.dispose();
    _extractPagesController.dispose();
    _extractOutputController.dispose();
    super.dispose();
  }

  Future<void> _runImagesToPdf() async {
    final rawPaths = _imgPathsController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (rawPaths.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one image file path')),
      );
      return;
    }

    setState(() {
      _isProcessingImg = true;
      _imgResult = null;
    });

    final service = ref.read(pdfStudioServiceProvider);
    final firstDir = p.dirname(rawPaths.first);
    final outputPath = p.join(firstDir, '${_imgTitleController.text.trim().replaceAll(' ', '_')}.pdf');

    final res = await service.imagesToPdf(
      rawPaths,
      outputPath,
      title: _imgTitleController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _isProcessingImg = false;
        _imgResult = res;
      });
    }
  }

  Future<void> _runMergePdfs() async {
    final rawPaths = _mergePdfsController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (rawPaths.length < 2) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least two PDF file paths to merge')),
      );
      return;
    }

    setState(() {
      _isProcessingMerge = true;
      _mergeResult = null;
    });

    final service = ref.read(pdfStudioServiceProvider);
    final firstDir = p.dirname(rawPaths.first);
    final outputPath = p.join(firstDir, _mergeOutputController.text.trim());

    final res = await service.mergePdfs(rawPaths, outputPath);

    if (mounted) {
      setState(() {
        _isProcessingMerge = false;
        _mergeResult = res;
      });
    }
  }

  Future<void> _runExtractPages() async {
    final sourcePath = _extractSourceController.text.trim();
    if (sourcePath.isEmpty || !File(sourcePath).existsSync()) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a source PDF file path')),
      );
      return;
    }

    final pagesStr = _extractPagesController.text.trim();
    final pageNumbers = <int>[];
    for (final part in pagesStr.split(',')) {
      final trimmed = part.trim();
      if (trimmed.contains('-')) {
        final range = trimmed.split('-');
        if (range.length == 2) {
          final start = int.tryParse(range[0].trim());
          final end = int.tryParse(range[1].trim());
          if (start != null && end != null && start <= end) {
            for (var i = start; i <= end; i++) {
              pageNumbers.add(i);
            }
          }
        }
      } else {
        final num = int.tryParse(trimmed);
        if (num != null) pageNumbers.add(num);
      }
    }

    if (pageNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid page numbers (e.g. 1, 2, 5 or 1-3)')),
      );
      return;
    }

    setState(() {
      _isProcessingExtract = true;
      _extractResult = null;
    });

    final service = ref.read(pdfStudioServiceProvider);
    final outDir = p.dirname(sourcePath);
    final outputPath = p.join(outDir, _extractOutputController.text.trim());

    final res = await service.extractPages(sourcePath, pageNumbers, outputPath);

    if (mounted) {
      setState(() {
        _isProcessingExtract = false;
        _extractResult = res;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Studio'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.photo_library_outlined), text: 'Images to PDF'),
            Tab(icon: Icon(Icons.merge_type_rounded), text: 'Merge PDFs'),
            Tab(icon: Icon(Icons.call_split_rounded), text: 'Extract Pages'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildImagesToPdfTab(),
          _buildMergePdfsTab(),
          _buildExtractPagesTab(),
        ],
      ),
    );
  }

  Widget _buildImagesToPdfTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Compile Images to PDF',
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Create a single organized PDF document from one or multiple images.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.lightTextSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _imgTitleController,
          decoration: const InputDecoration(
            labelText: 'Document Title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _imgPathsController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Image File Paths (one per line)',
            hintText: '/storage/emulated/0/DCIM/photo1.jpg\n/storage/emulated/0/DCIM/photo2.jpg',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isProcessingImg ? null : _runImagesToPdf,
          icon: _isProcessingImg
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_isProcessingImg ? 'Generating PDF...' : 'Convert to PDF'),
        ),
        if (_imgResult != null) ...[
          const SizedBox(height: 16),
          _buildResultCard(_imgResult!),
        ],
      ],
    );
  }

  Widget _buildMergePdfsTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Merge Multiple PDFs',
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Combine two or more PDF documents into a single unified file.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.lightTextSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _mergeOutputController,
          decoration: const InputDecoration(
            labelText: 'Output Filename',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mergePdfsController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'PDF File Paths to Merge (one per line)',
            hintText: '/storage/emulated/0/doc1.pdf\n/storage/emulated/0/doc2.pdf',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isProcessingMerge ? null : _runMergePdfs,
          icon: _isProcessingMerge
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.merge_type_rounded),
          label: Text(_isProcessingMerge ? 'Merging Documents...' : 'Merge PDFs'),
        ),
        if (_mergeResult != null) ...[
          const SizedBox(height: 16),
          _buildResultCard(_mergeResult!),
        ],
      ],
    );
  }

  Widget _buildExtractPagesTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Extract PDF Pages',
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Split and export selected pages from a PDF document.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.lightTextSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _extractSourceController,
          decoration: const InputDecoration(
            labelText: 'Source PDF File Path',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _extractPagesController,
          decoration: const InputDecoration(
            labelText: 'Pages to Extract (e.g. 1, 3, 5-8)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _extractOutputController,
          decoration: const InputDecoration(
            labelText: 'Output Filename',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isProcessingExtract ? null : _runExtractPages,
          icon: _isProcessingExtract
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.call_split_rounded),
          label: Text(_isProcessingExtract ? 'Extracting Pages...' : 'Extract Pages'),
        ),
        if (_extractResult != null) ...[
          const SizedBox(height: 16),
          _buildResultCard(_extractResult!),
        ],
      ],
    );
  }

  Widget _buildResultCard(PdfOperationResult result) {
    if (!result.success) {
      return Card(
        color: AppColors.error.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.error)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Operation failed: ${result.errorMessage}', style: const TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: AppColors.success.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.success)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  'PDF Ready!',
                  style: AppTypography.titleMedium.copyWith(color: AppColors.success, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${result.pagesProcessed} pages  •  ${Formatters.formatFileSize(result.outputSizeBytes)}',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              result.outputPath,
              style: AppTypography.bodySmall.copyWith(color: AppColors.lightTextSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Open in PDF Viewer'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => PdfViewerScreen(filePath: result.outputPath),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
