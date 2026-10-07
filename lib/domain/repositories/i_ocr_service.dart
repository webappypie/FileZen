import '../models/ai_models.dart';

/// Clean Architecture interface for on-device OCR text extraction.
abstract class IOcrService {
  /// Extracts text and line segments from a local image file.
  Future<OcrExtractionResult> extractTextFromImage(String imagePath);

  /// Checks if OCR capabilities are currently available on this platform/device.
  Future<bool> isOcrAvailable();
}
