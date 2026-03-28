class JourneyPlan {
  const JourneyPlan({
    required this.destination,
    required this.routeNote,
    required this.vehicleDetails,
    required this.startedAt,
    required this.expectedArrival,
  });

  final String destination;
  final String routeNote;
  final String vehicleDetails;
  final DateTime startedAt;
  final DateTime expectedArrival;

  bool get hasDetails =>
      destination.trim().isNotEmpty ||
      routeNote.trim().isNotEmpty ||
      vehicleDetails.trim().isNotEmpty;

  JourneyPlan copyWith({
    String? destination,
    String? routeNote,
    String? vehicleDetails,
    DateTime? startedAt,
    DateTime? expectedArrival,
  }) {
    return JourneyPlan(
      destination: destination ?? this.destination,
      routeNote: routeNote ?? this.routeNote,
      vehicleDetails: vehicleDetails ?? this.vehicleDetails,
      startedAt: startedAt ?? this.startedAt,
      expectedArrival: expectedArrival ?? this.expectedArrival,
    );
  }
}
