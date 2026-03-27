class TrustedContact {
  const TrustedContact({
    this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.priority,
    required this.prefersCall,
  });

  final int? id;
  final String name;
  final String phone;
  final String relationship;
  final int priority;
  final bool prefersCall;

  TrustedContact copyWith({
    int? id,
    String? name,
    String? phone,
    String? relationship,
    int? priority,
    bool? prefersCall,
  }) {
    return TrustedContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      relationship: relationship ?? this.relationship,
      priority: priority ?? this.priority,
      prefersCall: prefersCall ?? this.prefersCall,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'relationship': relationship,
      'priority': priority,
      'prefers_call': prefersCall ? 1 : 0,
    };
  }

  factory TrustedContact.fromMap(Map<String, Object?> map) {
    return TrustedContact(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      relationship: map['relationship'] as String? ?? '',
      priority: map['priority'] as int? ?? 1,
      prefersCall: (map['prefers_call'] as int? ?? 0) == 1,
    );
  }
}
