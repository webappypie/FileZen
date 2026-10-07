import '../models/ai_models.dart';
import '../models/file_entity.dart';

/// Clean Architecture interface for AI-assisted file rename suggestions and execution.
abstract class IAutoRenameService {
  /// Generates a structured rename suggestion for a single file from local signals.
  Future<AutoRenameSuggestion> generateRenameSuggestion(FileEntity file);

  /// Generates rename suggestions for a batch of files.
  Future<List<AutoRenameSuggestion>> generateBatchRenameSuggestions(List<FileEntity> files);

  /// Applies a rename suggestion to disk atomically.
  Future<bool> applyRename(AutoRenameSuggestion suggestion);

  /// Reverts a previous auto-rename operation safely.
  Future<bool> undoRename(AutoRenameHistoryItem historyItem);

  /// Retrieves recent auto-rename history for undo availability.
  List<AutoRenameHistoryItem> getRenameHistory();
}
