import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../domain/models/ai_models.dart';
import '../../domain/repositories/i_ocr_service.dart';

/// Real on-device OCR service powered by Google ML Kit Text Recognition.
///
/// Runs fully on-device with the bundled Latin-script model (no network, no
/// upload). Only the Latin recognizer is ever created, which is why the optional
/// Chinese/Japanese/Korean/Devanagari ML Kit classes can be left out of the APK
/// (see the `-dontwarn` rules in android/app/proguard-rules.pro).
///
/// Where ML Kit is unavailable (desktop/host builds) the service reports no text
/// rather than guessing from the file's bytes or name.
class OcrService implements IOcrService {
  final TextRecognizer? _customRecognizer;

  const OcrService({TextRecognizer? recognizer}) : _customRecognizer = recognizer;

  bool get _mlKitUsable => Platform.isAndroid || Platform.isIOS || _customRecognizer != null;

  TextRecognizer _createRecognizer() {
    return _customRecognizer ?? TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  Future<bool> isOcrAvailable() async => _mlKitUsable;

  OcrExtractionResult _empty(String imagePath) => OcrExtractionResult(
        filePath: imagePath,
        extractedText: '',
        confidence: 0.0,
        timestamp: DateTime.now(),
      );

  @override
  Future<OcrExtractionResult> extractTextFromImage(String imagePath) async {
    if (!_mlKitUsable) return _empty(imagePath);

    final file = File(imagePath);
    if (!await file.exists() || await file.length() == 0) return _empty(imagePath);

    TextRecognizer? recognizer;
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      recognizer = _createRecognizer();
      final RecognizedText recognizedText = await recognizer.processImage(inputImage);

      final lines = <String>[];
      final confidences = <double>[];
      final languages = <String, int>{};
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final trimmed = line.text.trim();
          if (trimmed.isEmpty) continue;
          lines.add(trimmed);
          final c = line.confidence;
          if (c != null) confidences.add(c);
          for (final lang in line.recognizedLanguages) {
            if (lang.isNotEmpty && lang != 'und') languages.update(lang, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      }

      final fullText = recognizedText.text.trim();
      final confidence = fullText.isEmpty
          ? 0.0
          : (confidences.isEmpty
              ? 0.0
              : confidences.reduce((a, b) => a + b) / confidences.length);
      final language = languages.isEmpty
          ? 'und'
          : (languages.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

      AppLogger.info(
        'ML Kit OCR processed ${p.basename(imagePath)}: ${lines.length} lines detected',
        'OcrService',
      );

      return OcrExtractionResult(
        filePath: imagePath,
        extractedText: fullText,
        detectedLanguage: language,
        confidence: confidence,
        timestamp: DateTime.now(),
        lines: lines,
      );
    } catch (e) {
      AppLogger.warning('ML Kit OCR extraction error for $imagePath: $e', 'OcrService');
      return _empty(imagePath);
    } finally {
      if (_customRecognizer == null && recognizer != null) {
        await recognizer.close();
      }
    }
  }
}
