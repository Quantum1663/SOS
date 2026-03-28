import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/safety_dashboard_controller.dart';
import '../application/safety_dashboard_state.dart';
import '../domain/journey_plan.dart';
import '../domain/trusted_contact.dart';
import '../../../services/app_lock_service.dart';
import '../../../services/shortcut_service.dart';

class SosHomeScreen extends ConsumerStatefulWidget {
  const SosHomeScreen({super.key});

  @override
  ConsumerState<SosHomeScreen> createState() => _SosHomeScreenState();
}

class _SosHomeScreenState extends ConsumerState<SosHomeScreen>
    with WidgetsBindingObserver {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int _disguiseTapCount = 0;
  Timer? _disguiseTapTimer;
  StreamSubscription<ShortcutAction>? _shortcutSubscription;
  bool _hasAppLockPin = false;
  bool _isUnlocked = true;
  bool _lockStateReady = false;
  bool? _lastKnownAppLockEnabled;
  bool? _lastKnownStealthNotificationsEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
    _shortcutSubscription = ShortcutService.actions.listen(_handleShortcutAction);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _configurePersistentShortcuts();
      await _syncAppLockState(false);
      final initialAction = await ShortcutService.getInitialAction();
      if (initialAction != null && mounted) {
        await _handleShortcutAction(initialAction);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _disguiseTapTimer?.cancel();
    _shortcutSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(safetyDashboardProvider.notifier).syncCheckInState());
      final dashboardState = ref.read(safetyDashboardProvider).value;
      if (dashboardState?.settings.appLockEnabled == true && _hasAppLockPin) {
        setState(() {
          _isUnlocked = false;
        });
      }
    }
  }

  Future<void> _syncAppLockState(bool shouldLock) async {
    final hasPin = await AppLockService.hasPin();
    if (!mounted) {
      return;
    }

    setState(() {
      _hasAppLockPin = hasPin;
      _lockStateReady = true;
      if (!hasPin) {
        _isUnlocked = true;
      } else if (shouldLock) {
        _isUnlocked = false;
      }
    });
  }

  Future<void> _enableAppLock(SafetyDashboardState state) async {
    final pin = await _showSetPinSheet(context);
    if (pin == null || pin.length < 4) {
      return;
    }

    await AppLockService.savePin(pin);
    await ref.read(safetyDashboardProvider.notifier).updateSettings(
          state.settings.copyWith(appLockEnabled: true),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _hasAppLockPin = true;
      _isUnlocked = true;
      _lockStateReady = true;
    });
  }

  Future<void> _disableAppLock(SafetyDashboardState state) async {
    final confirmed = await _showDisableLockSheet(context);
    if (confirmed != true) {
      return;
    }

    await AppLockService.clearPin();
    await ref.read(safetyDashboardProvider.notifier).updateSettings(
          state.settings.copyWith(appLockEnabled: false),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _hasAppLockPin = false;
      _isUnlocked = true;
      _lockStateReady = true;
    });
  }

  Future<void> _clearIncidentHistory() async {
    final confirmed = await _showDangerConfirmSheet(
      context,
      title: 'Clear incident history?',
      body:
          'This removes the local incident timeline from this device. Contacts, settings, and active safety flows will remain.',
      confirmLabel: 'Clear History',
    );
    if (confirmed != true) {
      return;
    }

    await ref.read(safetyDashboardProvider.notifier).clearIncidentHistory();
  }

  Future<void> _deleteAllSafetyData() async {
    final confirmed = await _showDangerConfirmSheet(
      context,
      title: 'Delete all safety data?',
      body:
          'This clears contacts, incidents, journeys, settings, and the local app-lock PIN from this device.',
      confirmLabel: 'Delete Everything',
    );
    if (confirmed != true) {
      return;
    }

    await AppLockService.clearPin();
    await ref.read(safetyDashboardProvider.notifier).deleteAllSafetyData();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasAppLockPin = false;
      _isUnlocked = true;
      _lockStateReady = true;
    });
  }

  Future<void> _configurePersistentShortcuts() async {
    if (!ShortcutService.supportsPersistentShortcuts) {
      return;
    }

    try {
      await ShortcutService.enablePersistentShortcuts();
    } catch (_) {
      // Leave the in-app shortcut system available even if the device-level
      // quick actions cannot be pinned right now.
    }
  }

  Future<void> _handleShortcutAction(ShortcutAction action) async {
    final controller = ref.read(safetyDashboardProvider.notifier);
    switch (action) {
      case ShortcutAction.quickOpen:
        if (!mounted) {
          return;
        }
        final state = ref.read(safetyDashboardProvider).value;
        if (state != null) {
          _showEmergencySheet(context, ref, state);
        }
        break;
      case ShortcutAction.fullPanic:
        await controller.triggerFullPanic();
        break;
      case ShortcutAction.silentSos:
        await controller.triggerSilentSos();
        break;
      case ShortcutAction.checkIn:
        controller.startCheckIn(15);
        break;
      case ShortcutAction.checkInExpired:
        await controller.handleExpiredCheckIn();
        break;
    }
  }

  void _registerDisguiseTap(SafetyDashboardState state) {
    if (!state.settings.disguiseModeEnabled) {
      return;
    }

    _disguiseTapCount++;
    _disguiseTapTimer?.cancel();
    _disguiseTapTimer = Timer(const Duration(milliseconds: 700), () {
      _disguiseTapCount = 0;
    });

    if (_disguiseTapCount >= 3) {
      _disguiseTapCount = 0;
      _disguiseTapTimer?.cancel();
      _showShortcutCountdownSheet(
        context,
        title: 'Hidden SOS armed',
        subtitle: 'Release pressure on the screen and stay calm. SHIELD will escalate in 5 seconds unless you cancel.',
        accent: const Color(0xFFFFB703),
        onConfirmed: () async {
          await ref.read(safetyDashboardProvider.notifier).triggerSilentSos();
        },
      );
    }
  }

  void _armFullPanic(SafetyDashboardState state) {
    _showShortcutCountdownSheet(
      context,
      title: 'Full panic armed',
      subtitle:
          'SHIELD will call 112 and alert your trusted circle in 5 seconds unless you cancel.',
      accent: const Color(0xFFE54B4B),
      onConfirmed: () async {
        await ref.read(safetyDashboardProvider.notifier).triggerFullPanic();
      },
    );
  }

  void _armSilentSos(SafetyDashboardState state) {
    _showShortcutCountdownSheet(
      context,
      title: 'Alert Family armed',
      subtitle:
          'A discreet alert will go out in 5 seconds unless you cancel now.',
      accent: const Color(0xFFFFB703),
      onConfirmed: () async {
        await ref.read(safetyDashboardProvider.notifier).triggerSilentSos();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(safetyDashboardProvider);

    return dashboardState.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF08090D),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: const Color(0xFF08090D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'The safety center could not load.\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
      data: (state) {
        final disguiseActive = state.settings.disguiseModeEnabled;
        if (_lastKnownAppLockEnabled != state.settings.appLockEnabled) {
          _lastKnownAppLockEnabled = state.settings.appLockEnabled;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_syncAppLockState(state.settings.appLockEnabled));
          });
        }
        if (_lastKnownStealthNotificationsEnabled !=
            state.settings.stealthNotificationsEnabled) {
          _lastKnownStealthNotificationsEnabled =
              state.settings.stealthNotificationsEnabled;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(
              ShortcutService.setStealthMode(
                state.settings.stealthNotificationsEnabled,
              ),
            );
          });
        }

        if (!_lockStateReady) {
          return const Scaffold(
            backgroundColor: Color(0xFF08090D),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state.settings.appLockEnabled && _hasAppLockPin && !_isUnlocked) {
          return _AppLockScreen(
            disguiseModeEnabled: state.settings.disguiseModeEnabled,
            onUnlock: (pin) async {
              final isValid = await AppLockService.verifyPin(pin);
              if (isValid && mounted) {
                setState(() {
                  _isUnlocked = true;
                });
              }
              return isValid;
            },
          );
        }

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: const Color(0xFF08090D),
            appBar: AppBar(
              backgroundColor: const Color(0xFF11131A),
              title: GestureDetector(
                onTap: () => _registerDisguiseTap(state),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(disguiseActive ? 'Daily Notes' : 'SHIELD'),
                    Text(
                      disguiseActive
                          ? 'Private workspace'
                          : 'India-first SOS safety center',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              bottom: TabBar(
                tabs: [
                  Tab(text: disguiseActive ? 'Home' : 'Safety'),
                  Tab(text: disguiseActive ? 'People' : 'Contacts'),
                  Tab(text: disguiseActive ? 'Logs' : 'History'),
                ],
              ),
            ),
            floatingActionButton: _QuickActionsFab(
              state: state,
              disguiseModeEnabled: disguiseActive,
              onHoldToArm: () => _armFullPanic(state),
            ),
            body: TabBarView(
              children: [
                _SafetyTab(
                  state: state,
                  now: _now,
                  appLockEnabled: state.settings.appLockEnabled && _hasAppLockPin,
                  stealthNotificationsEnabled:
                      state.settings.stealthNotificationsEnabled,
                  disguiseModeEnabled: disguiseActive,
                  onHoldToArm: () => _armFullPanic(state),
                  onSilentHold: () => _armSilentSos(state),
                  onPinQuickAccess: _configurePersistentShortcuts,
                  onToggleStealthNotifications: (value) async {
                    await ref.read(safetyDashboardProvider.notifier).updateSettings(
                          state.settings.copyWith(
                            stealthNotificationsEnabled: value,
                          ),
                        );
                  },
                  onEnableAppLock: () => _enableAppLock(state),
                  onDisableAppLock: () => _disableAppLock(state),
                  onClearHistory: _clearIncidentHistory,
                  onDeleteAllData: _deleteAllSafetyData,
                  onSecretTap: () => _registerDisguiseTap(state),
                  onSecretLongPress: () => _armSilentSos(state),
                ),
                _ContactsTab(state: state),
                _HistoryTab(state: state),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickActionsFab extends ConsumerWidget {
  const _QuickActionsFab({
    required this.state,
    required this.disguiseModeEnabled,
    required this.onHoldToArm,
  });

  final SafetyDashboardState state;
  final bool disguiseModeEnabled;
  final VoidCallback onHoldToArm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onLongPress: state.isPerformingAction ? null : onHoldToArm,
      child: FloatingActionButton.extended(
        onPressed: () => _showEmergencySheet(context, ref, state),
        backgroundColor: const Color(0xFFE54B4B),
        foregroundColor: Colors.white,
        icon: Icon(disguiseModeEnabled ? Icons.note_add_outlined : Icons.bolt),
        label: Text(disguiseModeEnabled ? 'Quick Note' : 'Quick SOS'),
      ),
    );
  }
}

class _SafetyTab extends ConsumerWidget {
  const _SafetyTab({
    required this.state,
    required this.now,
    required this.appLockEnabled,
    required this.stealthNotificationsEnabled,
    required this.disguiseModeEnabled,
    required this.onHoldToArm,
    required this.onSilentHold,
    required this.onPinQuickAccess,
    required this.onToggleStealthNotifications,
    required this.onEnableAppLock,
    required this.onDisableAppLock,
    required this.onClearHistory,
    required this.onDeleteAllData,
    required this.onSecretTap,
    required this.onSecretLongPress,
  });

  final SafetyDashboardState state;
  final DateTime now;
  final bool appLockEnabled;
  final bool stealthNotificationsEnabled;
  final bool disguiseModeEnabled;
  final VoidCallback onHoldToArm;
  final VoidCallback onSilentHold;
  final Future<void> Function() onPinQuickAccess;
  final Future<void> Function(bool value) onToggleStealthNotifications;
  final Future<void> Function() onEnableAppLock;
  final Future<void> Function() onDisableAppLock;
  final Future<void> Function() onClearHistory;
  final Future<void> Function() onDeleteAllData;
  final VoidCallback onSecretTap;
  final VoidCallback onSecretLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(safetyDashboardProvider.notifier);
    final deadline = state.checkInDeadline;
    final remaining = deadline == null ? null : deadline.difference(now);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _StatusCard(state: state, remaining: remaining),
        const SizedBox(height: 16),
        _SafetyButtonCard(
          state: state,
          disguiseModeEnabled: disguiseModeEnabled,
          onTapPrimary: () {
            if (state.activeMode == SafetyMode.checkIn) {
              controller.cancelCheckIn();
              return;
            }
            if (state.isPerformingAction) {
              _showEmergencyProgressSheet(context, state);
              return;
            }
            _showEmergencySheet(context, ref, state);
          },
          onDoubleTapPrimary: state.isPerformingAction || state.contacts.isEmpty
              ? null
              : onSilentHold,
          onLongPressPrimary: state.isPerformingAction ? null : onHoldToArm,
          onPinQuickAccess: onPinQuickAccess,
        ),
        const SizedBox(height: 16),
        _EmergencyProgressCard(state: state),
        const SizedBox(height: 16),
        if (state.activeJourney != null) ...[
          _JourneyStatusCard(state: state),
          const SizedBox(height: 16),
        ],
        _DeviceAccessCard(
          state: state,
          onPinQuickAccess: onPinQuickAccess,
        ),
        const SizedBox(height: 16),
        _QuickLaunchCard(state: state),
        const SizedBox(height: 16),
        _ActionCard(
          title: disguiseModeEnabled ? 'Priority contact' : 'Immediate danger',
          subtitle: disguiseModeEnabled
              ? 'Keeps the fastest call path close at hand when you need to reach someone quickly.'
              : 'Calls 112, sends alerts to trusted contacts, and logs the incident.',
          accent: const Color(0xFFE54B4B),
          children: [
            FilledButton(
              onPressed:
                  state.isPerformingAction ? null : controller.triggerFullPanic,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE54B4B),
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(
                disguiseModeEnabled ? 'Start Priority Call' : 'Trigger Full Panic',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: state.isPerformingAction
                  ? null
                  : controller.callEmergencyNumber,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text('Call ${state.settings.primaryEmergencyNumber}'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ActionCard(
          title: disguiseModeEnabled ? 'Quiet update' : 'Silent danger',
          subtitle: disguiseModeEnabled
              ? 'Sends a discreet update with location to the people you trust.'
              : 'Sends a discreet SOS with location to trusted contacts.',
          accent: const Color(0xFFFFB703),
          children: [
            FilledButton(
              onPressed:
                  state.isPerformingAction ? null : controller.triggerSilentSos,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFB703),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(
                disguiseModeEnabled ? 'Send Quiet Update' : 'Alert Family',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ContactMessageCompareCard(state: state),
        const SizedBox(height: 16),
        _ActionCard(
          title: disguiseModeEnabled ? 'Arrival timer' : 'Get home safe',
          subtitle:
              disguiseModeEnabled
                  ? 'Use a simple timer for arrivals, or plan the full trip so route details stay attached if you go quiet.'
                  : 'Use a simple timer for quick exits, or plan the full journey so destination and ride details stay attached to your missed-arrival escalation.',
          accent: const Color(0xFF4CC9F0),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final minutes in const [15, 30, 60])
                  ChoiceChip(
                    label: Text('$minutes min'),
                    selected: deadline != null &&
                        state.settings.checkInMinutes == minutes,
                    onSelected: state.isPerformingAction
                        ? null
                        : (_) async {
                            await controller.updateSettings(
                              state.settings.copyWith(checkInMinutes: minutes),
                            );
                            controller.startCheckIn(minutes);
                          },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        deadline == null ? null : controller.cancelCheckIn,
                    child: Text(
                      disguiseModeEnabled
                          ? 'Stop Arrival Timer'
                          : 'Cancel Get Home Safe',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: state.isPerformingAction
                        ? null
                        : controller.callWomenHelpline,
                    child: Text('Call ${state.settings.womenHelplineNumber}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: state.isPerformingAction
                    ? null
                    : () => _showJourneyPlannerSheet(context, state),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CC9F0),
                  foregroundColor: const Color(0xFF06131A),
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.route_outlined),
                label: Text(
                  state.activeJourney == null
                      ? disguiseModeEnabled
                          ? 'Plan Trip + Start Timer'
                          : 'Plan Journey + Start Get Home Safe'
                      : disguiseModeEnabled
                          ? 'Update Trip Plan'
                          : 'Update Journey Plan',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ReadinessCard(state: state),
        const SizedBox(height: 16),
        _PrivacyStealthCard(
          state: state,
          appLockEnabled: appLockEnabled,
          stealthNotificationsEnabled: stealthNotificationsEnabled,
          disguiseModeEnabled: state.settings.disguiseModeEnabled,
          onToggleStealthNotifications: onToggleStealthNotifications,
          onEnableAppLock: onEnableAppLock,
          onDisableAppLock: onDisableAppLock,
          onClearHistory: onClearHistory,
          onDeleteAllData: onDeleteAllData,
        ),
        const SizedBox(height: 16),
        _ActionCard(
          title: state.settings.disguiseModeEnabled
              ? 'Workspace snapshot'
              : 'Preparedness snapshot',
          subtitle:
              state.settings.disguiseModeEnabled
                  ? 'Review local setup, quick-access layers, and workspace tools.'
                  : 'A strong SOS setup needs trusted contacts, discreet messaging, and clear helpline paths.',
          accent: const Color(0xFF8ECAE6),
          children: [
            _InfoLine(
              label: 'Trusted contacts',
              value: '${state.contacts.length} ready',
            ),
            _InfoLine(
              label: 'Disguise mode',
              value: state.settings.disguiseModeEnabled ? 'On' : 'Off',
            ),
            _InfoLine(
              label: 'Follow-up contact reminder',
              value: state.settings.autoCallPrimaryContact ? 'Enabled' : 'Off',
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                state.settings.disguiseModeEnabled
                    ? 'Keep workspace disguise available'
                    : 'Enable camouflage feature',
              ),
              subtitle: Text(
                state.settings.disguiseModeEnabled
                    ? 'Keeps the disguised workspace available without replacing the main dashboard.'
                    : 'Keeps the disguise screen available without replacing the main dashboard.',
              ),
              value: state.settings.disguiseModeEnabled,
              onChanged: (value) {
                controller.updateSettings(
                  state.settings.copyWith(disguiseModeEnabled: value),
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: state.settings.disguiseModeEnabled
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _DisguiseWorkspace(
                            state: state,
                            now: now,
                            onSecretTap: onSecretTap,
                            onSecretLongPress: onSecretLongPress,
                          ),
                        ),
                      );
                    }
                  : null,
              child: Text(
                state.settings.disguiseModeEnabled
                    ? 'Open Workspace Screen'
                    : 'Open Camouflage Screen',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Highlight a follow-up contact after 112'),
              subtitle: const Text(
                'Reminds you which trusted person to call once the emergency call is over.',
              ),
              value: state.settings.autoCallPrimaryContact,
              onChanged: (value) {
                controller.updateSettings(
                  state.settings.copyWith(autoCallPrimaryContact: value),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _DisguiseWorkspace extends StatelessWidget {
  const _DisguiseWorkspace({
    required this.state,
    required this.now,
    required this.onSecretTap,
    required this.onSecretLongPress,
  });

  final SafetyDashboardState state;
  final DateTime now;
  final VoidCallback onSecretTap;
  final VoidCallback onSecretLongPress;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F0E8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F0E8),
        foregroundColor: const Color(0xFF2F3E46),
        elevation: 0,
        title: GestureDetector(
          onTap: onSecretTap,
          onLongPress: onSecretLongPress,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily Notes'),
              Text(
                'Personal workspace',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: GestureDetector(
        onLongPress: onSecretLongPress,
        child: FloatingActionButton.extended(
          onPressed: () {},
          backgroundColor: const Color(0xFF52796F),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('New Note'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today',
                  style: TextStyle(
                    color: Color(0xFF2F3E46),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Capture errands, reminders, and quick thoughts in one calm space.',
                  style: TextStyle(
                    color: Color(0xFF52796F),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DisguiseNoteCard(
            title: 'Groceries',
            subtitle: dateLabel,
            body:
                'Milk, fruits, electrolytes, sanitary pads, charger cable, and hostel snacks.',
          ),
          const _DisguiseNoteCard(
            title: 'Commute reminders',
            subtitle: 'Metro and cab',
            body:
                'Share ETA before leaving. Save vehicle details. Keep battery saver on after 8 PM.',
          ),
          const _DisguiseNoteCard(
            title: 'Weekly planning',
            subtitle: 'Study + work',
            body:
                'Finish project notes, call home, review route options, and check in after late travel.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFDDE5D2),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              state.checkInDeadline == null
                  ? 'Pinned: hydration, transport, and schedule notes.'
                  : 'Pinned reminder: next schedule check at ${_formatTime(state.checkInDeadline!)}.',
              style: const TextStyle(
                color: Color(0xFF344E41),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _DisguiseNoteCard extends StatelessWidget {
  const _DisguiseNoteCard({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String title;
  final String subtitle;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF2F3E46),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF52796F)),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: const TextStyle(
                color: Color(0xFF354F52),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickLaunchCard extends StatelessWidget {
  const _QuickLaunchCard({required this.state});

  final SafetyDashboardState state;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final controller = ref.read(safetyDashboardProvider.notifier);
        return _ActionCard(
          title: 'Quick launch',
          subtitle:
              'Fastest paths for the moments when there is no time to navigate.',
          accent: const Color(0xFF80ED99),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickActionChip(
                  label: '112',
                  icon: Icons.call,
                  onTap: state.isPerformingAction
                      ? null
                      : controller.callEmergencyNumber,
                ),
                _QuickActionChip(
                  label: '181',
                  icon: Icons.support_agent,
                  onTap: state.isPerformingAction
                      ? null
                      : controller.callWomenHelpline,
                ),
                _QuickActionChip(
                  label: 'Alert',
                  icon: Icons.sms_outlined,
                  onTap:
                      state.isPerformingAction ? null : controller.triggerSilentSos,
                ),
                _QuickActionChip(
                  label: 'Panic',
                  icon: Icons.warning_amber_rounded,
                  onTap:
                      state.isPerformingAction ? null : controller.triggerFullPanic,
                ),
                _QuickActionChip(
                  label: 'Home Safe',
                  icon: Icons.timer_outlined,
                  onTap: state.isPerformingAction
                      ? null
                      : () async {
                          await controller.updateSettings(
                            state.settings.copyWith(checkInMinutes: 15),
                          );
                          controller.startCheckIn(15);
                        },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: const Color(0xFF182028),
      labelStyle: const TextStyle(color: Colors.white),
      side: const BorderSide(color: Colors.white12),
    );
  }
}

class _SafetyButtonCard extends StatelessWidget {
  const _SafetyButtonCard({
    required this.state,
    required this.disguiseModeEnabled,
    required this.onTapPrimary,
    required this.onDoubleTapPrimary,
    required this.onLongPressPrimary,
    required this.onPinQuickAccess,
  });

  final SafetyDashboardState state;
  final bool disguiseModeEnabled;
  final VoidCallback onTapPrimary;
  final VoidCallback? onDoubleTapPrimary;
  final VoidCallback? onLongPressPrimary;
  final Future<void> Function() onPinQuickAccess;

  @override
  Widget build(BuildContext context) {
    final buttonTitle = switch (state.activeMode) {
      SafetyMode.idle => disguiseModeEnabled ? 'Quick Tools' : 'Safety Button',
      SafetyMode.silent =>
        disguiseModeEnabled ? 'Quiet Update Running' : 'Alert Family Running',
      SafetyMode.fullPanic =>
        disguiseModeEnabled ? 'Priority Call Running' : 'Full Panic Running',
      SafetyMode.checkIn => disguiseModeEnabled ? 'Reached' : 'I\'m Safe',
    };
    final buttonSubtitle = switch (state.activeMode) {
      SafetyMode.idle => disguiseModeEnabled
          ? 'Tap for tools, double-tap for a quiet update, or hold for the fastest call path.'
          : 'Tap for Safety Hub, double-tap for Alert Family, or hold for Full Panic.',
      SafetyMode.silent => disguiseModeEnabled
          ? 'Tap to view progress. Double-tap is disabled while the update is already running.'
          : 'Tap to view emergency progress. Double-tap is disabled while SHIELD is already acting.',
      SafetyMode.fullPanic => disguiseModeEnabled
          ? 'Tap to view progress. Hold is disabled while the call path is already running.'
          : 'Tap to view emergency progress. Hold is disabled while SHIELD is already acting.',
      SafetyMode.checkIn => disguiseModeEnabled
          ? 'Tap once to mark arrival and stop the timer. Hold to escalate instead.'
          : 'Tap once to mark yourself safe and stop the active Get Home Safe timer. Hold to escalate instead.',
    };
    final accent = switch (state.activeMode) {
      SafetyMode.idle =>
        disguiseModeEnabled ? const Color(0xFF52796F) : const Color(0xFFE54B4B),
      SafetyMode.silent => const Color(0xFFFFB703),
      SafetyMode.fullPanic => const Color(0xFFE54B4B),
      SafetyMode.checkIn => const Color(0xFF4CC9F0),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: disguiseModeEnabled
              ? const [Color(0xFF20323A), Color(0xFF12141C)]
              : const [Color(0xFF3B0D11), Color(0xFF12141C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: disguiseModeEnabled
              ? const Color(0x3352796F)
              : const Color(0x33E54B4B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            disguiseModeEnabled ? 'Quick tools' : 'Safety button',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            buttonSubtitle,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (ShortcutService.supportsPersistentShortcuts) ...[
            OutlinedButton.icon(
              onPressed: onPinQuickAccess,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(
                disguiseModeEnabled
                    ? 'Pin Quick Tools'
                    : 'Pin Notification Shortcuts',
              ),
            ),
            const SizedBox(height: 12),
          ],
          GestureDetector(
            onTap: onTapPrimary,
            onDoubleTap: onDoubleTapPrimary,
            onLongPress: onLongPressPrimary,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  colors: [
                    accent.withOpacity(0.92),
                    disguiseModeEnabled
                        ? const Color(0xFF2F5D50)
                        : const Color(0xFF721C24),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    state.activeMode == SafetyMode.checkIn
                        ? Icons.verified_user
                        : Icons.shield,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    buttonTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.activeMode == SafetyMode.checkIn
                        ? disguiseModeEnabled
                            ? 'Tap now if you have arrived.'
                            : 'Tap now if you have reached safely.'
                        : disguiseModeEnabled
                            ? 'Designed for quick one-handed access.'
                            : 'Designed for one-handed use under pressure.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _GestureHintChip(
                label: 'Tap',
                detail: state.activeMode == SafetyMode.checkIn
                    ? 'Mark safe'
                    : state.isPerformingAction
                        ? 'See progress'
                        : 'Open actions',
              ),
              _GestureHintChip(
                label: 'Double tap',
                detail: state.contacts.isEmpty ? 'Needs contact' : 'Alert Family',
                enabled: state.contacts.isNotEmpty && !state.isPerformingAction,
              ),
              _GestureHintChip(
                label: 'Hold',
                detail: state.isPerformingAction ? 'Busy' : 'Full Panic',
                enabled: !state.isPerformingAction,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GestureHintChip extends StatelessWidget {
  const _GestureHintChip({
    required this.label,
    required this.detail,
    this.enabled = true,
  });

  final String label;
  final String detail;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFF181B22) : const Color(0xFF12151B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: enabled ? Colors.white70 : Colors.white38,
            height: 1.3,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white54,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: detail),
          ],
        ),
      ),
    );
  }
}

class _EmergencyProgressCard extends StatelessWidget {
  const _EmergencyProgressCard({required this.state});

  final SafetyDashboardState state;

  @override
  Widget build(BuildContext context) {
    final progress = _buildEmergencyProgress(state);
    final disguiseModeEnabled = state.settings.disguiseModeEnabled;
    final isEmergencyActive = state.activeMode == SafetyMode.fullPanic ||
        state.activeMode == SafetyMode.silent;
    final title = switch (state.activeMode) {
      SafetyMode.fullPanic =>
        disguiseModeEnabled ? 'Priority call progress' : 'Emergency progress',
      SafetyMode.silent => disguiseModeEnabled
          ? 'Quiet update progress'
          : 'Silent response progress',
      SafetyMode.checkIn =>
        disguiseModeEnabled ? 'Arrival timer status' : 'Get Home Safe status',
      SafetyMode.idle =>
        disguiseModeEnabled ? 'Review and testing' : 'Recovery and testing',
    };
    final body = switch (state.activeMode) {
      SafetyMode.fullPanic => disguiseModeEnabled
          ? 'The fastest call path is active right now, along with contact alerts and follow-up guidance.'
          : 'SHIELD is handling the loudest path right now: emergency call, trusted-circle alerts, and follow-up guidance.',
      SafetyMode.silent => disguiseModeEnabled
          ? 'The quiet update path is active right now, along with location capture and delivery guidance.'
          : 'SHIELD is handling the discreet path right now: location capture, message delivery, and fallback support guidance.',
      SafetyMode.checkIn => state.activeJourney != null
          ? disguiseModeEnabled
              ? 'Your trip plan is active. Tap the quick tools surface when you arrive, or let the app escalate with your trip details if you go quiet.'
              : 'Your journey plan is active. Tap the Safety Button when you reach safely, or let SHIELD escalate with your trip details if you go silent.'
          : disguiseModeEnabled
              ? 'You have an arrival timer running. Tap the quick tools surface when you arrive, or hold it if the situation changes.'
              : 'You have a safety timer running. Tap the Safety Button when you reach safely, or hold it if the situation changes.',
      SafetyMode.idle => disguiseModeEnabled
          ? 'Use the countdown to avoid accidental triggers, and review the local log if you need to look back at what happened.'
          : 'Use the Safety Button countdown to avoid accidental triggers, and use the incident timeline if you need to review what happened after a false alarm.',
    };

    return _ActionCard(
      title: title,
      subtitle: body,
      accent: isEmergencyActive
          ? const Color(0xFFE54B4B)
          : state.activeMode == SafetyMode.checkIn
              ? const Color(0xFF4CC9F0)
              : const Color(0xFF80ED99),
      children: [
        for (final step in progress.steps) ...[
          _ProgressStepTile(step: step),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF181B22),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            progress.recoveryGuidance,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _showRecoverySheet(context, state),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('False Alarm / I\'m Safe Now'),
        ),
      ],
    );
  }
}

class _ContactMessageCompareCard extends StatefulWidget {
  const _ContactMessageCompareCard({required this.state});

  final SafetyDashboardState state;

  @override
  State<_ContactMessageCompareCard> createState() =>
      _ContactMessageCompareCardState();
}

class _ContactMessageCompareCardState extends State<_ContactMessageCompareCard> {
  bool _showJourneyContext = true;

  @override
  Widget build(BuildContext context) {
    final liveJourney = widget.state.activeJourney;
    final journey = _showJourneyContext
        ? liveJourney ??
            JourneyPlan(
              destination: 'Hostel Gate 2',
              routeNote: 'Returning from metro via the main road',
              vehicleDetails: 'Cab KA03AB1234',
              startedAt: DateTime.now(),
              expectedArrival: DateTime.now().add(const Duration(minutes: 25)),
            )
        : null;
    final destination = journey?.destination.trim();
    final vehicle = journey?.vehicleDetails.trim();
    final route = journey?.routeNote.trim();

    return _ActionCard(
      title: 'What Contacts Will See',
      subtitle:
          'Rehearse the two main trusted-circle paths here: Alert Family for discreet escalation, and Full Panic for the fastest response.',
      accent: const Color(0xFFCDB4DB),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ChoiceChip(
              label: const Text('With active journey'),
              selected: _showJourneyContext,
              onSelected: (selected) {
                setState(() {
                  _showJourneyContext = selected;
                });
              },
            ),
            ChoiceChip(
              label: const Text('Without active journey'),
              selected: !_showJourneyContext,
              onSelected: (selected) {
                if (!selected) {
                  return;
                }
                setState(() {
                  _showJourneyContext = false;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MessagePreviewPanel(
          title: 'Alert Family',
          accent: const Color(0xFFFFB703),
          intro:
              'Preview tone: discreet but urgent. Contacts are told to call, track, and escalate if you stop responding.',
          headline: 'SILENT SOS\nI may be unsafe and need help.',
          destination: destination,
          vehicle: vehicle,
          route: route,
          footer:
              'Contacts will also receive your latest location and these instructions:\n1. Call immediately\n2. Track route and ETA\n3. Escalate if there is no response',
        ),
        const SizedBox(height: 12),
        _MessagePreviewPanel(
          title: 'Full Panic',
          accent: const Color(0xFFE54B4B),
          intro:
              'Preview tone: loudest path. SHIELD will launch ${widget.state.settings.primaryEmergencyNumber}, alert your trusted circle, and tell them to escalate fast if you stop responding.',
          headline: 'FULL PANIC ALERT\nI may be unsafe and need help.',
          destination: destination,
          vehicle: vehicle,
          route: route,
          footer:
              'Contacts will also receive your latest location and these instructions:\n1. Call immediately\n2. Track route and ETA\n3. Escalate to ${widget.state.settings.primaryEmergencyNumber} if there is no response',
        ),
      ],
    );
  }
}

class _MessagePreviewPanel extends StatelessWidget {
  const _MessagePreviewPanel({
    required this.title,
    required this.accent,
    required this.intro,
    required this.headline,
    required this.footer,
    this.destination,
    this.vehicle,
    this.route,
  });

  final String title;
  final Color accent;
  final String intro;
  final String headline;
  final String footer;
  final String? destination;
  final String? vehicle;
  final String? route;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            intro,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 10),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              height: 1.35,
            ),
          ),
          if (destination != null && destination!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Destination: $destination',
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ],
          if (vehicle != null && vehicle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Vehicle: $vehicle',
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ],
          if (route != null && route!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Route note: $route',
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            footer,
            style: const TextStyle(color: Colors.white60, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DeviceAccessCard extends StatelessWidget {
  const _DeviceAccessCard({
    required this.state,
    required this.onPinQuickAccess,
  });

  final SafetyDashboardState state;
  final Future<void> Function() onPinQuickAccess;

  @override
  Widget build(BuildContext context) {
    final androidEnabled = ShortcutService.supportsPersistentShortcuts;
    final disguiseModeEnabled = state.settings.disguiseModeEnabled;

    return _ActionCard(
      title: disguiseModeEnabled ? 'Quick access' : 'Device access',
      subtitle:
          disguiseModeEnabled
              ? 'Keep this workspace reachable from outside the app through Android quick-access surfaces.'
              : 'Phase 2 makes SHIELD reachable from outside the app through Android-native entry points.',
      accent: const Color(0xFF80ED99),
      children: [
        _ProgressLine(
          label: 'Persistent notification',
          value: androidEnabled ? 'Available' : 'Android only',
        ),
        _ProgressLine(
          label: 'Home-screen widget',
          value: androidEnabled ? 'Add from Widgets' : 'Android only',
        ),
        _ProgressLine(
          label: 'Quick Settings tile',
          value: androidEnabled ? 'Add from Quick Settings' : 'Android only',
        ),
        _ProgressLine(
          label: 'App-icon shortcuts',
          value: androidEnabled ? 'Press and hold app icon' : 'Android only',
        ),
        const SizedBox(height: 12),
        Text(
          androidEnabled
              ? disguiseModeEnabled
                  ? 'Recommended setup: pin the notification, add the widget, place the Quick Settings tile near the top row, and memorize the long-press app-icon shortcuts.'
                  : 'Recommended setup: pin the notification, add the SHIELD widget, place the Quick Settings tile near the top row, and memorize the long-press app-icon shortcuts.'
              : disguiseModeEnabled
                  ? 'These quick-access entry points are currently implemented for Android builds. The in-app tools surface remains the main path on other platforms.'
                  : 'These device-level entry points are currently implemented for Android builds. The in-app Safety Button remains the main path on other platforms.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (androidEnabled)
              OutlinedButton.icon(
                onPressed: () => _showAndroidSetupGuide(context),
                icon: const Icon(Icons.tips_and_updates_outlined),
                label: const Text('Android Setup Guide'),
              ),
            if (androidEnabled)
              FilledButton.icon(
                onPressed: onPinQuickAccess,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Pin Notification'),
              ),
            OutlinedButton.icon(
              onPressed: () => _showShortcutTestLab(context, state),
              icon: const Icon(Icons.science_outlined),
              label: const Text('Shortcut Test Lab'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressStepTile extends StatelessWidget {
  const _ProgressStepTile({required this.step});

  final _EmergencyProgressStep step;

  @override
  Widget build(BuildContext context) {
    final color = switch (step.status) {
      _ProgressStatus.complete => const Color(0xFF7AE582),
      _ProgressStatus.active => const Color(0xFFFFB703),
      _ProgressStatus.pending => const Color(0xFF5C677D),
      _ProgressStatus.attention => const Color(0xFFE54B4B),
    };
    final icon = switch (step.status) {
      _ProgressStatus.complete => Icons.check_circle,
      _ProgressStatus.active => Icons.timelapse,
      _ProgressStatus.pending => Icons.radio_button_unchecked,
      _ProgressStatus.attention => Icons.error_outline,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.detail,
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    this.allowWrap = false,
  });

  final String label;
  final String value;
  final bool allowWrap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: allowWrap
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.state});

  final SafetyDashboardState state;

  @override
  Widget build(BuildContext context) {
    final report = _buildReadinessReport(state);
    final color = switch (report.level) {
      _ReadinessLevel.ready => const Color(0xFF7AE582),
      _ReadinessLevel.partial => const Color(0xFFFFB703),
      _ReadinessLevel.notReady => const Color(0xFFE54B4B),
    };
    final label = switch (report.level) {
      _ReadinessLevel.ready => 'Ready to respond',
      _ReadinessLevel.partial => 'Partially ready',
      _ReadinessLevel.notReady => 'Needs setup now',
    };

    return _ActionCard(
      title: 'Readiness layer',
      subtitle:
          'A trustworthy SOS app should show whether your emergency stack is actually usable right now.',
      accent: color,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF181B22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.18),
                child: Icon(Icons.shield_outlined, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.summary,
                      style: const TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final item in report.items) ...[
          _ReadinessItemTile(item: item),
          const SizedBox(height: 10),
        ],
        const Text(
          'India-focused setup: keep one family member, one nearby responder, and one hostel, PG, campus, or workplace backup in your circle.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
      ],
    );
  }
}

class _ReadinessItemTile extends StatelessWidget {
  const _ReadinessItemTile({required this.item});

  final _ReadinessItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.ready ? const Color(0xFF7AE582) : const Color(0xFFFFB703);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181B22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              item.ready ? Icons.check_circle : Icons.radio_button_unchecked,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.detail,
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyStealthCard extends StatelessWidget {
  const _PrivacyStealthCard({
    required this.state,
    required this.appLockEnabled,
    required this.stealthNotificationsEnabled,
    required this.disguiseModeEnabled,
    required this.onToggleStealthNotifications,
    required this.onEnableAppLock,
    required this.onDisableAppLock,
    required this.onClearHistory,
    required this.onDeleteAllData,
  });

  final SafetyDashboardState state;
  final bool appLockEnabled;
  final bool stealthNotificationsEnabled;
  final bool disguiseModeEnabled;
  final Future<void> Function(bool value) onToggleStealthNotifications;
  final Future<void> Function() onEnableAppLock;
  final Future<void> Function() onDisableAppLock;
  final Future<void> Function() onClearHistory;
  final Future<void> Function() onDeleteAllData;

  @override
  Widget build(BuildContext context) {
    return _ActionCard(
      title: disguiseModeEnabled ? 'Workspace Controls' : 'Privacy & Stealth',
      subtitle:
          disguiseModeEnabled
              ? 'Control local access, softer notification wording, and data cleanup for this workspace.'
              : 'Control how much SHIELD stores locally, whether it opens behind a PIN, and how quickly you can wipe sensitive data from this device.',
      accent: const Color(0xFFCDB4DB),
      children: [
        _InfoLine(
          label: 'App lock',
          value: appLockEnabled ? 'PIN enabled' : 'Off',
        ),
        _InfoLine(
          label: 'Incident history',
          value: state.incidents.isEmpty ? 'Empty' : '${state.incidents.length} local entries',
        ),
        _InfoLine(
          label: 'Stealth mode',
          value: state.settings.disguiseModeEnabled ? 'Camouflage ready' : 'Off',
        ),
        _InfoLine(
          label: 'Stealth notifications',
          value: stealthNotificationsEnabled ? 'Safer wording on' : 'Off',
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            disguiseModeEnabled
                ? 'Require PIN on workspace open'
                : 'Require PIN on app open',
          ),
          subtitle: Text(
            disguiseModeEnabled
                ? 'Locks this workspace behind a local PIN when you reopen it.'
                : 'Locks SHIELD behind a local PIN when you reopen the app.',
          ),
          value: appLockEnabled,
          onChanged: (_) {
            if (appLockEnabled) {
              unawaited(onDisableAppLock());
            } else {
              unawaited(onEnableAppLock());
            }
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            disguiseModeEnabled
                ? 'Use softer notification wording'
                : 'Use safer notification wording',
          ),
          subtitle: Text(
            disguiseModeEnabled
                ? 'Makes Android quick-access surfaces look more generic when possible.'
                : 'Makes Android quick-access surfaces look more generic when possible.',
          ),
          value: stealthNotificationsEnabled,
          onChanged: (value) {
            unawaited(onToggleStealthNotifications(value));
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                unawaited(onClearHistory());
              },
              icon: const Icon(Icons.history_toggle_off_outlined),
              label: Text(
                disguiseModeEnabled
                    ? 'Clear Local Log'
                    : 'Clear Incident History',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                unawaited(onDeleteAllData());
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE54B4B),
              ),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(
                disguiseModeEnabled
                    ? 'Delete Workspace Data'
                    : 'Delete All Safety Data',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _JourneyStatusCard extends ConsumerWidget {
  const _JourneyStatusCard({required this.state});

  final SafetyDashboardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journey = state.activeJourney;
    if (journey == null) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(safetyDashboardProvider.notifier);

    final eta =
        '${journey.expectedArrival.hour.toString().padLeft(2, '0')}:${journey.expectedArrival.minute.toString().padLeft(2, '0')}';

    return _ActionCard(
      title: 'Active journey',
      subtitle:
          'These details will stay attached to Get Home Safe so missed-arrival escalation gives your trusted circle more context.',
      accent: const Color(0xFF4CC9F0),
      children: [
        if (journey.destination.trim().isNotEmpty)
          _ProgressLine(
            label: 'Destination',
            value: journey.destination.trim(),
            allowWrap: true,
          ),
        if (journey.vehicleDetails.trim().isNotEmpty)
          _ProgressLine(
            label: 'Ride details',
            value: journey.vehicleDetails.trim(),
            allowWrap: true,
          ),
        if (journey.routeNote.trim().isNotEmpty)
          _ProgressLine(
            label: 'Route note',
            value: journey.routeNote.trim(),
            allowWrap: true,
          ),
        _ProgressLine(label: 'Expected arrival', value: eta),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: state.isPerformingAction
                  ? null
                  : () => controller.markArrivedSafely(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7AE582),
                foregroundColor: const Color(0xFF06130B),
              ),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Reached Safely'),
            ),
            OutlinedButton.icon(
              onPressed: state.isPerformingAction
                  ? null
                  : () => _showRunningLateSheet(context, ref),
              icon: const Icon(Icons.schedule_outlined),
              label: const Text('Running Late'),
            ),
            OutlinedButton.icon(
              onPressed: state.isPerformingAction
                  ? null
                  : () => _showJourneyPlannerSheet(context, state),
              icon: const Icon(Icons.edit_road_outlined),
              label: const Text('Change Route'),
            ),
            OutlinedButton.icon(
              onPressed: state.isPerformingAction
                  ? null
                  : () => _showJourneyUpdateSheet(
                        context,
                        ref,
                        state,
                        type: _JourneyUpdateType.vehicle,
                      ),
              icon: const Icon(Icons.local_taxi_outlined),
              label: const Text('Changed Vehicle'),
            ),
            OutlinedButton.icon(
              onPressed: state.isPerformingAction
                  ? null
                  : () => _showJourneyUpdateSheet(
                        context,
                        ref,
                        state,
                        type: _JourneyUpdateType.route,
                      ),
              icon: const Icon(Icons.alt_route_outlined),
              label: const Text('Route Changed'),
            ),
            FilledButton.icon(
              onPressed: state.isPerformingAction
                  ? null
                  : () => _showTrustedCircleUpdateSheet(context, ref, state),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFB703),
                foregroundColor: const Color(0xFF1A1200),
              ),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Notify Trusted Circle'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.remaining,
  });

  final SafetyDashboardState state;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readiness = _buildReadinessReport(state);
    final activeLabel = switch (state.activeMode) {
      SafetyMode.idle => 'Ready',
      SafetyMode.silent => 'Silent escalation in progress',
      SafetyMode.fullPanic => 'Full panic in progress',
      SafetyMode.checkIn => 'Get Home Safe armed',
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B1E27), Color(0xFF11131A)],
        ),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            activeLabel,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF181B22),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              readiness.banner,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            state.statusMessage ??
                'Add trusted contacts and rehearse your flow before you need it.',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          if (remaining != null) ...[
            const SizedBox(height: 16),
            Text(
              'Get Home Safe expires in ${_formatDuration(remaining!)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF4CC9F0),
              ),
            ),
            if (state.activeJourney != null &&
                state.activeJourney!.destination.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Destination: ${state.activeJourney!.destination.trim()}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) {
      return '00:00';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ContactsTab extends ConsumerStatefulWidget {
  const _ContactsTab({required this.state});

  final SafetyDashboardState state;

  @override
  ConsumerState<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<_ContactsTab> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationshipController = TextEditingController();

  int _priority = 1;
  bool _prefersCall = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(safetyDashboardProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ActionCard(
          title: 'Trusted contacts',
          subtitle:
              'Choose people who will answer quickly, coordinate with each other, and escalate if you go silent.',
          accent: const Color(0xFF7AE582),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _relationshipController,
              decoration: const InputDecoration(
                labelText: 'Relationship',
                hintText: 'Sister, friend, hostel warden, colleague',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 - First responder')),
                DropdownMenuItem(value: 2, child: Text('2 - Secondary backup')),
                DropdownMenuItem(value: 3, child: Text('3 - Wider support')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _priority = value;
                  });
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Call this person during full panic'),
              value: _prefersCall,
              onChanged: (value) {
                setState(() {
                  _prefersCall = value;
                });
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await controller.saveContact(
                  name: _nameController.text,
                  phone: _phoneController.text,
                  relationship: _relationshipController.text,
                  priority: _priority,
                  prefersCall: _prefersCall,
                );
                _nameController.clear();
                _phoneController.clear();
                _relationshipController.clear();
                if (mounted) {
                  setState(() {
                    _priority = 1;
                    _prefersCall = true;
                  });
                }
              },
              child: const Text('Save Contact'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.state.contacts.isEmpty)
          const _EmptyState(
            title: 'No trusted contacts yet',
            body:
                'Add at least 2 contacts: one person who answers immediately and one backup who can escalate.',
          )
        else
          ...widget.state.contacts.map(
            (contact) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ContactTile(contact: contact),
            ),
          ),
      ],
    );
  }
}

class _ContactTile extends ConsumerWidget {
  const _ContactTile({required this.contact});

  final TrustedContact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF11131A),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF202532),
            child: Text(contact.priority.toString()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${contact.relationship} | ${contact.phone}',
                  style: const TextStyle(color: Colors.white70),
                ),
                if (contact.prefersCall)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Preferred for full-panic follow-up calls',
                      style: TextStyle(color: Color(0xFF7AE582)),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: contact.id == null
                ? null
                : () => ref
                    .read(safetyDashboardProvider.notifier)
                    .removeContact(contact.id!),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.state});

  final SafetyDashboardState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ActionCard(
          title: 'Incident timeline',
          subtitle:
              'A lightweight local record helps after stalking, harassment, or repeated unsafe travel incidents.',
          accent: const Color(0xFFCDB4DB),
          children: [
            _InfoLine(
              label: 'Emergency number',
              value: state.settings.primaryEmergencyNumber,
            ),
            _InfoLine(
              label: 'Women helpline',
              value: state.settings.womenHelplineNumber,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.incidents.isEmpty)
          const _EmptyState(
            title: 'No incidents logged yet',
            body:
                'Once you trigger Alert Family, Full Panic, a helpline call, or a missed Get Home Safe escalation, it will appear here.',
          )
        else
          ...state.incidents.map(
            (incident) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF11131A),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      incident.mode,
                      style: const TextStyle(
                        color: Color(0xFFCDB4DB),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      incident.summary,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTimestamp(incident.createdAt),
                      style: const TextStyle(color: Colors.white60),
                    ),
                    if (incident.locationText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        incident.locationText!,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatTimestamp(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year;
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.children,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11131A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11131A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }
}

void _showEmergencySheet(
  BuildContext context,
  WidgetRef ref,
  SafetyDashboardState state,
) {
  final controller = ref.read(safetyDashboardProvider.notifier);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick SOS Actions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Use the fastest path for the situation you are in right now.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              _BottomSheetAction(
                title: 'Full Panic',
                subtitle: '112 + alerts to trusted contacts',
                color: const Color(0xFFE54B4B),
                onTap: () {
                  Navigator.pop(context);
                  controller.triggerFullPanic();
                },
              ),
              _BottomSheetAction(
                title: 'Alert Family',
                subtitle: 'Discreet message with location',
                color: const Color(0xFFFFB703),
                onTap: () {
                  Navigator.pop(context);
                  controller.triggerSilentSos();
                },
              ),
              _BottomSheetAction(
                title: 'Call 112',
                subtitle: 'Direct emergency call',
                color: const Color(0xFF4CC9F0),
                onTap: () {
                  Navigator.pop(context);
                  controller.callEmergencyNumber();
                },
              ),
              _BottomSheetAction(
                title: 'Call 181',
                subtitle: 'Women helpline support',
                color: const Color(0xFF7AE582),
                onTap: () {
                  Navigator.pop(context);
                  controller.callWomenHelpline();
                },
              ),
              _BottomSheetAction(
                title: 'Get Home Safe',
                subtitle: 'Escalates if you miss it',
                color: const Color(0xFFCDB4DB),
                onTap: () async {
                  Navigator.pop(context);
                  await controller.updateSettings(
                    state.settings.copyWith(checkInMinutes: 15),
                  );
                  controller.startCheckIn(15);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _BottomSheetAction extends StatelessWidget {
  const _BottomSheetAction({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF181B22),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showShortcutCheatSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Fastest SHIELD shortcuts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 10),
              _ShortcutBullet(
                title: 'Hold for Full Panic',
                body: 'Long-press the red shortcut surface or the floating Quick SOS button to arm a 5-second emergency countdown.',
              ),
              _ShortcutBullet(
                title: 'Triple-tap the SHIELD title',
                body: 'Use this hidden shortcut for a quieter path when disguise mode is on or you cannot navigate the full screen.',
              ),
              _ShortcutBullet(
                title: 'Open camouflage screen',
                body: 'Use the notes screen as a cover, then long-press or triple-tap to trigger help without exposing the dashboard.',
              ),
              _ShortcutBullet(
                title: 'Cancel only if safe',
                body: 'Each armed shortcut gives you 5 seconds to stop a false alarm before SHIELD escalates.',
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showQuickActionsPreviewSheet(
  BuildContext context,
  SafetyDashboardState state,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick actions preview',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This mirrors the layout users see when SHIELD opens from the Quick Settings tile or quick-open shortcut.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 18),
              _BottomSheetAction(
                title: 'Full Panic',
                subtitle: '112 + alerts to trusted contacts',
                color: const Color(0xFFE54B4B),
                onTap: () => Navigator.of(context).pop(),
              ),
              _BottomSheetAction(
                title: 'Alert Family',
                subtitle: state.contacts.isEmpty
                    ? 'Add trusted contacts before using the discreet alert path'
                    : 'Discreet message with location',
                color: const Color(0xFFFFB703),
                onTap: () => Navigator.of(context).pop(),
              ),
              _BottomSheetAction(
                title: 'Call 112',
                subtitle: 'Direct emergency call',
                color: const Color(0xFF4CC9F0),
                onTap: () => Navigator.of(context).pop(),
              ),
              _BottomSheetAction(
                title: 'Get Home Safe',
                subtitle: 'Escalates if you miss it',
                color: const Color(0xFFCDB4DB),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showEmergencyProgressSheet(
  BuildContext context,
  SafetyDashboardState state,
) {
  final progress = _buildEmergencyProgress(state);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Emergency progress',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _ProgressLine(
                label: 'Current mode',
                value: switch (state.activeMode) {
                  SafetyMode.fullPanic => 'Full Panic',
                  SafetyMode.silent => 'Alert Family',
                  SafetyMode.checkIn => 'Get Home Safe',
                  SafetyMode.idle => 'Standby',
                },
              ),
              _ProgressLine(
                label: 'Trusted circle',
                value: state.contacts.isEmpty
                    ? 'No contacts configured'
                    : '${state.contacts.length} contacts configured',
              ),
              _ProgressLine(
                label: 'Latest update',
                value: state.statusMessage ?? 'No update yet',
                allowWrap: true,
              ),
              const SizedBox(height: 12),
              for (final step in progress.steps.take(3)) ...[
                _ProgressStepTile(step: step),
                const SizedBox(height: 10),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF181B22),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  progress.recoveryGuidance,
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'False alarm path: call or message the trusted people who may have received your alert, then review the incident timeline before re-arming SHIELD.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showRecoverySheet(context, state);
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('False Alarm / I\'m Safe Now'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showShortcutCountdownSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Color accent,
  required Future<void> Function() onConfirmed,
}) {
  showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _ShortcutCountdownSheet(
        title: title,
        subtitle: subtitle,
        accent: accent,
        onConfirmed: onConfirmed,
      );
    },
  );
}

void _showRecoverySheet(
  BuildContext context,
  SafetyDashboardState state,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _RecoverySheet(state: state);
    },
  );
}

void _showShortcutTestLab(
  BuildContext context,
  SafetyDashboardState state,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _ShortcutTestLab(state: state);
    },
  );
}

void _showJourneyPlannerSheet(
  BuildContext context,
  SafetyDashboardState state,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _JourneyPlannerSheet(state: state);
    },
  );
}

void _showRunningLateSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _RunningLateSheet(
        onExtend: (minutes) async {
          await ref.read(safetyDashboardProvider.notifier).extendCheckIn(minutes);
        },
      );
    },
  );
}

void _showJourneyUpdateSheet(
  BuildContext context,
  WidgetRef ref,
  SafetyDashboardState state, {
  required _JourneyUpdateType type,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _JourneyUpdateSheet(
        state: state,
        type: type,
        onSubmit: ({
          required String primaryValue,
          required String note,
        }) async {
          final controller = ref.read(safetyDashboardProvider.notifier);
          final journey = state.activeJourney;
          if (journey == null) {
            return;
          }

          if (type == _JourneyUpdateType.vehicle) {
            final summary = note.trim().isEmpty
                ? 'Vehicle changed during Get Home Safe.'
                : 'Vehicle changed during Get Home Safe. $note';
            await controller.updateJourneyProgress(
              mode: 'Vehicle Changed',
              vehicleDetails: primaryValue,
              summary: summary,
            );
            return;
          }

          final summary = note.trim().isEmpty
              ? 'Route changed during Get Home Safe.'
              : 'Route changed during Get Home Safe. $note';
          await controller.updateJourneyProgress(
            mode: 'Route Changed',
            routeNote: primaryValue,
            summary: summary,
          );
        },
      );
    },
  );
}

void _showTrustedCircleUpdateSheet(
  BuildContext context,
  WidgetRef ref,
  SafetyDashboardState state,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _TrustedCircleUpdateSheet(
        state: state,
        onSend: ({required String updateLabel, String? note}) async {
          await ref
              .read(safetyDashboardProvider.notifier)
              .notifyTrustedCircleOfJourneyUpdate(
                updateLabel: updateLabel,
                note: note,
              );
        },
      );
    },
  );
}

Future<String?> _showSetPinSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const _SetPinSheet(),
  );
}

Future<bool?> _showDisableLockSheet(BuildContext context) {
  return _showDangerConfirmSheet(
    context,
    title: 'Disable app lock?',
    body:
        'This removes the local PIN gate from SHIELD on this device. Anyone opening the app will be able to see your dashboard immediately.',
    confirmLabel: 'Disable Lock',
  );
}

Future<bool?> _showDangerConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF11131A),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE54B4B),
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

class _RecoverySheet extends ConsumerWidget {
  const _RecoverySheet({required this.state});

  final SafetyDashboardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(safetyDashboardProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'False Alarm / I\'m Safe Now',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use this if the danger has passed. The next steps are about calming your trusted circle, reviewing what already happened, and getting SHIELD ready again.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 18),
            _RecoveryActionTile(
              title: 'I\'m Safe Now',
              subtitle: 'Stop the active Get Home Safe timer and return SHIELD to standby.',
              color: const Color(0xFF7AE582),
              onTap: () {
                controller.cancelCheckIn();
                Navigator.of(context).pop();
              },
            ),
            _RecoveryActionTile(
              title: 'Call 112 again',
              subtitle: 'Use this if the situation changed and you still need emergency help.',
              color: const Color(0xFFE54B4B),
              onTap: () {
                Navigator.of(context).pop();
                controller.callEmergencyNumber();
              },
            ),
            _RecoveryActionTile(
              title: 'Call 181 support',
              subtitle: 'Reach the women helpline for follow-up help, emotional support, or guidance.',
              color: const Color(0xFF4CC9F0),
              onTap: () {
                Navigator.of(context).pop();
                controller.callWomenHelpline();
              },
            ),
            _RecoveryActionTile(
              title: 'Review incident timeline',
              subtitle: 'Check what SHIELD logged so you can explain the false alarm clearly.',
              color: const Color(0xFFCDB4DB),
              onTap: () {
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 10),
            Text(
              state.contacts.isEmpty
                  ? 'Trusted-circle follow-up: no contacts are configured yet, so your next step is to rehearse the flow after you add them.'
                  : 'Trusted-circle follow-up: call or text the people who may have received your alert and tell them clearly that you are safe now.',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutTestLab extends StatelessWidget {
  const _ShortcutTestLab({required this.state});

  final SafetyDashboardState state;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shortcut Test Lab',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rehearse how SHIELD behaves before you rely on it. These practice actions do not send real alerts or start live calls.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 18),
            _RecoveryActionTile(
              title: 'Practice Safety Hub sheet',
              subtitle: 'See the same fast-action menu that the tile and safety-hub shortcut will show.',
              color: const Color(0xFF80ED99),
              onTap: () {
                Navigator.of(context).pop();
                _showQuickActionsPreviewSheet(context, state);
              },
            ),
            _RecoveryActionTile(
              title: 'Practice Full Panic countdown',
              subtitle: 'Preview the long-press countdown without actually calling or alerting anyone.',
              color: const Color(0xFFE54B4B),
              onTap: () {
                Navigator.of(context).pop();
                _showShortcutCountdownSheet(
                  context,
                  title: 'Practice Full Panic',
                  subtitle:
                      'This is a rehearsal only. No call or SOS alert will be sent when the countdown finishes.',
                  accent: const Color(0xFFE54B4B),
                  onConfirmed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Practice complete. No live emergency action was sent.'),
                      ),
                    );
                  },
                );
              },
            ),
            _RecoveryActionTile(
              title: 'Practice Alert Family countdown',
              subtitle: 'Preview the discreet countdown without messaging your trusted contacts.',
              color: const Color(0xFFFFB703),
              onTap: () {
                Navigator.of(context).pop();
                _showShortcutCountdownSheet(
                  context,
                  title: 'Practice Alert Family',
                  subtitle:
                      'This is a rehearsal only. No live message or location alert will be sent.',
                  accent: const Color(0xFFFFB703),
                  onConfirmed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Alert Family practice complete. No contacts were alerted.'),
                      ),
                    );
                  },
                );
              },
            ),
            _RecoveryActionTile(
              title: 'Open Android setup guide',
              subtitle: 'See exactly where to add the widget, tile, pinned notification, and app-icon shortcuts on Android.',
              color: const Color(0xFFCDB4DB),
              onTap: () {
                Navigator.of(context).pop();
                _showAndroidSetupGuide(context);
              },
            ),
            _RecoveryActionTile(
              title: 'Review device-entry checklist',
              subtitle: 'Confirm notification, widget, Quick Settings tile, and app-icon shortcut placement for one-handed access.',
              color: const Color(0xFF4CC9F0),
              onTap: () {
                Navigator.of(context).pop();
                _showDeviceChecklist(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyPlannerSheet extends ConsumerStatefulWidget {
  const _JourneyPlannerSheet({required this.state});

  final SafetyDashboardState state;

  @override
  ConsumerState<_JourneyPlannerSheet> createState() =>
      _JourneyPlannerSheetState();
}

class _JourneyPlannerSheetState extends ConsumerState<_JourneyPlannerSheet> {
  late final TextEditingController _destinationController;
  late final TextEditingController _vehicleController;
  late final TextEditingController _routeController;
  late int _minutes;

  @override
  void initState() {
    super.initState();
    final journey = widget.state.activeJourney;
    _destinationController =
        TextEditingController(text: journey?.destination ?? '');
    _vehicleController =
        TextEditingController(text: journey?.vehicleDetails ?? '');
    _routeController = TextEditingController(text: journey?.routeNote ?? '');
    _minutes = widget.state.settings.checkInMinutes;
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _vehicleController.dispose();
    _routeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          28 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plan journey',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add the details your trusted circle will need if you miss arrival: where you are going, how you are getting there, and any route note worth checking.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _destinationController,
              decoration: const InputDecoration(
                labelText: 'Destination',
                hintText: 'Home, hostel, PG, office, station',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vehicleController,
              decoration: const InputDecoration(
                labelText: 'Ride details',
                hintText: 'Cab number, auto plate, driver name, metro line',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _routeController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Route note',
                hintText:
                    'Via Ring Road, Gate 2 pickup, friend tracking live location',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Expected arrival window',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final minutes in const [15, 30, 60])
                  ChoiceChip(
                    label: Text('$minutes min'),
                    selected: _minutes == minutes,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _minutes = minutes;
                        });
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final journey = JourneyPlan(
                    destination: _destinationController.text.trim(),
                    routeNote: _routeController.text.trim(),
                    vehicleDetails: _vehicleController.text.trim(),
                    startedAt: DateTime.now(),
                    expectedArrival:
                        DateTime.now().add(Duration(minutes: _minutes)),
                  );
                  ref
                      .read(safetyDashboardProvider.notifier)
                      .startCheckIn(_minutes, journey);
                  Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CC9F0),
                  foregroundColor: const Color(0xFF06131A),
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.route_outlined),
                label: const Text('Start Get Home Safe'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tip: add cab, auto, hostel gate, campus block, or office landmark details here so follow-up is faster if you go silent.',
              style: TextStyle(color: Colors.white60, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningLateSheet extends StatelessWidget {
  const _RunningLateSheet({required this.onExtend});

  final Future<void> Function(int minutes) onExtend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Running late',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Extend Get Home Safe without losing your current destination and ride details.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 18),
            for (final minutes in const [10, 15, 30])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await onExtend(minutes);
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text('Add $minutes minutes'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _JourneyUpdateType {
  vehicle,
  route,
}

class _JourneyUpdateSheet extends StatefulWidget {
  const _JourneyUpdateSheet({
    required this.state,
    required this.type,
    required this.onSubmit,
  });

  final SafetyDashboardState state;
  final _JourneyUpdateType type;
  final Future<void> Function({
    required String primaryValue,
    required String note,
  }) onSubmit;

  @override
  State<_JourneyUpdateSheet> createState() => _JourneyUpdateSheetState();
}

class _JourneyUpdateSheetState extends State<_JourneyUpdateSheet> {
  late final TextEditingController _primaryController;
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final journey = widget.state.activeJourney;
    _primaryController = TextEditingController(
      text: widget.type == _JourneyUpdateType.vehicle
          ? (journey?.vehicleDetails ?? '')
          : (journey?.routeNote ?? ''),
    );
  }

  @override
  void dispose() {
    _primaryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVehicle = widget.type == _JourneyUpdateType.vehicle;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          28 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isVehicle ? 'Changed vehicle' : 'Route changed',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isVehicle
                  ? 'Update cab, auto, driver, or coach details so your trusted circle has the latest ride context.'
                  : 'Update the route note so your trusted circle knows what changed during the journey.',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _primaryController,
              maxLines: isVehicle ? 1 : 3,
              decoration: InputDecoration(
                labelText: isVehicle ? 'New ride details' : 'New route note',
                hintText: isVehicle
                    ? 'New cab number, driver name, metro coach, auto plate'
                    : 'Changed route via flyover, switched to metro, getting off at Gate 3',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Optional note',
                hintText: 'Reason for the change, delay, pickup issue, or anything your circle should know',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await widget.onSubmit(
                    primaryValue: _primaryController.text.trim(),
                    note: _noteController.text.trim(),
                  );
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: Text(isVehicle ? 'Save Vehicle Change' : 'Save Route Change'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustedCircleUpdateSheet extends StatefulWidget {
  const _TrustedCircleUpdateSheet({
    required this.state,
    required this.onSend,
  });

  final SafetyDashboardState state;
  final Future<void> Function({
    required String updateLabel,
    String? note,
  }) onSend;

  @override
  State<_TrustedCircleUpdateSheet> createState() =>
      _TrustedCircleUpdateSheetState();
}

class _TrustedCircleUpdateSheetState extends State<_TrustedCircleUpdateSheet> {
  final TextEditingController _noteController = TextEditingController();
  String _selectedLabel = 'Running late';
  bool _showJourneyContext = true;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveJourney = widget.state.activeJourney;
    final previewJourney = _showJourneyContext
        ? liveJourney ??
            JourneyPlan(
              destination: 'Office to Hostel Gate 2',
              routeNote: 'Returning via metro and short auto ride',
              vehicleDetails: 'Auto KA05XY4321',
              startedAt: DateTime.now(),
              expectedArrival: DateTime.now().add(const Duration(minutes: 20)),
            )
        : null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          28 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notify trusted circle',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Send a quick journey update without cancelling Get Home Safe. SHIELD will attach your latest trip context automatically.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ChoiceChip(
                  label: const Text('With journey context'),
                  selected: _showJourneyContext,
                  onSelected: (selected) {
                    setState(() {
                      _showJourneyContext = selected;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Without journey context'),
                  selected: !_showJourneyContext,
                  onSelected: (selected) {
                    if (!selected) {
                      return;
                    }
                    setState(() {
                      _showJourneyContext = false;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              children: [
                for (final option in const [
                  (
                    label: 'Running late',
                    preview: 'Calm update that tells them to watch your ETA and route.',
                  ),
                  (
                    label: 'Route changed',
                    preview: 'Signals a changed path and asks them to watch for anything unexpected.',
                  ),
                  (
                    label: 'Vehicle changed',
                    preview: 'Highlights new cab, auto, or ride details so they can track the switch.',
                  ),
                  (
                    label: 'Check on me',
                    preview: 'More urgent wording that tells them to call you immediately.',
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TrustedCirclePresetTile(
                      label: option.label,
                      preview: option.preview,
                      selected: _selectedLabel == option.label,
                      onTap: () {
                        setState(() {
                          _selectedLabel = option.label;
                        });
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: 3,
              onChanged: (_) {
                setState(() {});
              },
              decoration: const InputDecoration(
                labelText: 'Optional note',
                hintText:
                    'Traffic near hostel, driver changed, route blocked, phone battery low',
              ),
            ),
            const SizedBox(height: 16),
            _TrustedCircleMessagePreview(
              updateLabel: _selectedLabel,
              note: _noteController.text.trim(),
              journey: previewJourney,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await widget.onSend(
                    updateLabel: _selectedLabel,
                    note: _noteController.text.trim(),
                  );
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Send Update'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustedCircleMessagePreview extends StatelessWidget {
  const _TrustedCircleMessagePreview({
    required this.updateLabel,
    required this.note,
    required this.journey,
  });

  final String updateLabel;
  final String note;
  final JourneyPlan? journey;

  @override
  Widget build(BuildContext context) {
    final noteLine = note.isEmpty ? null : 'Note: $note';
    final destination = journey?.destination.trim();
    final vehicle = journey?.vehicleDetails.trim();
    final route = journey?.routeNote.trim();
    final guidance = switch (updateLabel) {
      'Running late' => 'Preview tone: calm update, watch ETA and route.',
      'Route changed' =>
        'Preview tone: route deviation, watch for unexpected movement.',
      'Vehicle changed' =>
        'Preview tone: ride switch, save the new vehicle details.',
      'Check on me' => 'Preview tone: urgent, call immediately.',
      _ => 'Preview tone: trusted-circle update.',
    };
    final actionBadge = switch (updateLabel) {
      'Running late' => 'Contacts will: acknowledge, watch ETA, call if delay grows',
      'Route changed' => 'Contacts will: note route change, watch movement, call if it looks off',
      'Vehicle changed' => 'Contacts will: save new vehicle details, watch closely, call if needed',
      'Check on me' => 'Contacts will: call now, track location, escalate quickly if no response',
      _ => 'Contacts will: acknowledge update and keep watch',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFB703).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SMS Preview',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            guidance,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF11131A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              actionBadge,
              style: const TextStyle(
                color: Colors.white70,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'TRUSTED CIRCLE UPDATE\n$updateLabel',
            style: const TextStyle(
              color: Colors.white,
              height: 1.35,
            ),
          ),
          if (destination != null && destination.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Destination: $destination',
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ],
          if (vehicle != null && vehicle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Vehicle: $vehicle',
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ],
          if (route != null && route.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Route note: $route',
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ],
          if (noteLine != null) ...[
            const SizedBox(height: 6),
            Text(
              noteLine,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            journey == null
                ? 'SHIELD will send location and action guidance only, without trip details.'
                : 'SHIELD will also attach your latest trip details, location, and action guidance.',
            style: const TextStyle(color: Colors.white60, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _TrustedCirclePresetTile extends StatelessWidget {
  const _TrustedCirclePresetTile({
    required this.label,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF1F2631) : const Color(0xFF181B22),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFB703).withOpacity(0.45)
                  : Colors.white10,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                preview,
                style: TextStyle(
                  color: selected ? Colors.white70 : Colors.white60,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetPinSheet extends StatefulWidget {
  const _SetPinSheet();

  @override
  State<_SetPinSheet> createState() => _SetPinSheetState();
}

class _SetPinSheetState extends State<_SetPinSheet> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          28 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set app lock PIN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use a short PIN that you can enter quickly under pressure. This PIN stays only on this device.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'PIN',
                hintText: '4 to 6 digits',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFE54B4B)),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final pin = _pinController.text.trim();
                  final confirm = _confirmPinController.text.trim();
                  if (pin.length < 4 || pin.length > 6) {
                    setState(() {
                      _error = 'Use a PIN between 4 and 6 digits.';
                    });
                    return;
                  }
                  if (pin != confirm) {
                    setState(() {
                      _error = 'PIN entries do not match.';
                    });
                    return;
                  }
                  Navigator.of(context).pop(pin);
                },
                child: const Text('Enable App Lock'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppLockScreen extends StatefulWidget {
  const _AppLockScreen({
    required this.onUnlock,
    required this.disguiseModeEnabled,
  });

  final Future<bool> Function(String pin) onUnlock;
  final bool disguiseModeEnabled;

  @override
  State<_AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<_AppLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.disguiseModeEnabled ? 'Daily Notes Locked' : 'SHIELD Locked';
    final subtitle = widget.disguiseModeEnabled
        ? 'Enter your workspace PIN to reopen your notes.'
        : 'Enter your local PIN to reopen the safety dashboard.';
    final buttonLabel =
        widget.disguiseModeEnabled ? 'Open Workspace' : 'Unlock SHIELD';

    return Scaffold(
      backgroundColor: const Color(0xFF08090D),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF11131A),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'PIN',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFE54B4B)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting
                            ? null
                            : () async {
                                setState(() {
                                  _submitting = true;
                                  _error = null;
                                });
                                final isValid =
                                    await widget.onUnlock(_pinController.text.trim());
                                if (!mounted) {
                                  return;
                                }
                                setState(() {
                                  _submitting = false;
                                  if (!isValid) {
                                    _error = 'Incorrect PIN. Try again.';
                                  }
                                });
                              },
                        child: Text(_submitting ? 'Unlocking...' : buttonLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryActionTile extends StatelessWidget {
  const _RecoveryActionTile({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF181B22),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white70, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showAndroidSetupGuide(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Android setup guide',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Set these up once when you are calm. The goal is to keep one safety entry point available from the shade, one from the home screen, and one from the app icon.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              SizedBox(height: 18),
              _SetupGuideCard(
                step: '1',
                title: 'Pin the quick-access notification',
                body: 'Open SHIELD and tap Pin Notification in Device access. Allow notification permission if Android asks. Then pull down your shade once and confirm you can see Full Panic, Alert Family, and Get Home Safe.',
                accent: Color(0xFFE54B4B),
              ),
              _SetupGuideCard(
                step: '2',
                title: 'Place the home-screen widget',
                body: 'Long-press an empty part of your home screen, open Widgets, find SHIELD, and drag it onto the page you reach most often with one hand. Keep it on your first or second screen, not buried inside a folder.',
                accent: Color(0xFF80ED99),
              ),
              _SetupGuideCard(
                step: '3',
                title: 'Add the Quick Settings tile',
                body: 'Swipe down twice, tap the edit pencil or edit tiles button, and drag the SHIELD tile into the first visible row. That way one swipe and one tap can open the Safety Hub even when the app is closed.',
                accent: Color(0xFF4CC9F0),
              ),
              _SetupGuideCard(
                step: '4',
                title: 'Memorize the app-icon shortcut path',
                body: 'Press and hold the SHIELD app icon until Android shows Safety Hub, Full Panic, Alert Family, and Get Home Safe. Rehearse this once so you do not have to think about it later.',
                accent: Color(0xFFFFB703),
              ),
              _SetupGuideCard(
                step: '5',
                title: 'Run one rehearsal',
                body: 'Open Shortcut Test Lab and practice the quick-actions sheet plus both countdowns. SHIELD keeps those rehearsals safe, so no real alert or call goes out while you learn the flow.',
                accent: Color(0xFFCDB4DB),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showDeviceChecklist(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF11131A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Device-entry checklist',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 10),
              _ShortcutBullet(
                title: 'Notification',
                body: 'Pin the SHIELD quick-access notification so Full Panic, Alert Family, and Get Home Safe stay available from the shade.',
              ),
              _ShortcutBullet(
                title: 'Widget',
                body: 'Add the SHIELD home-screen widget somewhere your thumb can reach quickly without hunting across screens.',
              ),
              _ShortcutBullet(
                title: 'Quick Settings tile',
                body: 'Place the SHIELD tile in the first visible row so one swipe opens the quick-action sheet immediately.',
              ),
              _ShortcutBullet(
                title: 'App-icon shortcuts',
                body: 'Press and hold the SHIELD app icon to surface Safety Hub, Full Panic, Alert Family, and Get Home Safe without opening the full app first.',
              ),
              _ShortcutBullet(
                title: 'Practice',
                body: 'Run the test lab once after setup so you know what each entry point looks like under pressure.',
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ShortcutCountdownSheet extends StatefulWidget {
  const _ShortcutCountdownSheet({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onConfirmed,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final Future<void> Function() onConfirmed;

  @override
  State<_ShortcutCountdownSheet> createState() => _ShortcutCountdownSheetState();
}

class _ShortcutCountdownSheetState extends State<_ShortcutCountdownSheet> {
  Timer? _timer;
  int _secondsRemaining = 5;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_secondsRemaining <= 1) {
        timer.cancel();
        _confirm();
        return;
      }

      setState(() {
        _secondsRemaining--;
      });
    });
  }

  Future<void> _confirm() async {
    if (_confirming) {
      return;
    }

    _confirming = true;
    Navigator.of(context).pop();
    await widget.onConfirmed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF181B22),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: widget.accent.withOpacity(0.35)),
              ),
              child: Column(
                children: [
                  Text(
                    '$_secondsRemaining',
                    style: TextStyle(
                      color: widget.accent,
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Seconds to cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Cancel alarm'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupGuideCard extends StatelessWidget {
  const _SetupGuideCard({
    required this.step,
    required this.title,
    required this.body,
    required this.accent,
  });

  final String step;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF181B22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                step,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutBullet extends StatelessWidget {
  const _ShortcutBullet({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 8, color: Colors.white54),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.white70, height: 1.4),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

_ReadinessReport _buildReadinessReport(SafetyDashboardState state) {
  final hasTrustedCircle = state.contacts.length >= 2;
  final hasPrimaryCaller = state.contacts.any((contact) => contact.prefersCall);
  final hasHiddenShortcut = state.settings.disguiseModeEnabled;
  final hasFastCheckIn = state.settings.checkInMinutes <= 30;
  final hasIndiaEmergencyPath =
      state.settings.primaryEmergencyNumber.trim().isNotEmpty &&
      state.settings.womenHelplineNumber.trim().isNotEmpty;

  final items = [
    _ReadinessItem(
      title: 'Trusted circle',
      detail: hasTrustedCircle
          ? '${state.contacts.length} contacts are ready to coordinate.'
          : 'Add at least 2 contacts so one person can respond while another escalates.',
      ready: hasTrustedCircle,
    ),
    _ReadinessItem(
      title: 'Call-back responder',
      detail: hasPrimaryCaller
          ? 'One contact is marked as your first follow-up call.'
          : 'Mark one contact as your first call-back person after 112.',
      ready: hasPrimaryCaller,
    ),
    _ReadinessItem(
      title: 'Hidden trigger',
      detail: hasHiddenShortcut
          ? 'Camouflage mode is on, so the triple-tap shortcut stays available.'
          : 'Enable camouflage mode to keep a low-visibility shortcut ready.',
      ready: hasHiddenShortcut,
    ),
    _ReadinessItem(
      title: 'Get Home Safe',
      detail: hasFastCheckIn
          ? 'Missed Get Home Safe timers escalate within ${state.settings.checkInMinutes} minutes.'
          : 'Reduce the Get Home Safe timer to 30 minutes or less for late travel and ride safety.',
      ready: hasFastCheckIn,
    ),
    _ReadinessItem(
      title: 'India support path',
      detail: hasIndiaEmergencyPath
          ? '112 and the women helpline are configured for immediate calling.'
          : 'Set both emergency numbers so SHIELD can launch the right call fast.',
      ready: hasIndiaEmergencyPath,
    ),
  ];

  final readyCount = items.where((item) => item.ready).length;
  final level = readyCount >= 4
      ? _ReadinessLevel.ready
      : readyCount >= 2
          ? _ReadinessLevel.partial
          : _ReadinessLevel.notReady;
  final summary = switch (level) {
    _ReadinessLevel.ready =>
      'Your quick triggers, contacts, and fallback layers are mostly in place.',
    _ReadinessLevel.partial =>
      'The core flow exists, but one or two missing layers could slow help in a crisis.',
    _ReadinessLevel.notReady =>
      'Right now SHIELD still needs setup before it can be trusted under pressure.',
  };
  final banner = '$readyCount/5 safety layers configured';

  return _ReadinessReport(
    level: level,
    items: items,
    summary: summary,
    banner: banner,
  );
}

class _ReadinessReport {
  const _ReadinessReport({
    required this.level,
    required this.items,
    required this.summary,
    required this.banner,
  });

  final _ReadinessLevel level;
  final List<_ReadinessItem> items;
  final String summary;
  final String banner;
}

class _ReadinessItem {
  const _ReadinessItem({
    required this.title,
    required this.detail,
    required this.ready,
  });

  final String title;
  final String detail;
  final bool ready;
}

enum _ReadinessLevel {
  notReady,
  partial,
  ready,
}

_EmergencyProgress _buildEmergencyProgress(SafetyDashboardState state) {
  final status = (state.statusMessage ?? '').toLowerCase();
  final locationDone = status.contains('location') ||
      status.contains('alerted') ||
      status.contains('call launched') ||
      status.contains('call placed');
  final contactsDone = status.contains('trusted contact') ||
      status.contains('trusted contacts') ||
      status.contains('could not reach');
  final callDone = status.contains('call launched') ||
      status.contains('call placed') ||
      status.contains('calling 112');
  final callFailed = status.contains('could not be launched');

  switch (state.activeMode) {
    case SafetyMode.fullPanic:
      return _EmergencyProgress(
        steps: [
          _EmergencyProgressStep(
            title: 'Location snapshot',
            detail: 'SHIELD is collecting your latest safe-to-share location data.',
            status: locationDone ? _ProgressStatus.complete : _ProgressStatus.active,
          ),
          _EmergencyProgressStep(
            title: 'Trusted-circle alerts',
            detail: 'Your selected contacts will be alerted with time and location details.',
            status: contactsDone ? _ProgressStatus.complete : _ProgressStatus.pending,
          ),
          _EmergencyProgressStep(
            title: 'Emergency call path',
            detail: callFailed
                ? 'The emergency call path needs attention. Use the 112 quick action again if safe.'
                : 'SHIELD will launch the 112 call path as part of Full Panic.',
            status: callFailed
                ? _ProgressStatus.attention
                : callDone
                    ? _ProgressStatus.complete
                    : _ProgressStatus.pending,
          ),
        ],
        recoveryGuidance:
            'If this was accidental, wait for the current step to finish, then immediately message or call the people who may already have been alerted.',
      );
    case SafetyMode.silent:
      return _EmergencyProgress(
        steps: [
          _EmergencyProgressStep(
            title: 'Location snapshot',
            detail: 'SHIELD is collecting your latest location before sending the discreet alert.',
            status: locationDone ? _ProgressStatus.complete : _ProgressStatus.active,
          ),
          _EmergencyProgressStep(
            title: 'Silent message delivery',
            detail: 'Your trusted contacts will get the alert without starting a loud emergency call.',
            status: contactsDone ? _ProgressStatus.complete : _ProgressStatus.pending,
          ),
          _EmergencyProgressStep(
            title: 'Fallback support',
            detail: 'If you stay unsafe, use the Safety Button hold gesture or the 112 quick action next.',
            status: _ProgressStatus.pending,
          ),
        ],
        recoveryGuidance:
            'If the situation has settled, follow up with your trusted circle so they know whether to stand down or stay on watch.',
      );
    case SafetyMode.checkIn:
      return _EmergencyProgress(
        steps: [
          const _EmergencyProgressStep(
            title: 'Get Home Safe armed',
            detail: 'A timer is active and SHIELD will escalate only if you miss it.',
            status: _ProgressStatus.active,
          ),
          const _EmergencyProgressStep(
            title: 'Reach-safe action',
            detail: 'Tap the Safety Button once when you are safe to stop the timer.',
            status: _ProgressStatus.pending,
          ),
          const _EmergencyProgressStep(
            title: 'Escalation fallback',
            detail: 'If the situation changes, hold the Safety Button instead of waiting for the timer to expire.',
            status: _ProgressStatus.pending,
          ),
        ],
        recoveryGuidance:
            'Use Get Home Safe for late travel, cabs, campus routes, and any journey where someone should know if you go silent.',
      );
    case SafetyMode.idle:
      return _EmergencyProgress(
        steps: [
          const _EmergencyProgressStep(
            title: 'Tap',
            detail: 'Opens the Safety Hub for 112, 181, Alert Family, and Get Home Safe actions.',
            status: _ProgressStatus.complete,
          ),
          const _EmergencyProgressStep(
            title: 'Double tap',
            detail: 'Starts the discreet Alert Family path when trusted contacts are configured.',
            status: _ProgressStatus.complete,
          ),
          const _EmergencyProgressStep(
            title: 'Hold',
            detail: 'Arms the Full Panic countdown for the fastest loud escalation path.',
            status: _ProgressStatus.complete,
          ),
        ],
        recoveryGuidance:
            'Practice all three gestures once so they become muscle memory before you ever need them in real danger.',
      );
  }
}

class _EmergencyProgress {
  const _EmergencyProgress({
    required this.steps,
    required this.recoveryGuidance,
  });

  final List<_EmergencyProgressStep> steps;
  final String recoveryGuidance;
}

class _EmergencyProgressStep {
  const _EmergencyProgressStep({
    required this.title,
    required this.detail,
    required this.status,
  });

  final String title;
  final String detail;
  final _ProgressStatus status;
}

enum _ProgressStatus {
  complete,
  active,
  pending,
  attention,
}
