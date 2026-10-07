/// Typed domain error hierarchy for FileZen.
///
/// Prevents raw platform/OS exceptions from leaking into the UI.
sealed class AppError {
  final String message;
  final String? technicalDetails;
  final String? recoverySuggestion;

  const AppError({
    required this.message,
    this.technicalDetails,
    this.recoverySuggestion,
  });

  @override
  String toString() => '$runtimeType: $message (${technicalDetails ?? ''})';
}

/// Permission-related failure (e.g. Scoped Storage / MANAGE_EXTERNAL_STORAGE).
class PermissionError extends AppError {
  final String permission;

  const PermissionError({
    required this.permission,
    super.message = 'Storage permission is required to access your files.',
    super.technicalDetails,
    super.recoverySuggestion = 'Please grant permission in App Settings.',
  });
}

/// File or directory not found.
class FileNotFoundError extends AppError {
  final String path;

  const FileNotFoundError({
    required this.path,
    super.message = 'The specified file or folder could not be found.',
    super.technicalDetails,
    super.recoverySuggestion = 'Refresh the directory or check if it was moved.',
  });
}

/// Access denied / permission restriction.
class AccessDeniedError extends AppError {
  final String path;

  const AccessDeniedError({
    required this.path,
    super.message = 'Access to this file or folder is restricted.',
    super.technicalDetails,
    super.recoverySuggestion = 'Check app permissions or Android storage access.',
  });
}

/// Insufficient storage space on device.
class StorageFullError extends AppError {
  final int requiredBytes;

  const StorageFullError({
    required this.requiredBytes,
    super.message = 'Not enough storage space available.',
    super.technicalDetails,
    super.recoverySuggestion = 'Free up space using the Clean tab and try again.',
  });
}

/// File format not recognized or supported.
class UnsupportedFormatError extends AppError {
  final String extension;

  const UnsupportedFormatError({
    required this.extension,
    super.message = 'This file format is not natively supported.',
    super.technicalDetails,
    super.recoverySuggestion = 'Try opening with a third-party application.',
  });
}

/// Long-running operation was cancelled by the user.
class OperationCancelledError extends AppError {
  const OperationCancelledError({
    super.message = 'The operation was cancelled.',
    super.technicalDetails,
    super.recoverySuggestion,
  });
}

/// Network or external connectivity failure.
class NetworkError extends AppError {
  const NetworkError({
    super.message = 'Network connection is currently unavailable.',
    super.technicalDetails,
    super.recoverySuggestion = 'Check your connection. Offline features remain fully operational.',
  });
}

/// External provider (WAPCentral, Cloud) unavailable.
class ProviderUnavailableError extends AppError {
  final String providerName;

  const ProviderUnavailableError({
    required this.providerName,
    super.message = 'The service is temporarily unavailable.',
    super.technicalDetails,
    super.recoverySuggestion = 'Local file management continues unaffected.',
  });
}

/// Local database or indexing failure.
class DatabaseError extends AppError {
  const DatabaseError({
    required super.message,
    super.technicalDetails,
    super.recoverySuggestion = 'Try rescanning the folder or restarting the application.',
  });
}

/// Unhandled or unexpected runtime exception.
class UnknownError extends AppError {
  const UnknownError({
    super.message = 'An unexpected error occurred.',
    super.technicalDetails,
    super.recoverySuggestion = 'Please try again.',
  });
}
