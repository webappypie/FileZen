import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import '../../core/logging/app_logger.dart';
import '../../domain/models/document_models.dart';
import '../../domain/repositories/i_pdf_studio_service.dart';

/// Implementation of IPdfStudioService using pure-Dart pdf document compiler
/// and pdfx document inspection & page rendering.
class PdfStudioService implements IPdfStudioService {
  const PdfStudioService();

  @override
  Future<PdfDocumentInfo> getPdfInfo(String filePath) async {
    final file = File(filePath);
    final exists = await file.exists();
    final fileSize = exists ? await file.length() : 0;

    if (!exists || fileSize == 0) {
      return PdfDocumentInfo(
        filePath: filePath,
        pageCount: 0,
        fileSize: 0,
      );
    }

    int pageCount = 0;
    String? title;
    String? author;
    String? subject;
    String? creator;
    DateTime? creationDate;
    bool isEncrypted = false;

    // First attempt quick binary header and trailer inspection
    try {
      final bytesToRead = fileSize < 65536 ? fileSize : 65536;
      final raf = await file.open(mode: FileMode.read);
      final head = await raf.read(bytesToRead);

      // Also read tail for trailer dictionary
      Uint8List tail = head;
      if (fileSize > 65536) {
        await raf.setPosition(fileSize - 32768);
        tail = await raf.read(32768);
      }
      await raf.close();

      final headText = latin1.decode(head);
      final tailText = latin1.decode(tail);
      final combined = '$headText\n$tailText';

      isEncrypted = combined.contains('/Encrypt');

      // Title
      final titleMatch = RegExp(r'/Title\s*\(([^)]+)\)').firstMatch(combined);
      if (titleMatch != null) title = titleMatch.group(1);

      // Author
      final authorMatch = RegExp(r'/Author\s*\(([^)]+)\)').firstMatch(combined);
      if (authorMatch != null) author = authorMatch.group(1);

      // Creator
      final creatorMatch = RegExp(r'/Creator\s*\(([^)]+)\)').firstMatch(combined);
      if (creatorMatch != null) creator = creatorMatch.group(1);

      // CreationDate
      final dateMatch = RegExp(r'/CreationDate\s*\(D:(\d{4})(\d{2})(\d{2})').firstMatch(combined);
      if (dateMatch != null) {
        final year = int.tryParse(dateMatch.group(1) ?? '') ?? 2026;
        final month = int.tryParse(dateMatch.group(2) ?? '') ?? 1;
        final day = int.tryParse(dateMatch.group(3) ?? '') ?? 1;
        creationDate = DateTime(year, month, day);
      }

      // Fast regex fallback for page count
      final countMatch = RegExp(r'/Type\s*/Pages[^\n\r]*?/Count\s+(\d+)').firstMatch(combined);
      if (countMatch != null) {
        pageCount = int.tryParse(countMatch.group(1) ?? '0') ?? 0;
      }
    } catch (e) {
      AppLogger.warning('Binary header inspection failed for $filePath: $e', 'PdfStudioService');
    }

    // Precise page count resolution via pdfx if pageCount is still zero
    if (pageCount == 0 && !isEncrypted) {
      try {
        final doc = await pdfx.PdfDocument.openFile(filePath);
        pageCount = doc.pagesCount;
        await doc.close();
      } catch (e) {
        AppLogger.warning('pdfx openFile failed for $filePath: $e', 'PdfStudioService');
      }
    }

    return PdfDocumentInfo(
      filePath: filePath,
      pageCount: pageCount,
      fileSize: fileSize,
      title: title,
      author: author,
      subject: subject,
      creator: creator,
      creationDate: creationDate,
      isEncrypted: isEncrypted,
    );
  }

