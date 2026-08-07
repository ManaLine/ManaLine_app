import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_003_investor_management.dart';
import 'package:mana_line/features/owner_workspace/state/investor_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededInvestorWorkforceNotifier extends InvestorWorkforceNotifier {
  _SeededInvestorWorkforceNotifier(this._seed);
  final InvestorWorkforceState _seed;

  @override
  InvestorWorkforceState build() => _seed;

  @override
  Future<void> load(String businessId) async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260808010000 + reused earlier keys) — the landing list view only
/// (dashboard strip, search, filter chips, pending request, investor rows),
/// not the tabbed Investor Profile drill-in.
const _ow003TeluguTranslations = <String, Map<String, String>>{
  'investor_management': {'English': 'Investor Management', 'Telugu': 'పెట్టుబడిదారుల నిర్వహణ'},
  'add_existing_investor': {'English': 'Add Existing Investor', 'Telugu': 'ఇప్పటికే ఉన్న పెట్టుబడిదారుని జోడించండి'},
  'pre_existing_investor': {'English': 'Pre-Existing Investor', 'Telugu': 'ముందుగా ఉన్న పెట్టుబడిదారు'},
  'search_by_name_or_mlid': {'English': 'Search by name or MLID', 'Telugu': 'పేరు లేదా MLID ద్వారా శోధించండి'},
  'no_investors_match_view': {'English': 'No investors match this view.', 'Telugu': 'ఈ వీక్షణకు సరిపోలే పెట్టుబడిదారులు లేరు.'},
  'total': {'English': 'Total', 'Telugu': 'మొత్తం'},
  'active': {'English': 'Active', 'Telugu': 'యాక్టివ్'},
  'pending_invitation_status': {'English': 'Pending Invitation', 'Telugu': 'పెండింగ్ ఆహ్వానం'},
  'pending_acceptance_status': {'English': 'Pending Acceptance', 'Telugu': 'పెండింగ్ అంగీకారం'},
  'suspended': {'English': 'Suspended', 'Telugu': 'సస్పెండ్ చేయబడింది'},
  'removed': {'English': 'Removed', 'Telugu': 'తీసివేయబడింది'},
  'temporarily_disabled': {'English': 'Temporarily Disabled', 'Telugu': 'తాత్కాలికంగా నిలిపివేయబడింది'},
  'total_investment_balance': {'English': 'Total Investment Balance', 'Telugu': 'మొత్తం పెట్టుబడి నిల్వ'},
  'interest_payable': {'English': 'Interest Payable', 'Telugu': 'చెల్లించవలసిన వడ్డీ'},
  'all': {'English': 'All', 'Telugu': 'అన్నీ'},
  'reject': {'English': 'Reject', 'Telugu': 'తిరస్కరించండి'},
  'approve': {'English': 'Approve', 'Telugu': 'ఆమోదించండి'},
};

void main() {
  final investors = [
    InvestorSummary(
      investorId: 'i1',
      fullName: 'Karri Siri Manikanta Reddy',
      mlid: 'MLIV0000012345',
      phoneNumber: '9493509919',
      investmentBalance: 250000,
      roi: 1.5,
      interestDue: 3750,
      membershipStatus: 'Active',
      lastTransaction: DateTime(2026, 8, 1),
    ),
    InvestorSummary(
      investorId: 'i2',
      fullName: 'Chalasani Ramana',
      mlid: 'MLIV0000012346',
      phoneNumber: '9876543210',
      investmentBalance: 0,
      roi: 0,
      interestDue: 0,
      membershipStatus: 'Pending Acceptance',
    ),
  ];
  final seed = InvestorWorkforceState(investors: investors);

  for (final scale in kManaTextScales) {
    testWidgets('OW-003 Investor Management survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const InvestorManagementScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [investorWorkforceProvider.overrideWith(() => _SeededInvestorWorkforceNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-003 Investor Management at ${scale}x');
    });

    testWidgets('OW-003 Investor Management survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const InvestorManagementScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow003TeluguTranslations,
        overrides: [investorWorkforceProvider.overrideWith(() => _SeededInvestorWorkforceNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-003 Investor Management at ${scale}x in Telugu');
    });
  }

  testWidgets('OW-003 shows the investors', (tester) async {
    await pumpManaScreen(
      tester,
      const InvestorManagementScreen(businessId: 'b1'),
      overrides: [investorWorkforceProvider.overrideWith(() => _SeededInvestorWorkforceNotifier(seed))],
    );
    expect(find.textContaining('Karri Siri Manikanta Reddy'), findsWidgets);
  });
}
