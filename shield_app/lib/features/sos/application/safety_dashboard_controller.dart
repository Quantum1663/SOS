import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/location_permission.dart';
import '../../../services/call_service.dart';
import '../../../services/location_service.dart';
import '../../../services/shortcut_service.dart';
import '../../../services/sms_service.dart';
import '../data/safety_repository.dart';
import '../domain/incident_log.dart';
import '../domain/journey_plan.dart';
import '../domain/safety_settings.dart';
import '../domain/trusted_contact.dart';
import 'safety_dashboard_state.dart';

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  return SafetyRepository();
});

final safetyDashboardProvider = StateNotifierProvider<
    SafetyDashboardController, AsyncValue<SafetyDashboardState>>((ref) {
  final repository = ref.watch(safetyRepositoryProvider);
  return SafetyDashboardController(repository)..load();
});

class SafetyDashboardController
    extends StateNotifier<AsyncValue<SafetyDashboardState>> {
  SafetyDashboardController(this._repository)
      : super(AsyncValue.data(SafetyDashboardState.initial()));

  final SafetyRepository _repository;
  Timer? _checkInTimer;

  SafetyDashboardState get _current =>
      state.value ?? SafetyDashboardState.initial();

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final contacts = await _repository.getContacts();
      final incidents = await _repository.getIncidents();
      final settings = await _repository.getSettings();
      final checkInDeadline = await _repository.getActiveCheckInDeadline();
      final activeJourney = await _repository.getActiveJourney();
      state = AsyncValue.data(
        SafetyDashboardState(
          contacts: contacts,
          incidents: incidents,
          settings: settings,
          activeMode:
              checkInDeadline == null ? SafetyMode.idle : SafetyMode.checkIn,
          isPerformingAction: false,
          statusMessage: contacts.isEmpty
              ? 'Add trusted contacts before relying on discreet alerts.'
              : checkInDeadline == null
                  ? 'Safety center ready.'
                  : 'Get Home Safe is active.',
          checkInDeadline: checkInDeadline,
          activeJourney: activeJourney,
        ),
      );
      await syncCheckInState();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> saveContact({
    int? id,
    required String name,
    required String phone,
    required String relationship,
    required int priority,
    required bool prefersCall,
  }) async {
    if (name.trim().isEmpty ||
        phone.trim().isEmpty ||
        relationship.trim().isEmpty) {
      _setState(
        _current.copyWith(
          statusMessage: 'Name, phone, and relationship are all required.',
        ),
      );
      return;
    }

    final contact = TrustedContact(
      id: id,
      name: name.trim(),
      phone: phone.trim(),
      relationship: relationship.trim(),
      priority: priority,
      prefersCall: prefersCall,
    );

    final saved = await _repository.saveContact(contact);
    final contacts = [..._current.contacts];
    final index = contacts.indexWhere((item) => item.id == saved.id);
    if (index >= 0) {
      contacts[index] = saved;
    } else {
      contacts.add(saved);
    }
    contacts.sort((a, b) => a.priority.compareTo(b.priority));

    _setState(
      _current.copyWith(
        contacts: contacts,
        statusMessage: 'Trusted contact saved.',
      ),
    );
  }

  Future<void> removeContact(int id) async {
    await _repository.deleteContact(id);
    final contacts = _current.contacts.where((item) => item.id != id).toList();
    _setState(
      _current.copyWith(
        contacts: contacts,
        statusMessage: 'Trusted contact removed.',
      ),
    );
  }

  Future<void> updateSettings(SafetySettings settings) async {
    await _repository.saveSettings(settings);
    _setState(
      _current.copyWith(
        settings: settings,
        statusMessage: 'Safety preferences updated.',
      ),
    );
  }

  Future<void> clearIncidentHistory() async {
    await _repository.clearIncidentHistory();
    _setState(
      _current.copyWith(
        incidents: const [],
        statusMessage: 'Incident history cleared from this device.',
      ),
    );
  }

  Future<void> deleteAllSafetyData() async {
    _checkInTimer?.cancel();
    await ShortcutService.cancelCheckInAlarm();
    await _repository.deleteAllSafetyData();
    _setState(
      SafetyDashboardState.initial().copyWith(
        statusMessage: 'All local safety data was deleted from this device.',
      ),
    );
  }

  Future<void> triggerSilentSos() async {
    if (!SmsService.supportsSilentSend) {
      _setState(
        _current.copyWith(
          statusMessage:
              'Alert Family needs Android SMS access on this build. Use the call actions instead.',
        ),
      );
      return;
    }

    await _triggerEmergency(
      mode: SafetyMode.silent,
      summary: 'Alert Family sent to your trusted circle.',
      messagePrefix: 'SILENT SOS',
      shouldCallEmergency: false,
    );
  }

  Future<void> triggerFullPanic() async {
    await _triggerEmergency(
      mode: SafetyMode.fullPanic,
      summary: 'Full panic activated with emergency escalation.',
      messagePrefix: 'FULL PANIC ALERT',
      shouldCallEmergency: true,
    );
  }

  Future<void> callEmergencyNumber() async {
    final number = _current.settings.primaryEmergencyNumber;
    await _withAction(
      activeMode: SafetyMode.fullPanic,
      statusMessage: 'Calling $number...',
      action: () async {
        await CallService.callEmergency(number);
        await _recordIncident(
          mode: 'Emergency Call',
          summary: 'Placed call to $number.',
        );
        _setState(
          _current.copyWith(
            activeMode: SafetyMode.idle,
            statusMessage: 'Emergency call placed to $number.',
          ),
        );
      },
    );
  }

  Future<void> callWomenHelpline() async {
    final number = _current.settings.womenHelplineNumber;
    await _withAction(
      activeMode: SafetyMode.silent,
      statusMessage: 'Calling women helpline...',
      action: () async {
        await CallService.callEmergency(number);
        await _recordIncident(
          mode: 'Women Helpline',
          summary: 'Placed call to $number.',
        );
        _setState(
          _current.copyWith(
            activeMode: SafetyMode.idle,
            statusMessage: 'Women helpline call started.',
          ),
        );
      },
    );
  }

  void startCheckIn([int? minutes, JourneyPlan? journey]) {
    unawaited(_startCheckIn(minutes, journey));
  }

  Future<void> _startCheckIn([int? minutes, JourneyPlan? journey]) async {
    if (_current.contacts.isEmpty) {
      _setState(
        _current.copyWith(
          statusMessage:
              'Add a trusted contact before using Get Home Safe.',
        ),
      );
      return;
    }

    final durationMinutes = minutes ?? _current.settings.checkInMinutes;
    final deadline = DateTime.now().add(Duration(minutes: durationMinutes));
    final resolvedJourney = journey?.copyWith(expectedArrival: deadline);
    await _repository.saveActiveCheckInDeadline(deadline);
    await _repository.saveActiveJourney(resolvedJourney);
    _scheduleCheckInTimer(deadline);
    await ShortcutService.scheduleCheckInAlarm(deadline);

    _setState(
      _current.copyWith(
        activeMode: SafetyMode.checkIn,
        checkInDeadline: deadline,
        activeJourney: resolvedJourney,
        statusMessage: _buildCheckInStatus(
          deadline: deadline,
          durationMinutes: durationMinutes,
          journey: resolvedJourney,
        ),
      ),
    );
  }

  void cancelCheckIn() {
    unawaited(_cancelCheckIn());
  }

  Future<void> markArrivedSafely() async {
    final journey = _current.activeJourney;
    final destination = journey?.destination.trim();
    await _recordIncident(
      mode: 'Reached Safely',
      summary: destination == null || destination.isEmpty
          ? 'Reached safely and closed Get Home Safe.'
          : 'Reached safely at $destination and closed Get Home Safe.',
      locationText: journey?.vehicleDetails.trim().isEmpty ?? true
          ? null
          : 'Ride details: ${journey!.vehicleDetails.trim()}',
    );
    await _cancelCheckIn(statusMessage: 'Marked safe. Get Home Safe closed.');
  }

  Future<void> extendCheckIn(int extraMinutes) async {
    final currentDeadline = _current.checkInDeadline;
    if (currentDeadline == null) {
      return;
    }

    final journey = _current.activeJourney;
    final newDeadline = currentDeadline.add(Duration(minutes: extraMinutes));
    final updatedJourney = journey?.copyWith(expectedArrival: newDeadline);

    await _repository.saveActiveCheckInDeadline(newDeadline);
    await _repository.saveActiveJourney(updatedJourney);
    _scheduleCheckInTimer(newDeadline);
    await ShortcutService.scheduleCheckInAlarm(newDeadline);

    _setState(
      _current.copyWith(
        activeMode: SafetyMode.checkIn,
        checkInDeadline: newDeadline,
        activeJourney: updatedJourney,
        statusMessage: 'Running late. Get Home Safe extended by $extraMinutes minutes.',
      ),
    );
  }

  Future<void> updateJourneyProgress({
    required String mode,
    String? destination,
    String? vehicleDetails,
    String? routeNote,
    required String summary,
  }) async {
    final currentDeadline = _current.checkInDeadline;
    final currentJourney = _current.activeJourney;
    if (currentDeadline == null || currentJourney == null) {
      return;
    }

    final updatedJourney = currentJourney.copyWith(
      destination: destination ?? currentJourney.destination,
      vehicleDetails: vehicleDetails ?? currentJourney.vehicleDetails,
      routeNote: routeNote ?? currentJourney.routeNote,
      expectedArrival: currentDeadline,
    );

    await _repository.saveActiveJourney(updatedJourney);
    await _recordIncident(
      mode: mode,
      summary: summary,
      locationText: _buildJourneyLogContext(updatedJourney),
    );

    _setState(
      _current.copyWith(
        activeJourney: updatedJourney,
        statusMessage: summary,
      ),
    );
  }

  Future<void> notifyTrustedCircleOfJourneyUpdate({
    required String updateLabel,
    String? note,
  }) async {
    if (!SmsService.supportsSilentSend) {
      _setState(
        _current.copyWith(
          statusMessage:
              'Trusted-circle updates need Android SMS access on this build.',
        ),
      );
      return;
    }

    final contacts = _current.contacts;
    if (contacts.isEmpty) {
      _setState(
        _current.copyWith(
          statusMessage:
              'Add a trusted contact before sending journey updates.',
        ),
      );
      return;
    }

    _setState(
      _current.copyWith(
        activeMode: SafetyMode.checkIn,
        isPerformingAction: true,
        statusMessage: 'Sending journey update to your trusted circle...',
      ),
    );

    try {
      final message = await _buildJourneyUpdateMessage(
        updateLabel: updateLabel,
        note: note,
      );
      final deliveryFailures = <String>[];
      var deliveredContactCount = 0;

      for (final contact in contacts) {
        try {
          await SmsService.sendSOS(number: contact.phone, message: message);
          deliveredContactCount++;
        } catch (_) {
          deliveryFailures.add(contact.name);
        }
      }

      if (deliveredContactCount == 0) {
        throw Exception('No trusted-circle updates could be delivered.');
      }

      final summary = note == null || note.trim().isEmpty
          ? '$updateLabel sent to your trusted circle.'
          : '$updateLabel sent to your trusted circle. ${note.trim()}';
      await _recordIncident(
        mode: 'Trusted Circle Update',
        summary: summary,
        locationText: _buildJourneyLogContext(_current.activeJourney),
      );

      final deliverySummary = _buildDeliverySummary(
        deliveredContactCount: deliveredContactCount,
        emergencyCallPlaced: false,
        emergencyCallFailed: false,
        deliveryFailures: deliveryFailures,
      );
      _setState(
        _current.copyWith(
          activeMode: SafetyMode.checkIn,
          isPerformingAction: false,
          statusMessage: [summary, deliverySummary]
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .join(' '),
        ),
      );
    } catch (_) {
      _setState(
        _current.copyWith(
          activeMode: SafetyMode.checkIn,
          isPerformingAction: false,
          statusMessage:
              'Journey update could not be sent. Check SMS permission and try again.',
        ),
      );
    }
  }

  Future<void> _cancelCheckIn({
    String statusMessage = 'Get Home Safe cancelled.',
  }) async {
    _checkInTimer?.cancel();
    await _repository.saveActiveCheckInDeadline(null);
    await _repository.saveActiveJourney(null);
    await ShortcutService.cancelCheckInAlarm();
    _setState(
      _current.copyWith(
        activeMode: SafetyMode.idle,
        clearCheckIn: true,
        clearActiveJourney: true,
        statusMessage: statusMessage,
      ),
    );
  }

  Future<void> syncCheckInState() async {
    final deadline = await _repository.getActiveCheckInDeadline();
    final activeJourney = await _repository.getActiveJourney();
    if (deadline == null) {
      _checkInTimer?.cancel();
      if (_current.checkInDeadline != null ||
          _current.activeMode == SafetyMode.checkIn) {
        _setState(
          _current.copyWith(
            activeMode: SafetyMode.idle,
            clearCheckIn: true,
            clearActiveJourney: true,
          ),
        );
      }
      return;
    }

    if (!deadline.isAfter(DateTime.now())) {
      await handleExpiredCheckIn();
      return;
    }

    _scheduleCheckInTimer(deadline);
    await ShortcutService.scheduleCheckInAlarm(deadline);
    if (_current.checkInDeadline != deadline ||
        _current.activeMode != SafetyMode.checkIn) {
      _setState(
        _current.copyWith(
          activeMode: SafetyMode.checkIn,
          checkInDeadline: deadline,
          activeJourney: activeJourney,
          statusMessage: _buildActiveCheckInStatus(
            deadline: deadline,
            journey: activeJourney,
          ),
        ),
      );
    }
  }

  Future<void> handleExpiredCheckIn() async {
    final deadline = await _repository.getActiveCheckInDeadline();
    if (deadline == null) {
      return;
    }

    if (deadline.isAfter(DateTime.now())) {
      _scheduleCheckInTimer(deadline);
      return;
    }

    _checkInTimer?.cancel();
    await _repository.saveActiveCheckInDeadline(null);
    await _repository.saveActiveJourney(null);
    await ShortcutService.cancelCheckInAlarm();

    if (_current.contacts.isEmpty) {
      _setState(
        _current.copyWith(
          activeMode: SafetyMode.idle,
          clearCheckIn: true,
          clearActiveJourney: true,
          statusMessage:
              'Get Home Safe expired, but no trusted contact is configured for escalation.',
        ),
      );
      return;
    }

    await _triggerEmergency(
      mode: SafetyMode.checkIn,
      summary: 'Get Home Safe expired and escalated to Alert Family.',
      messagePrefix: 'MISSED CHECK-IN ALERT',
      shouldCallEmergency: false,
    );
  }

  Future<void> _triggerEmergency({
    required SafetyMode mode,
    required String summary,
    required String messagePrefix,
    required bool shouldCallEmergency,
  }) async {
    await _withAction(
      activeMode: mode,
      statusMessage: 'Preparing safety response...',
      action: () async {
        if (mode == SafetyMode.checkIn) {
          await _repository.saveActiveCheckInDeadline(null);
          await _repository.saveActiveJourney(null);
          await ShortcutService.cancelCheckInAlarm();
          _checkInTimer?.cancel();
        }
        final locationText = await _resolveLocationText();
        final contacts = _current.contacts;
        if (contacts.isEmpty && !shouldCallEmergency) {
          throw Exception('Trusted contacts are required for this flow.');
        }
        final timestamp = DateTime.now();
        final message = _buildEmergencyMessage(
          prefix: messagePrefix,
          locationText: locationText,
          timestamp: timestamp,
          journey: _current.activeJourney,
        );
        final deliveryFailures = <String>[];
        var deliveredContactCount = 0;
        var emergencyCallPlaced = false;
        var emergencyCallFailed = false;

        for (final contact in contacts) {
          try {
            await SmsService.sendSOS(number: contact.phone, message: message);
            deliveredContactCount++;
          } catch (_) {
            deliveryFailures.add(contact.name);
          }
        }

        if (shouldCallEmergency) {
          try {
            await CallService.callEmergency(_current.settings.primaryEmergencyNumber);
            emergencyCallPlaced = true;
          } catch (_) {
            emergencyCallFailed = true;
          }
        }

        if (deliveredContactCount == 0 && !emergencyCallPlaced) {
          throw Exception('No emergency actions could be completed.');
        }

        await _recordIncident(
          mode: switch (mode) {
            SafetyMode.silent => 'Alert Family',
            SafetyMode.checkIn => 'Get Home Safe',
            SafetyMode.fullPanic => 'Full Panic',
            SafetyMode.idle => 'Safety Event',
          },
          summary: summary,
          locationText: locationText,
        );

        final settings = _current.settings;
        final primaryContact = _findPrimaryContact(contacts);
        final prompt = shouldCallEmergency
            ? settings.autoCallPrimaryContact && primaryContact != null
                ? 'If you can speak safely after 112, call ${primaryContact.name}.'
                : null
            : settings.sendWomenHelplinePrompt
                ? 'You can also call ${settings.womenHelplineNumber} for support.'
                : null;
        final deliverySummary = _buildDeliverySummary(
          deliveredContactCount: deliveredContactCount,
          emergencyCallPlaced: emergencyCallPlaced,
          emergencyCallFailed: emergencyCallFailed,
          deliveryFailures: deliveryFailures,
        );
        _setState(
          _current.copyWith(
            activeMode: SafetyMode.idle,
            clearCheckIn: true,
            clearActiveJourney: true,
            statusMessage: [summary, deliverySummary, prompt]
                .whereType<String>()
                .where((value) => value.trim().isNotEmpty)
                .join(' '),
          ),
        );
      },
    );
  }

  void _scheduleCheckInTimer(DateTime deadline) {
    _checkInTimer?.cancel();
    final duration = deadline.difference(DateTime.now());
    if (duration.isNegative || duration == Duration.zero) {
      unawaited(handleExpiredCheckIn());
      return;
    }

    _checkInTimer = Timer(duration, () {
      unawaited(handleExpiredCheckIn());
    });
  }

  Future<String> _resolveLocationText() async {
    final permissionGranted = await LocationPermission.request();
    if (!permissionGranted) {
      return 'Location permission denied. Last known location unavailable.';
    }

    final position = await LocationService.getCurrentLocation();
    if (position == null) {
      return 'Location unavailable at the moment.';
    }

    return LocationService.formatLocation(position);
  }

  String _buildEmergencyMessage({
    required String prefix,
    required String locationText,
    required DateTime timestamp,
    JourneyPlan? journey,
  }) {
    final localTimestamp =
        '${timestamp.day.toString().padLeft(2, '0')}/'
        '${timestamp.month.toString().padLeft(2, '0')}/'
        '${timestamp.year} '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
    final journeySection = _buildJourneyMessageBlock(journey);
    return '$prefix\n'
        'I may be unsafe and need help.\n'
        'Time: $localTimestamp\n'
        '$journeySection'
        '$locationText\n'
        'What to do now:\n'
        '1. Call me immediately.\n'
        '2. Keep tracking my route and expected arrival.\n'
        '3. If I do not respond, escalate to 112 and contact the rest of my trusted circle.';
  }

  Future<String> _buildJourneyUpdateMessage({
    required String updateLabel,
    String? note,
  }) async {
    final timestamp = DateTime.now();
    final localTimestamp =
        '${timestamp.day.toString().padLeft(2, '0')}/'
        '${timestamp.month.toString().padLeft(2, '0')}/'
        '${timestamp.year} '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
    final locationText = await _resolveLocationText();
    final noteBlock = note == null || note.trim().isEmpty
        ? ''
        : 'Note: ${note.trim()}\n';
    final guidance = _buildJourneyUpdateGuidance(updateLabel);
    return 'TRUSTED CIRCLE UPDATE\n'
        '$updateLabel\n'
        'Time: $localTimestamp\n'
        '${_buildJourneyMessageBlock(_current.activeJourney)}'
        '$noteBlock'
        '$locationText\n'
        '$guidance';
  }

  String _buildJourneyUpdateGuidance(String updateLabel) {
    switch (updateLabel.trim().toLowerCase()) {
      case 'running late':
        return 'What to do now:\n'
            '1. Acknowledge this update so I know you saw it.\n'
            '2. Keep watch on my route and updated arrival time.\n'
            '3. Call me if the delay keeps growing or I stop responding.';
      case 'route changed':
        return 'What to do now:\n'
            '1. Note the changed route and keep tracking my journey.\n'
            '2. Call me if the new route looks unexpected.\n'
            '3. Escalate if I stop responding or the route becomes unsafe.';
      case 'vehicle changed':
        return 'What to do now:\n'
            '1. Save the new vehicle details and keep watch.\n'
            '2. Call me if anything about the new ride feels off.\n'
            '3. Escalate if I stop responding or the trip changes again unexpectedly.';
      case 'check on me':
        return 'What to do now:\n'
            '1. Call me immediately.\n'
            '2. Keep tracking my route and current location.\n'
            '3. If I do not respond, escalate quickly and contact the rest of my trusted circle.';
      default:
        return 'What to do now:\n'
            '1. Acknowledge this update and call me if needed.\n'
            '2. Keep watch on my route and expected arrival.\n'
            '3. Escalate if I stop responding or the situation changes.';
    }
  }

  String _buildJourneyMessageBlock(JourneyPlan? journey) {
    if (journey == null || !journey.hasDetails) {
      return '';
    }

    final lines = <String>[];
    if (journey.destination.trim().isNotEmpty) {
      lines.add('Destination: ${journey.destination.trim()}');
    }
    if (journey.vehicleDetails.trim().isNotEmpty) {
      lines.add('Vehicle: ${journey.vehicleDetails.trim()}');
    }
    if (journey.routeNote.trim().isNotEmpty) {
      lines.add('Route note: ${journey.routeNote.trim()}');
    }
    final eta =
        '${journey.expectedArrival.hour.toString().padLeft(2, '0')}:${journey.expectedArrival.minute.toString().padLeft(2, '0')}';
    lines.add('Expected arrival: $eta');
    return '${lines.join('\n')}\n';
  }

  String? _buildJourneyLogContext(JourneyPlan? journey) {
    if (journey == null || !journey.hasDetails) {
      return null;
    }

    final parts = <String>[];
    if (journey.destination.trim().isNotEmpty) {
      parts.add('Destination: ${journey.destination.trim()}');
    }
    if (journey.vehicleDetails.trim().isNotEmpty) {
      parts.add('Ride details: ${journey.vehicleDetails.trim()}');
    }
    if (journey.routeNote.trim().isNotEmpty) {
      parts.add('Route note: ${journey.routeNote.trim()}');
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  String _buildCheckInStatus({
    required DateTime deadline,
    required int durationMinutes,
    JourneyPlan? journey,
  }) {
    if (journey == null || !journey.hasDetails) {
      return 'Get Home Safe armed for $durationMinutes minutes.';
    }

    final destination = journey.destination.trim().isEmpty
        ? 'your destination'
        : journey.destination.trim();
    return 'Get Home Safe armed for $durationMinutes minutes toward $destination.';
  }

  String _buildActiveCheckInStatus({
    required DateTime deadline,
    JourneyPlan? journey,
  }) {
    final time =
        '${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')}';
    if (journey == null || !journey.hasDetails) {
      return 'Get Home Safe is active until $time.';
    }

    final destination = journey.destination.trim().isEmpty
        ? 'your destination'
        : journey.destination.trim();
    return 'Get Home Safe is active for $destination until $time.';
  }

  String? _buildDeliverySummary({
    required int deliveredContactCount,
    required bool emergencyCallPlaced,
    required bool emergencyCallFailed,
    required List<String> deliveryFailures,
  }) {
    final parts = <String>[];

    if (deliveredContactCount > 0) {
      parts.add(
        deliveredContactCount == 1
            ? '1 trusted contact was alerted.'
            : '$deliveredContactCount trusted contacts were alerted.',
      );
    }

    if (emergencyCallPlaced) {
      parts.add('Emergency call launched.');
    } else if (emergencyCallFailed) {
      parts.add('Emergency call could not be launched.');
    }

    if (deliveryFailures.isNotEmpty) {
      final failedNames = deliveryFailures.take(2).join(', ');
      final suffix = deliveryFailures.length > 2 ? ', and others' : '';
      parts.add('Could not reach $failedNames$suffix.');
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(' ');
  }

  Future<void> _recordIncident({
    required String mode,
    required String summary,
    String? locationText,
  }) async {
    final incident = IncidentLog(
      mode: mode,
      summary: summary,
      locationText: locationText,
      createdAt: DateTime.now(),
    );
    await _repository.saveIncident(incident);
    final incidents = await _repository.getIncidents();
    _setState(_current.copyWith(incidents: incidents));
  }

  TrustedContact? _findPrimaryContact(List<TrustedContact> contacts) {
    for (final contact in contacts) {
      if (contact.prefersCall) {
        return contact;
      }
    }
    return contacts.isNotEmpty ? contacts.first : null;
  }

  Future<void> _withAction({
    required SafetyMode activeMode,
    required String statusMessage,
    required Future<void> Function() action,
  }) async {
    _setState(
      _current.copyWith(
        activeMode: activeMode,
        isPerformingAction: true,
        statusMessage: statusMessage,
      ),
    );

    try {
      await action();
    } catch (_) {
      _setState(
        _current.copyWith(
          activeMode: SafetyMode.idle,
          isPerformingAction: false,
          statusMessage:
              'Safety action could not be completed. Check permissions and try again.',
        ),
      );
      return;
    }

    _setState(
      _current.copyWith(
        activeMode: SafetyMode.idle,
        isPerformingAction: false,
      ),
    );
  }

  void _setState(SafetyDashboardState nextState) {
    state = AsyncValue.data(nextState);
  }

  @override
  void dispose() {
    _checkInTimer?.cancel();
    super.dispose();
  }
}
