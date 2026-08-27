import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_002_workforce_management.dart';
import 'package:mana_line/features/owner_workspace/state/owner_api_service.dart';
import 'package:mana_line/features/owner_workspace/state/owner_workspace_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// OW-002's Agent Profile is a six-tab drill-in, and OW-002's existing layout
/// test never opened it -- it pumped the agent LIST and stopped there. Six tab
/// bodies had therefore never been laid out at any scale.
///
/// TabBarView lays out only the visible page, so reaching a tab means tapping
/// it. Pumping the screen once covers tab zero and reports green for the rest.
class _SeededAgentProfile extends AgentProfileNotifier {
  _SeededAgentProfile(this._seed);
  final AgentProfile _seed;

  @override
  Future<AgentProfile> build(String agentId) async => _seed;
}

void main() {
  final agent = AgentSummary(
    agentId: 'a1',
    membershipId: 'm1',
    fullName: 'Kandukuri Siva Rama Krishna',
    mlid: 'MLAG0000012345',
    phoneNumber: '9493509919',
    status: 'Active',
    businessAccess: 'Full',
    todaysCollections: 1284500,
    todaysLoans: 320000,
    joinedDate: DateTime(2024, 6, 12),
  );

  final compensation = CompensationRecord(
    fixedSalary: 18000,
    salaryCycle: 'Monthly',
    dailyAllowance: 200,
    profitSharePercent: 2.5,
    effectiveDate: DateTime(2026, 4, 1),
  );

  final profile = AgentProfile(
    summary: agent,
    permissions: const {
      'can_collect_payments': true,
      'can_apply_penalty': false,
      'can_record_expenses': true,
      'can_issue_loans': true,
      'can_add_remarks': true,
      'can_upload_documents': false,
      'can_edit_customer_contact': false,
      'can_create_customer': true,
      'can_perform_day_settlement': true,
    },
    assignedAreas: const [
      'Srikalahasti — Uranduru Colony',
      'Puttur',
      'Renigunta',
    ],
    currentCompensation: compensation,
    compensationHistory: [compensation],
  );

  Widget screen() => AgentProfileScreen(businessId: 'b1', agent: agent);

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      for (var i = 0; i < 6; i++) {
        testWidgets('OW-002 agent profile tab $i survives text scale ${scale}x$tag',
            (tester) async {
          await pumpManaScreen(
            tester,
            screen(),
            textScale: scale,
            language: lang,
            overrides: [
              agentProfileProvider.overrideWith(() => _SeededAgentProfile(profile)),
            ],
          );
          await tester.pumpAndSettle();

          if (i > 0) {
            await tester.tap(find.byType(Tab).at(i), warnIfMissed: false);
            await tester.pumpAndSettle();
          }
          expectNoLayoutFault(tester, 'OW-002 agent profile tab $i at ${scale}x$tag');
        });
      }
    }
  }
}
