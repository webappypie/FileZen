import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/services/document_service.dart';
import '../../../../data/services/pdf_studio_service.dart';
import '../../../../domain/models/document_models.dart';
import '../../../../domain/repositories/i_document_service.dart';
import '../../../../domain/repositories/i_pdf_studio_service.dart';

/// Provider for DocumentService instance.
final documentServiceProvider = Provider<IDocumentService>((ref) {
  return const DocumentService();
});

/// Provider for PdfStudioService instance.
final pdfStudioServiceProvider = Provider<IPdfStudioService>((ref) {
  return const PdfStudioService();
});

/// Family provider loading raw or preview text of a document file.
final documentTextProvider = FutureProvider.family<String, String>((ref, filePath) async {
  final service = ref.watch(documentServiceProvider);
  return service.readDocumentText(filePath);
});

/// Family provider analyzing document word/line/character counts and type.
final documentMetadataProvider = FutureProvider.family<DocumentMetadata, String>((ref, filePath) async {
  final service = ref.watch(documentServiceProvider);
  return service.analyzeDocument(filePath);
});

/// Family provider parsing CSV rows and headers.
final csvTableDataProvider = FutureProvider.family<List<List<dynamic>>, String>((ref, filePath) async {
  final service = ref.watch(documentServiceProvider);
  return service.parseCsv(filePath);
});

/// Family provider extracting PDF metadata and page count.
final pdfInfoProvider = FutureProvider.family<PdfDocumentInfo, String>((ref, filePath) async {
  final service = ref.watch(pdfStudioServiceProvider);
  return service.getPdfInfo(filePath);
});
