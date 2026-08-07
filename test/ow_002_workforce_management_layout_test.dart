import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_002_workforce_management.dart';
import 'package:mana_line/features/owner_workspace/state/owner_api_service.dart' show AgentSummary;
import 'package:mana_line/features/owner_workspace/state/owner_workspace_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededWorkforceNotifier extends WorkforceNotifier {
  _SeededWorkforceNotifier(this._seed);
  final WorkforceState _seed;

  @override
  WorkforceState build() => _seed;

  @override
  Future<void> load(String businessId) async {}
}

/// The real ui_translations rows this screen was wired against (migrations
/// 20260807180725 / 20260807181108 + reused earlier keys) — the landing
/// list view only (dashboard strip, search, filter chips, agent rows), not
/// the tabbed Agent Profile drill-in.
const _ow002TeluguTranslations = <String, Map<String, String>>{
  'workforce_management': {'English': 'Workforce Management', 'Telugu': 'శ్రామిక నిర్వహణ'},
  'register_agent': {'English': 'Register Agent', 'Telugu': 'ఏజెంట్ నమోదు చేయండి'},
  'add_existing_agent': {'English': 'Add Existing Agent', 'Telugu': 'ఇప్పటికే ఉన్న ఏజెంట్‌ను జోడించండి'},
  'pre_existing_agent': {'English': 'Pre-Existing Agent', 'Telugu': 'ముందుగా ఉన్న ఏజెంట్'},
  'search_by_name_or_mlid': {'English': 'Search by name or MLID', 'Telugu': 'పేరు లేదా MLID ద్వారా శోధించండి'},
  'active': {'English': 'Active', 'Telugu': 'యాక్టివ్'},
  'pending_invitation_status': {'English': 'Pending Invitation', 'Telugu': 'పెండింగ్ ఆహ్వానం'},
  'pending_acceptance_status': {'English': 'Pending Acceptance', 'Telugu': 'పెండింగ్ అంగీకారం'},
  'disabled': {'English': 'Disabled', 'Telugu': 'నిలిపివేయబడింది'},
  'suspended': {'English': 'Suspended', 'Telugu': 'సస్పెండ్ చేయబడింది'},
  'removed': {'English': 'Removed', 'Telugu': 'తీసివేయబడింది'},
  'temporarily_disabled': {'English': 'Temporarily Disabled', 'Telugu': 'తాత్కాలికంగా నిలిపివేయబడింది'},
  'all': {'English': 'All', 'Telugu': 'అన్నీ'},
  'no_agents_match_view': {'English': 'No agents match this view.', 'Telugu': 'ఈ వీక్షణకు సరిపోలే ఏజెంట్లు లేరు.'},
};

void main() {
  final agents = [
    AgentSummary(
      agentId: 'a1',
      membershipId: 'm1',
      fullName: 'Karri Siri Manikanta Reddy',
      mlid: 'MLAG0000012345',
      phoneNumber: '9493509919',
      status: 'Active',
      businessAccess: 'Full Access',
      currentRoute: 'Srikalahasti — Uranduru Colony Round',
      todaysCollections: 4500,
      todaysLoans: 0,
      joinedDate: DateTime(2026, 1, 15),
      lastLogin: DateTime(2026, 8, 7, 9, 0),
      lastLoginVisible: true,
    ),
    AgentSummary(
      agentId: 'a2',
      membershipId: 'm2',
      fullName: 'Chalasani Ramana',
      mlid: 'MLAG0000012346',
      phoneNumber: '9876543210',
      status: 'Pending Invitation',
      businessAccess: 'Restricted',
      todaysCollections: 0,
      todaysLoans: 0,
      joinedDate: DateTime(2026, 7, 1),
    ),
  ];
  final seed = WorkforceState(agents: agents);

  for (final scale in kManaTextScales) {
    testWidgets('OW-002 Workforce Management survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const WorkforceManagementScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [workforceProvider.overrideWith(() => _SeededWorkforceNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-002 Workforce Management at ${scale}x');
    });

    testWidgets('OW-002 Workforce Management survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const WorkforceManagementScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow002TeluguTranslations,
        overrides: [workforceProvider.overrideWith(() => _SeededWorkforceNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-002 Workforce Management at ${scale}x in Telugu');
    });
  }

  testWidgets('OW-002 shows the agents', (tester) async {
    await pumpManaScreen(
      tester,
      const WorkforceManagementScreen(businessId: 'b1'),
      overrides: [workforceProvider.overrideWith(() => _SeededWorkforceNotifier(seed))],
    );
    expect(find.textContaining('Karri Siri Manikanta Reddy'), findsWidgets);
  });
}
