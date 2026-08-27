import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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


/// A fake owner API so the Overview tab has a float and a pending BF request
/// to render. Without the request there is no Approve button, and without the
/// button the add-BF dialog cannot be opened at all.
class _FakeOwnerApi extends OwnerApiService {
  _FakeOwnerApi(Ref ref) : super(ref: ref);

  @override
  Future<int?> readAgentBf({required String agentMembershipId}) async => 45000;

  @override
  Future<PendingBfRequest?> readPendingBfRequest({
    required String membershipId,
  }) async =>
      PendingBfRequest(
        requestId: 'bf1',
        requestedAmount: 25000,
        reason: 'Short for the Uranduru round, two new loans going out today.',
        askedAt: DateTime(2026, 8, 27, 9, 30),
      );
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
            // ensureVisible first: the TabBar scrolls, so a later tab sits
            // off-screen and a tap with warnIfMissed off lands on nothing
            // in silence -- which is how these walks reported every tab
            // clean while never leaving the first one.
            await tester.ensureVisible(find.byType(Tab).at(i));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(Tab).at(i), warnIfMissed: false);
            await tester.pumpAndSettle();
          }
          expectNoLayoutFault(tester, 'OW-002 agent profile tab $i at ${scale}x$tag');
        });
      }
    }
  }
  // OW-002's three dialogs, none of which had a test opening them.
  //
  // Add BF is reached only when a pending request exists, so the fake API
  // supplies one -- otherwise the Approve button is absent and the test would
  // pass by never opening anything.
  List<Override> withApi(AgentProfile p) => [
        agentProfileProvider.overrideWith(() => _SeededAgentProfile(p)),
        ownerApiServiceProvider.overrideWith((ref) => _FakeOwnerApi(ref)),
      ];

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';

      testWidgets('OW-002 add BF dialog survives ${scale}x$tag', (tester) async {
        await pumpManaScreen(tester, screen(),
            textScale: scale, language: lang, overrides: withApi(profile));
        await tester.pumpAndSettle();

        // Approve is the second button in the request block; reject is first.
        // Below the fold from 1.6x and therefore not built, so it has to be
        // scrolled to before it can be found at all.
        final buttons = find.byType(ElevatedButton);
        for (var i = 0; i < 6 && buttons.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(TabBarView), const Offset(0, -220));
          await tester.pumpAndSettle();
        }
        expect(buttons, findsWidgets, reason: 'no approve button — no pending request rendered');
        await tester.ensureVisible(buttons.first);
        await tester.pumpAndSettle();
        await tester.tap(buttons.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'add BF dialog did not open');
        expectNoLayoutFault(tester, 'OW-002 add BF at ${scale}x$tag');
      });

      testWidgets('OW-002 top-up sheet survives ${scale}x$tag', (tester) async {
        await pumpManaScreen(tester, screen(),
            textScale: scale, language: lang, overrides: withApi(profile));
        await tester.pumpAndSettle();

        final topUp = find.byType(OutlinedButton);
        for (var i = 0; i < 6 && topUp.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(TabBarView), const Offset(0, -220));
          await tester.pumpAndSettle();
        }
        expect(topUp, findsWidgets, reason: 'no top-up control on Overview');
        await tester.ensureVisible(topUp.last);
        await tester.pumpAndSettle();
        await tester.tap(topUp.last, warnIfMissed: false);
        await tester.pumpAndSettle();

        expectNoLayoutFault(tester, 'OW-002 top-up at ${scale}x$tag');
      });
    }
  }
  // Distribute Profit Share, on the Compensation tab (index 2). The last of
  // OW-002's three dialogs.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('OW-002 profit share dialog survives ${scale}x$tag', (tester) async {
        await pumpManaScreen(tester, screen(),
            textScale: scale, language: lang, overrides: withApi(profile));
        await tester.pumpAndSettle();
        // ensureVisible first: the TabBar scrolls, so a later tab sits
        // off-screen and a tap with warnIfMissed off lands on nothing
        // in silence -- which is how these walks reported every tab
        // clean while never leaving the first one.
        await tester.ensureVisible(find.byType(Tab).at(2));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Tab).at(2), warnIfMissed: false);
        await tester.pumpAndSettle();

        final declare = find.byType(FilledButton);
        for (var i = 0; i < 6 && declare.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(TabBarView), const Offset(0, -220));
          await tester.pumpAndSettle();
        }
        expect(declare, findsWidgets, reason: 'PROBE: no declare button');
        await tester.ensureVisible(declare.first);
        await tester.pumpAndSettle();
        await tester.tap(declare.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'profit share dialog did not open');
        expectNoLayoutFault(tester, 'OW-002 profit share at ${scale}x$tag');
      });
    }
  }
}
