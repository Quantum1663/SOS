import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/safety_dashboard_controller.dart';
import '../application/safety_dashboard_state.dart';
import '../domain/trusted_contact.dart';

class SosHomeScreen extends ConsumerStatefulWidget {
  const SosHomeScreen({super.key});

  @override
  ConsumerState<SosHomeScreen> createState() => _SosHomeScreenState();
}

class _SosHomeScreenState extends ConsumerState<SosHomeScreen> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int _disguiseTapCount = 0;
  Timer? _disguiseTapTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _disguiseTapTimer?.cancel();
    super.dispose();
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
      _showEmergencySheet(context, ref, state);
    }
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
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: const Color(0xFF08090D),
            appBar: AppBar(
              backgroundColor: const Color(0xFF11131A),
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SHIELD'),
                  Text(
                    'India-first SOS safety center',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Safety'),
                  Tab(text: 'Contacts'),
                  Tab(text: 'History'),
                ],
              ),
            ),
            floatingActionButton: _QuickActionsFab(state: state),
            body: TabBarView(
              children: [
                _SafetyTab(state: state, now: _now),
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
  const _QuickActionsFab({required this.state});

  final SafetyDashboardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () => _showEmergencySheet(context, ref, state),
      backgroundColor: const Color(0xFFE54B4B),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.bolt),
      label: const Text('Quick SOS'),
    );
  }
}

class _SafetyTab extends ConsumerWidget {
  const _SafetyTab({
    required this.state,
    required this.now,
  });

  final SafetyDashboardState state;
  final DateTime now;

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
        _QuickLaunchCard(state: state),
        const SizedBox(height: 16),
        _ActionCard(
          title: 'Immediate danger',
          subtitle:
              'Calls 112, sends alerts to trusted contacts, and logs the incident.',
          accent: const Color(0xFFE54B4B),
          children: [
            FilledButton(
              onPressed:
                  state.isPerformingAction ? null : controller.triggerFullPanic,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE54B4B),
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Trigger Full Panic'),
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
          title: 'Silent danger',
          subtitle: 'Sends a discreet SOS with location to trusted contacts.',
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
              child: const Text('Send Silent SOS'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ActionCard(
          title: 'Travel check-in',
          subtitle:
              'If you miss the timer, the app escalates to a silent SOS.',
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
                    child: const Text('Cancel Check-in'),
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
          ],
        ),
        const SizedBox(height: 16),
        _ActionCard(
          title: 'Preparedness snapshot',
          subtitle:
              'A strong SOS setup needs trusted contacts, discreet messaging, and clear helpline paths.',
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
              title: const Text('Enable camouflage feature'),
              subtitle: const Text(
                'Keeps the disguise screen available without replacing the main dashboard.',
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
                            onSecretTap: () {},
                            onSecretLongPress: () =>
                                _showEmergencySheet(context, ref, state),
                          ),
                        ),
                      );
                    }
                  : null,
              child: const Text('Open Camouflage Screen'),
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
                  label: 'Silent',
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
                  label: '15 min',
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
    final activeLabel = switch (state.activeMode) {
      SafetyMode.idle => 'Ready',
      SafetyMode.silent => 'Silent escalation in progress',
      SafetyMode.fullPanic => 'Full panic in progress',
      SafetyMode.checkIn => 'Check-in armed',
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
          Text(
            state.statusMessage ??
                'Add trusted contacts and rehearse your flow before you need it.',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          if (remaining != null) ...[
            const SizedBox(height: 16),
            Text(
              'Check-in expires in ${_formatDuration(remaining!)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF4CC9F0),
              ),
            ),
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
                'Once you trigger a silent SOS, full panic, helpline call, or missed check-in escalation, it will appear here.',
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
                      incident.mode.toUpperCase(),
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
                title: 'Silent SOS',
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
                title: '15 min Check-in',
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
