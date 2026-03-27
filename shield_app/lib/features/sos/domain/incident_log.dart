class IncidentLog {
  const IncidentLog({
    this.id,
    required this.mode,
    required this.summary,
    required this.locationText,
    required this.createdAt,
  });

  final int? id;
  final String mode;
  final String summary;
  final String? locationText;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'mode': mode,
      'summary': summary,
      'location_text': locationText,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory IncidentLog.fromMap(Map<String, Object?> map) {
    return IncidentLog(
      id: map['id'] as int?,
      mode: map['mode'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      locationText: map['location_text'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
