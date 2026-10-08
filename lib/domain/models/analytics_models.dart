/// Privacy-preserving analytics event record.
///
/// Strictly prohibits logging of user file names, contents, OCR text, or credentials.
class AnalyticsEvent {
  final String id;
  final String name;
  final DateTime timestamp;
  final Map<String, dynamic> parameters;

  const AnalyticsEvent({
    required this.id,
    required this.name,
    required this.timestamp,
    this.parameters = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'timestamp': timestamp.toIso8601String(),
        'parameters': parameters,
      };

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) {
    return AnalyticsEvent(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'unknown',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      parameters: (json['parameters'] as Map<String, dynamic>?) ?? const {},
    );
  }
}
