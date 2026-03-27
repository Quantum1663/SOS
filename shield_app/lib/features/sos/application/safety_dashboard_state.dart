import '../domain/incident_log.dart';
import '../domain/safety_settings.dart';
import '../domain/trusted_contact.dart';

enum SafetyMode {
  idle,
  silent,
  fullPanic,
  checkIn,
}

class SafetyDashboardState {
  const SafetyDashboardState({
    required this.contacts,
    required this.incidents,
    required this.settings,
    required this.activeMode,
    required this.isPerformingAction,
    required this.statusMessage,
    required this.checkInDeadline,
  });

  final List<TrustedContact> contacts;
  final List<IncidentLog> incidents;
  final SafetySettings settings;
  final SafetyMode activeMode;
  final bool isPerformingAction;
  final String? statusMessage;
  final DateTime? checkInDeadline;

  factory SafetyDashboardState.initial() {
    return SafetyDashboardState(
      contacts: const [],
      incidents: const [],
      settings: SafetySettings.defaults(),
      activeMode: SafetyMode.idle,
      isPerformingAction: false,
      statusMessage: null,
      checkInDeadline: null,
    );
  }

  SafetyDashboardState copyWith({
    List<TrustedContact>? contacts,
    List<IncidentLog>? incidents,
    SafetySettings? settings,
    SafetyMode? activeMode,
    bool? isPerformingAction,
    String? statusMessage,
    bool clearStatusMessage = false,
    DateTime? checkInDeadline,
    bool clearCheckIn = false,
  }) {
    return SafetyDashboardState(
      contacts: contacts ?? this.contacts,
      incidents: incidents ?? this.incidents,
      settings: settings ?? this.settings,
      activeMode: activeMode ?? this.activeMode,
      isPerformingAction: isPerformingAction ?? this.isPerformingAction,
      statusMessage:
          clearStatusMessage ? null : statusMessage ?? this.statusMessage,
      checkInDeadline:
          clearCheckIn ? null : checkInDeadline ?? this.checkInDeadline,
    );
  }
}
