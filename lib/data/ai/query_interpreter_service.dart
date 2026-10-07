import '../../domain/models/ai_models.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/search_result_item.dart';
import '../../domain/repositories/i_query_interpreter_service.dart';
import '../../domain/repositories/i_search_repository.dart';

/// Heuristic and rule-based natural language query interpreter for "Ask Your Files".
/// Runs 100% locally and offline without external network or AI cloud dependencies.
class QueryInterpreterService implements IQueryInterpreterService {
  const QueryInterpreterService({
    required this.searchRepository,
  });

  final ISearchRepository searchRepository;

  static const _stopWords = {
    'find', 'show', 'get', 'list', 'all', 'my', 'the', 'a', 'an', 'in',
    'on', 'of', 'for', 'with', 'containing', 'about', 'from', 'please',
    'search', 'where', 'is', 'are', 'me', 'file', 'files',
  };

  @override
  NaturalQueryIntent interpretQuery(String naturalQuery) {
    final lower = naturalQuery.trim().toLowerCase();
    final tokens = lower.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    FileCategory? targetCategory;
    String? fileExtension;
    int? minSizeBytes;
    int? maxSizeBytes;
    DateTime? startDate;
    DateTime? endDate;
    SpecialQueryIntent specialIntent = SpecialQueryIntent.general;
    final keywords = <String>[];
    String explanation = 'Searching for files matching keywords';

    final now = DateTime.now();

    // 1. Detect Special Intent Patterns
    if (lower.contains('resume') || lower.contains(' cv') || lower == 'cv') {
      specialIntent = SpecialQueryIntent.resume;
      targetCategory = FileCategory.document;
      keywords.addAll(['resume', 'cv']);
      explanation = 'Looking for your latest resume or CV documents';
    } else if (lower.contains('otp') || lower.contains('verification') || (lower.contains('screenshot') && lower.contains('code'))) {
      specialIntent = SpecialQueryIntent.otpScreenshot;
      targetCategory = FileCategory.image;
      keywords.addAll(['screenshot', 'otp', 'verification', 'code']);
      explanation = 'Looking for screenshots containing OTPs or verification codes';
    } else if (lower.contains('receipt') || lower.contains('invoice') || lower.contains('bill')) {
      specialIntent = SpecialQueryIntent.receiptOrInvoice;
      keywords.addAll(['receipt', 'invoice', 'bill', 'payment']);
      explanation = 'Searching for receipts, invoices, and expense documents';
    } else if (lower.contains('large video') ||
        lower.contains('big video') ||
        (lower.contains('video') &&
            (lower.contains('large') ||
                lower.contains('larger') ||
                lower.contains('heavy') ||
                lower.contains('big') ||
                lower.contains('over') ||
                lower.contains('greater')))) {
      specialIntent = SpecialQueryIntent.largeVideos;
      targetCategory = FileCategory.video;
      minSizeBytes = 50 * 1024 * 1024; // 50MB
      keywords.add('video');
      explanation = 'Filtering videos larger than 50 MB';
    } else if (RegExp(r'\b(id|passport|license|aadhaar)\b').hasMatch(lower)) {
      specialIntent = SpecialQueryIntent.idCard;
      keywords.addAll(['id', 'passport', 'license', 'card', 'identity']);
      explanation = 'Looking for identity cards, passports, or license documents';
    } else if (lower.contains('recent doc') || lower.contains('latest doc') || lower.contains('recently modified')) {
      specialIntent = SpecialQueryIntent.recentDocuments;
      targetCategory = FileCategory.document;
      startDate = now.subtract(const Duration(days: 7));
      explanation = 'Finding recently modified documents from the last 7 days';
    }

    // 2. Detect Category Hints (if not already locked by special intent)
    if (targetCategory == null) {
      if (lower.contains('video') || lower.contains('movie') || lower.contains('clip')) {
        targetCategory = FileCategory.video;
      } else if (lower.contains('audio') || lower.contains('song') || lower.contains('music') || lower.contains('sound')) {
        targetCategory = FileCategory.audio;
      } else if (lower.contains('photo') || lower.contains('image') || lower.contains('picture') || lower.contains('screenshot')) {
        targetCategory = FileCategory.image;
      } else if (lower.contains('document') || lower.contains('doc') || lower.contains('sheet') || lower.contains('pdf')) {
        targetCategory = FileCategory.document;
      } else if (lower.contains('archive') || lower.contains('zip') || lower.contains('tar')) {
        targetCategory = FileCategory.archive;
      } else if (lower.contains('code') || lower.contains('script')) {
        targetCategory = FileCategory.document;
      }
    }

    // 3. Detect Extensions
    final extMatch = RegExp(r'\b(pdf|docx?|xlsx?|pptx?|mp4|mkv|mp3|wav|png|jpe?g|csv|zip|dart|py|json)\b').firstMatch(lower);
    if (extMatch != null) {
      fileExtension = extMatch.group(1);
    }

    // 4. Detect Explicit Size Constraints
    final sizeMatch = RegExp(r'(?:over|larger than|greater than|>)\s*(\d+)\s*(gb|mb|kb)', caseSensitive: false).firstMatch(lower);
    if (sizeMatch != null) {
      final amount = int.tryParse(sizeMatch.group(1) ?? '0') ?? 0;
      final unit = (sizeMatch.group(2) ?? '').toLowerCase();
      if (unit == 'gb') minSizeBytes = amount * 1024 * 1024 * 1024;
      if (unit == 'mb') minSizeBytes = amount * 1024 * 1024;
      if (unit == 'kb') minSizeBytes = amount * 1024;
      explanation += ' (min size: ${sizeMatch.group(1)} ${unit.toUpperCase()})';
    }

    // 5. Detect Date Filters
    if (startDate == null) {
      if (lower.contains('today')) {
        startDate = DateTime(now.year, now.month, now.day);
      } else if (lower.contains('yesterday')) {
        startDate = DateTime(now.year, now.month, now.day - 1);
        endDate = DateTime(now.year, now.month, now.day);
      } else if (lower.contains('this week')) {
        startDate = now.subtract(const Duration(days: 7));
      } else if (lower.contains('this month')) {
        startDate = DateTime(now.year, now.month, 1);
      } else if (lower.contains('last month')) {
        startDate = DateTime(now.year, now.month - 1, 1);
        endDate = DateTime(now.year, now.month, 1);
      }
    }

    // 6. Extract meaningful keyword tokens
    if (keywords.isEmpty) {
      for (final t in tokens) {
        if (!_stopWords.contains(t) && t.length > 1) {
          keywords.add(t);
        }
      }
    }

    if (keywords.isEmpty) {
      keywords.add(naturalQuery.trim());
    }

    return NaturalQueryIntent(
      rawQuery: naturalQuery,
      interpretedKeywords: keywords,
      targetCategory: targetCategory,
      startDate: startDate,
      endDate: endDate,
      minSizeBytes: minSizeBytes,
      maxSizeBytes: maxSizeBytes,
      fileExtension: fileExtension,
      specialIntent: specialIntent,
      explanation: explanation,
    );
  }