  @override
  Future<PdfOperationResult> imagesToPdf(
    List<String> imagePaths,
    String outputPath, {
    String? title,
    String? author,
  }) async {
    if (imagePaths.isEmpty) {
      return PdfOperationResult(
        success: false,
        outputPath: outputPath,
        pagesProcessed: 0,
        outputSizeBytes: 0,
        errorMessage: 'No images provided for PDF generation',
      );
    }

    try {
      final doc = pw.Document(
        title: title ?? p.basenameWithoutExtension(outputPath),
        author: author ?? 'FileZen PDF Studio',
      );

      var pagesCount = 0;
      for (final imagePath in imagePaths) {
        final file = File(imagePath);
        if (!await file.exists()) continue;

        final imageBytes = await file.readAsBytes();
        final image = pw.MemoryImage(imageBytes);

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              );
            },
          ),
        );
        pagesCount++;
      }

      if (pagesCount == 0) {
        return PdfOperationResult(
          success: false,
          outputPath: outputPath,
          pagesProcessed: 0,
          outputSizeBytes: 0,
          errorMessage: 'None of the provided image files could be read',
        );
      }

      final pdfBytes = await doc.save();
      final outFile = File(outputPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(pdfBytes, flush: true);

      AppLogger.info('Successfully compiled images to PDF: $outputPath ($pagesCount pages)', 'PdfStudioService');

      return PdfOperationResult(
        success: true,
        outputPath: outputPath,
        pagesProcessed: pagesCount,
        outputSizeBytes: pdfBytes.length,
      );
    } catch (e) {
      AppLogger.error('Failed to compile images to PDF: $e', 'PdfStudioService');
      return PdfOperationResult(
        success: false,
        outputPath: outputPath,
        pagesProcessed: 0,
        outputSizeBytes: 0,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<PdfOperationResult> mergePdfs(List<String> pdfPaths, String outputPath) async {
    if (pdfPaths.length < 2) {
      return PdfOperationResult(
        success: false,
        outputPath: outputPath,
        pagesProcessed: 0,
        outputSizeBytes: 0,
        errorMessage: 'At least 2 PDF documents are required to perform a merge',
      );
    }

    try {
      final mergedDoc = pw.Document(
        title: p.basenameWithoutExtension(outputPath),
        author: 'FileZen PDF Studio',
      );

      var totalPages = 0;

      for (final pdfPath in pdfPaths) {
        final doc = await pdfx.PdfDocument.openFile(pdfPath);
        final pageCount = doc.pagesCount;

        for (var i = 1; i <= pageCount; i++) {
          final page = await doc.getPage(i);
          final pageImage = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: pdfx.PdfPageImageFormat.jpeg,
          );
          await page.close();

          if (pageImage != null) {
            final img = pw.MemoryImage(pageImage.bytes);
            mergedDoc.addPage(
              pw.Page(
                pageFormat: PdfPageFormat(page.width, page.height),
                margin: pw.EdgeInsets.zero,
                build: (pw.Context context) {
                  return pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(img, fit: pw.BoxFit.fill),
                  );
                },
              ),
            );
            totalPages++;
          }
        }

        await doc.close();
      }

      final bytes = await mergedDoc.save();
      final outFile = File(outputPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(bytes, flush: true);

      AppLogger.info('Successfully merged ${pdfPaths.length} PDFs into $outputPath ($totalPages pages)', 'PdfStudioService');

      return PdfOperationResult(
        success: true,
        outputPath: outputPath,
        pagesProcessed: totalPages,
        outputSizeBytes: bytes.length,
      );
    } catch (e) {
      AppLogger.error('Failed to merge PDFs: $e', 'PdfStudioService');
      return PdfOperationResult(
        success: false,
        outputPath: outputPath,
        pagesProcessed: 0,
        outputSizeBytes: 0,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<PdfOperationResult> extractPages(
    String sourcePdfPath,
    List<int> pageNumbers,
    String outputPath,
  ) async {
    if (pageNumbers.isEmpty) {
      return PdfOperationResult(
        success: false,
        outputPath: outputPath,
        pagesProcessed: 0,
        outputSizeBytes: 0,
        errorMessage: 'No page numbers provided for extraction',
      );
    }

    try {
      final sourceDoc = await pdfx.PdfDocument.openFile(sourcePdfPath);
      final totalAvailable = sourceDoc.pagesCount;

      final extractedDoc = pw.Document(
        title: p.basenameWithoutExtension(outputPath),
        author: 'FileZen PDF Studio',
      );

      var extractedCount = 0;
      for (final pageNum in pageNumbers) {
        if (pageNum < 1 || pageNum > totalAvailable) continue;

        final page = await sourceDoc.getPage(pageNum);
        final pageImage = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: pdfx.PdfPageImageFormat.jpeg,
        );
        await page.close();

        if (pageImage != null) {
          final img = pw.MemoryImage(pageImage.bytes);
          extractedDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(page.width, page.height),
              margin: pw.EdgeInsets.zero,
              build: (pw.Context context) {
                return pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Image(img, fit: pw.BoxFit.fill),
                );
              },
            ),
          );
          extractedCount++;
        }
      }

      await sourceDoc.close();

      if (extractedCount == 0) {
        return PdfOperationResult(
          success: false,
          outputPath: outputPath,
          pagesProcessed: 0,
          outputSizeBytes: 0,
          errorMessage: 'No valid pages could be extracted from the specified range',
        );
      }

      final bytes = await extractedDoc.save();
      final outFile = File(outputPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(bytes, flush: true);

      AppLogger.info('Successfully extracted $extractedCount pages to $outputPath', 'PdfStudioService');

      return PdfOperationResult(
        success: true,
        outputPath: outputPath,
        pagesProcessed: extractedCount,
        outputSizeBytes: bytes.length,
      );
    } catch (e) {
      AppLogger.error('Failed to extract PDF pages: $e', 'PdfStudioService');
      return PdfOperationResult(
        success: false,
        outputPath: outputPath,
        pagesProcessed: 0,
        outputSizeBytes: 0,
        errorMessage: e.toString(),
      );
    }
  }
}
