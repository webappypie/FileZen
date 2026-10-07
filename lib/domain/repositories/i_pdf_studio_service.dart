import '../models/document_models.dart';

/// Clean Architecture interface for PDF metadata inspection and PDF manipulation (Merge, Images to PDF, Extract).
abstract class IPdfStudioService {
  /// Extract metadata and page count from a PDF file.
  Future<PdfDocumentInfo> getPdfInfo(String filePath);

  /// Convert one or multiple image files into a single structured PDF document.
  Future<PdfOperationResult> imagesToPdf(
    List<String> imagePaths,
    String outputPath, {
    String? title,
    String? author,
  });

  /// Merge multiple PDF documents into a single consolidated PDF document.
  Future<PdfOperationResult> mergePdfs(List<String> pdfPaths, String outputPath);

  /// Extract specified page numbers (1-indexed) from a source PDF and save as a new PDF.
  Future<PdfOperationResult> extractPages(
    String sourcePdfPath,
    List<int> pageNumbers,
    String outputPath,
  );
}
