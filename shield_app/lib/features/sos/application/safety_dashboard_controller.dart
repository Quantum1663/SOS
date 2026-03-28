import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/location_permission.dart';
import '../../../services/call_service.dart';
import '../../../services/location_service.dart';
import '../../../services/sms_service.dart';
import '../data/safety_repository.dart';
import '../domain/incident_log.dart';
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
      state = AsyncValue.data(
        SafetyDashboardState(
          contacts: contacts,
          incidents: incidents,
          settings: settings,
          activeMode: SafetyMode.idle,
          isPerformingAction: false,
          statusMessage: contacts.isEmpty
              ? 'Add trusted contacts before relying on silent escalation.'
              : 'Safety center ready.',
          checkInDeadline: null,
        ),
      );
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

  Future<void> triggerSilentSos() async {
    if (!SmsService.supportsSilentSend) {
      _setState(
        _current.copyWith(
          statusMessage:
              'Silent SOS needs Android SMS access on this build. Use the call actions instead.',
        ),
      );
      return;
    }

    await _triggerEmergency(
      mode: SafetyMode.silent,
      summary: 'Silent SOS sent to trusted contacts.',
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

  void startCheckIn([int? minutes]) {
    if (_current.contacts.isEmpty) {
      _setState(
        _current.copyWith(
          statusMessage:
              'Add a trusted contact before using the missed check-in flow.',
        ),
      );
      return;
    }

    final durationMinutes = minutes ?? _current.settings.checkInMinutes;
    final deadline = DateTime.now().add(Duration(minutes: durationMinutes));
    _checkInTimer?.cancel();
    _checkInTimer = Timer(Duration(minutes: durationMinutes), () {
      unawaited(
        _triggerEmergency(
          mode: SafetyMode.checkIn,
          summary: 'Check-in expired and escalated to silent SOS.',
          messagePrefix: 'MISSED CHECK-IN ALERT',
          shouldCallEmergency: false,
        ),
      );
    });

    _setState(
      _current.copyWith(
        activeMode: SafetyMode.checkIn,
        checkInDeadline: deadline,
        statusMessage: 'Check-in armed for $durationMinutes minutes.',
      ),
    );
  }

  void cancelCheckIn() {
    _checkInTimer?.cancel();
    _setState(
      _current.copyWith(
        activeMode: SafetyMode.idle,
        clearCheckIn: true,
        statusMessage: 'Check-in cancelled.',
      ),
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
          mode: mode.name,
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
            statusMessage: [summary, deliverySummary, prompt]
                .whereType<String>()
                .where((value) => value.trim().isNotEmpty)
                .join(' '),
          ),
        );
      },
    );
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
  }) {
    final localTimestamp =
        '${timestamp.day.toString().padLeft(2, '0')}/'
        '${timestamp.month.toString().padLeft(2, '0')}/'
        '${timestamp.year} '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
    return '$prefix\n'
        'I may be unsafe and need help.\n'
        'Time: $localTimestamp\n'
        '$locationText\n'
        'Please call me, track my route, and escalate to 112 if I do not respond.';
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
