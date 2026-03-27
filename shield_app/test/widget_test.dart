import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield_app/features/sos/application/safety_dashboard_controller.dart';
import 'package:shield_app/features/sos/data/safety_repository.dart';
import 'package:shield_app/features/sos/domain/incident_log.dart';
import 'package:shield_app/features/sos/domain/safety_settings.dart';
import 'package:shield_app/features/sos/domain/trusted_contact.dart';
import 'package:shield_app/main.dart';

void main() {
  testWidgets('renders the SOS home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          safetyRepositoryProvider.overrideWithValue(_FakeSafetyRepository()),
        ],
        child: ShieldApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('SHIELD'), findsOneWidget);
    expect(find.text('India-first SOS safety center'), findsOneWidget);
    expect(find.text('Trigger Full Panic'), findsOneWidget);
    expect(find.text('Send Silent SOS'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
  });
}

class _FakeSafetyRepository extends SafetyRepository {
  @override
  Future<List<TrustedContact>> getContacts() async {
    return const [
      TrustedContact(
        id: 1,
        name: 'Asha',
        phone: '9999999999',
        relationship: 'Friend',
        priority: 1,
        prefersCall: true,
      ),
    ];
  }

  @override
  Future<List<IncidentLog>> getIncidents() async {
    return const [];
  }

  @override
  Future<SafetySettings> getSettings() async {
    return SafetySettings.defaults();
  }
}