  @override
  Future<List<SearchResultItem>> executeAskYourFiles(String naturalQuery) async {
    final intent = interpretQuery(naturalQuery);

    final textQuery = intent.interpretedKeywords.isNotEmpty
        ? intent.interpretedKeywords.join(' OR ')
        : '*';

    // Build structured SearchQuery from interpreted intent
    final searchQuery = SearchQuery(
      text: textQuery,
      category: intent.targetCategory,
      minSize: intent.minSizeBytes,
      maxSize: intent.maxSizeBytes,
      extension: intent.fileExtension,
    );

    final searchResult = await searchRepository.search(searchQuery);
    final results = searchResult.when(
      success: (items) => items,
      failure: (_) => <SearchResultItem>[],
    );

    // Intent-specific post-ranking
    final sorted = List<SearchResultItem>.from(results);

    switch (intent.specialIntent) {
      case SpecialQueryIntent.resume:
      case SpecialQueryIntent.recentDocuments:
        // Rank by most recently modified
        sorted.sort((a, b) => b.file.modifiedAt.compareTo(a.file.modifiedAt));
        break;
      case SpecialQueryIntent.largeVideos:
        // Rank by largest size first
        sorted.sort((a, b) => b.file.size.compareTo(a.file.size));
        break;
      case SpecialQueryIntent.otpScreenshot:
      case SpecialQueryIntent.receiptOrInvoice:
      case SpecialQueryIntent.idCard:
      case SpecialQueryIntent.general:
        // Keep default BM25 relevance rank
        break;
    }

    return sorted;
  }
}
