import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_009_profile.dart';
import 'package:mana_line/features/agent_workspace/state/agent_dashboard_state.dart' show AgentAreaAssignment;
import 'package:mana_line/features/agent_workspace/state/agent_profile_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededProfile extends AgentProfileNotifier {
  @override
  AgentProfileState build() => _profileSeed;

  @override
  Future<void> load({required String personId, required String agentId, required String businessId}) async {}
}

final _profileSeed = AgentProfileState(
  profile: AgentProfileSummary(
    fullName: 'Chalasani Ramana',
    mlid: 'MLAG0000012345',
    phoneNumber: '9493509919',
    joinedDate: DateTime(2026, 1, 15),
    currentStatus: 'Active',
  ),
  memberships: [
    AgentBusinessMembership(businessId: 'b1', businessName: 'Sri Lakshmi Finance', membershipStatus: 'Active'),
    AgentBusinessMembership(businessId: 'b2', businessName: 'Venkata Subrahmanyam Finance', membershipStatus: 'Active'),
  ],
  areaAssignments: [
    AgentAreaAssignment(
      operatingAreaId: 'a1',
      areaName: 'Srikalahasti — Uranduru Colony Round',
      enabled: true,
      selectedInSession: true,
    ),
  ],
  compensationSummary: AgentCompensationSummary(fixedSalary: 15000, salaryCycleStatus: 'Monthly · paid'),
);


const _telugu = <String, Map<String, String>>{
  'profile': {'English': 'Profile', 'Telugu': 'ప్రొఫైల్'},
  'route_area_assignment': {'English': 'Route / Area Assignment', 'Telugu': 'మార్గం / ప్రాంత కేటాయింపు'},
  'my_compensation': {'English': 'My Compensation', 'Telugu': 'నా వేతనం'},
  'other_business_memberships': {'English': 'Other Business Memberships', 'Telugu': 'ఇతర వ్యాపార సభ్యత్వాలు'},
  'tenancy_isolation_note': {
    'English': "Each Owner sees only their own tenancy's data for you — nothing here is shared or blended across businesses.",
    'Telugu': 'ప్రతి యజమాని మీ గురించి వారి స్వంత టెనెన్సీ డేటాను మాత్రమే చూస్తారు — ఇక్కడ ఏదీ వ్యాపారాల మధ్య పంచుకోబడదు లేదా కలపబడదు.',
  },
  'phone': {'English': 'Phone', 'Telugu': 'ఫోన్'},
  'joined_date_label': {'English': 'Joined Date', 'Telugu': 'చేరిన తేదీ'},
  'in_session': {'English': 'In Session', 'Telugu': 'సెషన్‌లో'},
  'agent': {'English': 'Agent', 'Telugu': 'ఏజెంట్'},
  'transaction_history': {'English': 'Transaction History', 'Telugu': 'లావాదేవీల చరిత్ర'},
  'total_collected_last_100': {'English': 'Total Collected (Last 100)', 'Telugu': 'మొత్తం వసూలు (చివరి 100)'},
  'loan_number_note': {'English': 'Loan {number}', 'Telugu': 'రుణం {number}'},
  'receipt_note': {'English': 'Receipt: {number}', 'Telugu': 'రసీదు: {number}'},
};

/// AG-010 is NOT tested here.
///
/// It was, and the tests proved nothing: they seeded agentHistoryProvider,
/// which the screen does not read -- it reads ledgerHistoryProvider. Every
/// run rendered an empty history and passed. ledger_history_screens_test.dart
/// covers both OW-017 and AG-010 against the provider they actually use, at
/// every text scale, which is why the dead ones are gone rather than fixed
/// twice over.
void main() {
  for (final scale in kManaTextScales) {
    testWidgets('AG-009 profile survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const Ag009ProfileScreen(personId: '1', agentId: 'a1', businessId: 'b1'),
        textScale: scale,
        overrides: [agentProfileProvider.overrideWith(_SeededProfile.new)],
      );
      expectNoLayoutFault(tester, 'AG-009 at ${scale}x');
    });

    testWidgets('AG-009 profile survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const Ag009ProfileScreen(personId: '1', agentId: 'a1', businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _telugu,
        overrides: [agentProfileProvider.overrideWith(_SeededProfile.new)],
      );
      expectNoLayoutFault(tester, 'AG-009 at ${scale}x in Telugu');
    });


  }
}
