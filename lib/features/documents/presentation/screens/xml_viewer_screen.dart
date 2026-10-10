import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';

/// Structured, syntax-formatted viewer for XML and HTML documents.
class XmlViewerScreen extends StatefulWidget {
  const XmlViewerScreen({
    super.key,
    required this.filePath,
  });

  final String filePath;

  @override
  State<XmlViewerScreen> createState() => _XmlViewerScreenState();
}

class _XmlViewerScreenState extends State<XmlViewerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _rawContent = '';
  String _formattedContent = '';
  bool _isLoading = true;
  String? _parseError;
  bool _isSearching = false;
  String _searchQuery = '';
  bool _showRaw = false;
  double _fontSize = 13.0;

  @override
  void initState() {
    super.initState();
    _loadXml();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadXml() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() {
          _parseError = 'File does not exist: ${widget.filePath}';
          _isLoading = false;
        });
        return;
      }

      // The whole document is held (and pretty-printed) in memory.
      const maxBytes = 20 * 1024 * 1024;
      if (await file.length() > maxBytes) {
        setState(() {
          _parseError = 'File is too large to display here '
              '(limit ${Formatters.formatFileSize(maxBytes)}). Open it with another app instead.';
          _isLoading = false;
        });
        return;
      }

      final raw = await file.readAsString();
      _rawContent = raw;

      try {
        final document = XmlDocument.parse(raw);
        _formattedContent = document.toXmlString(pretty: true, indent: '  ');
        _parseError = null;
      } catch (e) {
        // Not perfectly well-formed XML: fall back to raw content
        _formattedContent = raw;
        _parseError = 'Not well-formed XML: ${e.toString()}';
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _parseError = 'Failed to read XML file: $e';
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard() {
    final text = _showRaw ? _rawContent : _formattedContent;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('XML content copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.filePath);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search tag, attribute, or value...',
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    _showRaw ? 'Raw XML' : 'Structured XML',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _isSearching ? 'Close search' : 'Search XML',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: Icon(_showRaw ? Icons.code_rounded : Icons.account_tree_outlined),
            tooltip: _showRaw ? 'Show Formatted Tree' : 'Show Raw Source',
            onPressed: () => setState(() => _showRaw = !_showRaw),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'copy') _copyToClipboard();
              if (val == 'zoom_in') setState(() => _fontSize = (_fontSize + 1.5).clamp(10.0, 24.0));
              if (val == 'zoom_out') setState(() => _fontSize = (_fontSize - 1.5).clamp(10.0, 24.0));
              if (val == 'details') _showDetailsDialog(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('Copy All')),
              const PopupMenuItem(value: 'zoom_in', child: Text('Increase Text Size')),
              const PopupMenuItem(value: 'zoom_out', child: Text('Decrease Text Size')),
              const PopupMenuItem(value: 'details', child: Text('File Properties')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_parseError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.amber.withValues(alpha: 0.2),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Displaying raw XML (syntax notice: ${_parseError!})',
                            style: const TextStyle(fontSize: 11, color: Colors.orange),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: _buildXmlContent(isDark)),
              ],
            ),
    );
  }

  Widget _buildXmlContent(bool isDark) {
    final content = _showRaw ? _rawContent : _formattedContent;
    final lines = content.split('\n');

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final isMatch = _searchQuery.isNotEmpty &&
            line.toLowerCase().contains(_searchQuery.toLowerCase());

        return Container(
          color: isMatch ? AppColors.primary.withValues(alpha: 0.2) : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: _fontSize - 2,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(
                  line.isEmpty ? ' ' : line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: _fontSize,
                    height: 1.35,
                    color: _getLineColor(line, isDark),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color? _getLineColor(String line, bool isDark) {
    final trimmed = line.trim();
    if (trimmed.startsWith('<!--')) {
      return isDark ? Colors.green[400] : Colors.green[700];
    }
    if (trimmed.startsWith('<?xml') || trimmed.startsWith('<!DOCTYPE')) {
      return Colors.purpleAccent;
    }
    if (trimmed.startsWith('<') && trimmed.endsWith('>')) {
      return isDark ? Colors.lightBlueAccent : Colors.blue[800];
    }
    return null;
  }

  void _showDetailsDialog(BuildContext context) async {
    final file = File(widget.filePath);
    final size = await file.length();
    final modified = await file.lastModified();

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('XML Document Properties'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${p.basename(widget.filePath)}'),
            const SizedBox(height: 6),
            Text('Size: ${Formatters.formatFileSize(size)}'),
            const SizedBox(height: 6),
            Text('Lines: ${_formattedContent.split('\n').length}'),
            const SizedBox(height: 6),
            Text('Modified: ${Formatters.formatDate(modified)}'),
            const SizedBox(height: 6),
            Text('Path: ${widget.filePath}', style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
