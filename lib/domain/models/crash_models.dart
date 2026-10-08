/// Data model representing a privacy-scrubbed crash or error event.
///
/// Principles:
/// - Strictly sanitizes file paths, OCR content, vault keys, and credentials.
/// - Stores only technical diagnostics required for stability analysis.
class CrashReport {
  final String id;
  final DateTime timestamp;
  final String errorType;
  final String message;
  final String? stackTrace;
  final bool isFatal;
  final Map<String, dynamic> deviceInfo;
  final Map<String, dynamic> customContext;

  const CrashReport({
    required this.id,
    required this.timestamp,
    required this.errorType,
    required this.message,
    this.stackTrace,
    this.isFatal = false,
    this.deviceInfo = const {},
    this.customContext = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'errorType': errorType,
        'message': message,
        'stackTrace': stackTrace,
        'isFatal': isFatal,
        'deviceInfo': deviceInfo,
        'customContext': customContext,
      };

  factory CrashReport.fromJson(Map<String, dynamic> json) {
    return CrashReport(
      id: json['id'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      errorType: json['errorType'] as String? ?? 'UnknownError',
      message: json['message'] as String? ?? '',
      stackTrace: json['stackTrace'] as String?,
      isFatal: json['isFatal'] as bool? ?? false,
      deviceInfo: (json['deviceInfo'] as Map<String, dynamic>?) ?? const {},
      customContext: (json['customContext'] as Map<String, dynamic>?) ?? const {},
    );
  }

  CrashReport copyWith({
    String? id,
    DateTime? timestamp,
    String? errorType,
    String? message,
    String? stackTrace,
    bool? isFatal,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? customContext,
  }) {
    return CrashReport(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      errorType: errorType ?? this.errorType,
      message: message ?? this.message,
      stackTrace: stackTrace ?? this.stackTrace,
      isFatal: isFatal ?? this.isFatal,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      customContext: customContext ?? this.customContext,
    );
  }
}
