import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/document_models.dart';
import '../providers/document_providers.dart';

/// Multi-format document viewer and text editor supporting Markdown, CSV tables,
/// JSON, XML, source code, and plain text with in-document search and live editing.
class DocumentViewerScreen extends ConsumerStatefulWidget {
  const DocumentViewerScreen({
    super.key,
    required this.filePath,
  });

  final String filePath;

  @override
  ConsumerState<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  late final TextEditingController _editController;
  late final TextEditingController _searchController;
  bool _isEditing = false;
  bool _isSearching = false;
  bool _showRawSource = false;
  bool _hasChanges = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _editController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final service = ref.read(documentServiceProvider);
    final success = await service.saveDocumentText(widget.filePath, _editController.text);
    if (!mounted) return;

    if (success) {
      ref.invalidate(documentTextProvider(widget.filePath));
      ref.invalidate(documentMetadataProvider(widget.filePath));
      ref.invalidate(csvTableDataProvider(widget.filePath));
      setState(() {
        _isEditing = false;
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document saved successfully'), backgroundColor: AppColors.success),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save document'), backgroundColor: AppColors.error),
      );
    }
  }

  void _showDocumentInfo(DocumentMetadata meta) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
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
                const Icon(Icons.info_outline, color: AppColors.primary, size: 22),
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
            _infoRow('Type', meta.type.displayName),
            _infoRow('File Size', Formatters.formatFileSize(meta.fileSize)),
            _infoRow('Lines', meta.lineCount.toString()),
            _infoRow('Words', meta.wordCount.toString()),
            _infoRow('Characters', meta.characterCount.toString()),
            _infoRow('Encoding', meta.encoding),
            _infoRow('Path', widget.filePath, isPath: true),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    final textAsync = ref.watch(documentTextProvider(widget.filePath));
    final metaAsync = ref.watch(documentMetadataProvider(widget.filePath));
    final docService = ref.watch(documentServiceProvider);
    final docType = docService.resolveDocumentType(widget.filePath);
    final filename = p.basename(widget.filePath);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search in document...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(filename, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(docType.displayName, style: const TextStyle(fontSize: 11, color: Colors.white60)),
                ],
              ),
        actions: [
          if (!_isEditing) ...[
            IconButton(
              tooltip: _isSearching ? 'Close Search' : 'Find in Document',
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    _searchQuery = '';
                  }
                });
              },
            ),
            if (docType.isMarkdown || docType.isCsv)
              IconButton(
                tooltip: _showRawSource ? 'Show Rendered View' : 'Show Raw Source',
                icon: Icon(_showRawSource ? Icons.visibility : Icons.code),
                onPressed: () => setState(() => _showRawSource = !_showRawSource),
              ),
            IconButton(
              tooltip: 'Edit Document',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                final currentText = textAsync.valueOrNull ?? '';
                _editController.text = currentText;
                setState(() {
                  _isEditing = true;
                  _hasChanges = false;
                });
              },
            ),
          ] else ...[
            TextButton(
              onPressed: () => setState(() => _isEditing = false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            IconButton(
              tooltip: 'Save Changes',
              icon: const Icon(Icons.save, color: AppColors.primary),
              onPressed: _hasChanges ? _saveChanges : null,
            ),
          ],
          metaAsync.when(
            data: (meta) => IconButton(
              tooltip: 'Document Info',
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showDocumentInfo(meta),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: textAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 12),
                Text('Unable to read document: $err', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        data: (content) {
          if (docType == DocumentType.unsupported) {
            return _buildUnsupportedFallback(context);
          }

          if (_isEditing) {
            return _buildEditorView();
          }

          if (docType.isMarkdown && !_showRawSource) {
            return _buildMarkdownView(content);
          }

          if (docType.isCsv && !_showRawSource) {
            return _buildCsvTableView();
          }

          return _buildTextCodeView(content);
        },
      ),
      bottomNavigationBar: metaAsync.when(
        data: (meta) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(top: BorderSide(color: AppColors.lightBorder.withValues(alpha: 0.3))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${meta.lineCount} lines  •  ${meta.wordCount} words  •  ${Formatters.formatFileSize(meta.fileSize)}',
                  style: AppTypography.bodySmall.copyWith(fontSize: 12),
                ),
                Text(
                  meta.encoding,
                  style: AppTypography.bodySmall.copyWith(fontSize: 12, color: AppColors.lightTextSecondary),
                ),
              ],
            ),
          ),
        ),
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildEditorView() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: TextField(
        controller: _editController,
        maxLines: null,
        expands: true,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Type text here...',
        ),
        onChanged: (_) {
          if (!_hasChanges) {
            setState(() => _hasChanges = true);
          }
        },
      ),
    );
  }

  Widget _buildMarkdownView(String content) {
    return Markdown(
      data: content,
      selectable: true,
      padding: const EdgeInsets.all(AppSpacing.md),
    );
  }

  Widget _buildCsvTableView() {
    final csvAsync = ref.watch(csvTableDataProvider(widget.filePath));

    return csvAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error rendering CSV table: $err')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('Empty CSV spreadsheet'));
        }

        final filteredRows = _searchQuery.isEmpty
            ? rows
            : rows.where((row) => row.any((cell) => cell.toString().toLowerCase().contains(_searchQuery.toLowerCase()))).toList();

        final headerRow = rows.first;
        final dataRows = filteredRows.skip(rows == filteredRows ? 1 : 0).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Text(
                'Showing ${dataRows.length} rows (${headerRow.length} columns)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: headerRow
                        .map((col) => DataColumn(
                              label: Text(
                                col.toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ))
                        .toList(),
                    rows: dataRows.map((row) {
                      return DataRow(
                        cells: List.generate(headerRow.length, (colIdx) {
                          final value = colIdx < row.length ? row[colIdx].toString() : '';
                          return DataCell(
                            SelectableText(
                              value,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextCodeView(String content) {
    final lines = content.split('\n');

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final isMatch = _searchQuery.isNotEmpty && line.toLowerCase().contains(_searchQuery.toLowerCase());

        return Container(
          color: isMatch ? AppColors.primary.withValues(alpha: 0.15) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.grey.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(
                  line.isEmpty ? ' ' : line,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.3),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnsupportedFallback(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 64, color: AppColors.typeDocument),
            const SizedBox(height: 16),
            Text(
              p.basename(widget.filePath),
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Office binary document formats (.docx, .xlsx, .pptx) can be opened with a compatible external office viewer on your device.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.lightTextSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Share / Open in App'),
              onPressed: () {
                // Clipboard copy path as safe fallback
                Clipboard.setData(ClipboardData(text: widget.filePath));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('File path copied to clipboard: ${widget.filePath}')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
