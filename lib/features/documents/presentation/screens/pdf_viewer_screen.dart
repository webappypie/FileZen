import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/document_models.dart';
import '../providers/document_providers.dart';
import 'pdf_studio_screen.dart';

/// Full-featured PDF document viewer with page navigation, zoom,
/// PDF metadata inspection, and shortcuts to PDF Studio utilities.
class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.filePath,
  });

  final String filePath;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  late PdfController _pdfController;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  void _initPdf() {
    try {
      _pdfController = PdfController(
        document: PdfDocument.openFile(widget.filePath),
      );
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  void _showPdfInfo(PdfDocumentInfo info) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: AppColors.error, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.basename(widget.filePath),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow('Pages', '${info.pageCount} pages'),
            _infoRow('File Size', Formatters.formatFileSize(info.fileSize)),
            _infoRow('Title', info.titleOrFilename),
            _infoRow('Author', info.authorOrUnknown),
            if (info.subject != null) _infoRow('Subject', info.subject!),
            if (info.creator != null) _infoRow('Creator', info.creator!),
            if (info.creationDate != null) _infoRow('Created', Formatters.formatDate(info.creationDate!)),
            _infoRow('Encrypted', info.isEncrypted ? 'Yes' : 'No'),
            _infoRow('Path', widget.filePath, isPath: true),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isPath = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: isPath ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white54, fontWeight: FontWeight.w500))),
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

  void _showJumpToPageDialog() {
    final controller = TextEditingController(text: '$_currentPage');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jump to Page'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Page Number (1 - $_totalPages)',
            hintText: 'Enter page',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final page = int.tryParse(controller.text);
              if (page != null && page >= 1 && page <= _totalPages) {
                _pdfController.jumpToPage(page);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Jump'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pdfInfoAsync = ref.watch(pdfInfoProvider(widget.filePath));
    final filename = p.basename(widget.filePath);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(filename, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (_totalPages > 0)
              Text('Page $_currentPage of $_totalPages', style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Jump to Page',
            icon: const Icon(Icons.find_in_page_outlined),
            onPressed: _totalPages > 1 ? _showJumpToPageDialog : null,
          ),
          IconButton(
            tooltip: 'PDF Studio Tools',
            icon: const Icon(Icons.build_circle_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => PdfStudioScreen(initialSourcePdfPath: widget.filePath),
                ),
              );
            },
          ),
          pdfInfoAsync.when(
            data: (info) => IconButton(
              tooltip: 'PDF Properties',
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showPdfInfo(info),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text('Unable to open PDF: $_errorMessage', textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : PdfView(
                  controller: _pdfController,
                  scrollDirection: Axis.vertical,
                  onDocumentLoaded: (doc) {
                    setState(() {
                      _totalPages = doc.pagesCount;
                    });
                  },
                  onPageChanged: (page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                ),
      bottomNavigationBar: _totalPages > 1
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
                      onPressed: _currentPage > 1 ? () => _pdfController.previousPage(curve: Curves.ease, duration: const Duration(milliseconds: 200)) : null,
                    ),
                    Text(
                      'Page $_currentPage / $_totalPages',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                      onPressed: _currentPage < _totalPages ? () => _pdfController.nextPage(curve: Curves.ease, duration: const Duration(milliseconds: 200)) : null,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
