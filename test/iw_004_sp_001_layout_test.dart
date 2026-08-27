import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/investor_workspace/screens/iw_004_request_withdrawal.dart';
import 'package:mana_line/features/investor_workspace/state/withdrawal_request_state.dart';
import 'package:mana_line/features/support_admin/screens/sp_001_aadhaar_dispute_resolution.dart';
import 'package:mana_line/features/support_admin/state/aadhaar_dispute_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// The last two screens with no layout coverage at all.
///
/// IW-004 is a money-entry screen -- an investor asking for their own money
/// back -- and SP-001 is a seven-step support workflow for the case where two
/// people claim one Aadhaar. Every SP-001 step draws a different body, so all
/// seven are pumped rather than just the entry step.
class _SeededWithdrawal extends WithdrawalRequestNotifier {
  _SeededWithdrawal(this._seed);
  final WithdrawalRequestState _seed;

  @override
  WithdrawalRequestState build() => _seed;

  @override
  Future<void> loadInvestment({
    required String investmentId,
    InvestmentSummary? fallbackSnapshot,
  }) async {}
}

class _SeededDispute extends AadhaarDisputeCaseNotifier {
  _SeededDispute(this._seed);
  final AadhaarDisputeCaseState _seed;

  @override
  AadhaarDisputeCaseState build() => _seed;
}

void main() {
  final investment = InvestmentSummary(
    investmentId: 'i1',
    availableBalance: 1284500,
    principalAmount: 1000000,
  );

  final withdrawalStates = <String, WithdrawalRequestState>{
    'loaded': WithdrawalRequestState(investment: investment),
    'loading': const WithdrawalRequestState(loadingInvestment: true),
    'submitting': WithdrawalRequestState(investment: investment, submitting: true),
    'error': const WithdrawalRequestState(
        error: 'Could not reach the server. Check your connection and try again.'),
  };

  final lookup = DisputeCaseLookup(
    personId: 'p1',
    currentMlid: 'MLTI0000012345',
    fullName: 'Nagabhushanam Venkata Subba Reddy',
  );

  final impact = SuspensionImpactSummary(rows: [
    SuspensionImpactRow(
      id: 'b1',
      label: 'Sri Satyanarayana Swamy Finance Corporation',
      role: 'Customer',
      isOwnerBusiness: false,
    ),
    SuspensionImpactRow(
      id: 'b2',
      label: 'Venkateswara Chit Funds And Finance',
      role: 'Owner',
      isOwnerBusiness: true,
    ),
  ]);

  AadhaarDisputeCaseState disputeAt(DisputeStep step) => AadhaarDisputeCaseState(
        step: step,
        searchMlidOrAadhaarInput: 'MLTI0000012345',
        existingAccount: lookup,
        secondPersonDecision: ManualVerificationDecision.verified,
        suspensionImpact: impact,
        originalHolderCorrectedAadhaar: '123456789012',
        originalHolderDecision: ManualVerificationDecision.verified,
        upgradeResult: MlidUpgradeResult(personId: 'p1', newMlid: 'MLCU0000012345'),
        idHistoryEntry: PersonIdHistoryEntry(
          oldMlid: 'MLTI0000012345',
          newMlid: 'MLCU0000012345',
          reason: 'Aadhaar dispute resolved in favour of the original holder',
          recordedAt: DateTime(2026, 8, 26),
        ),
      );

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';

      withdrawalStates.forEach((label, seed) {
        testWidgets('IW-004 $label survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const RequestWithdrawalScreen(investmentId: 'i1'),
            textScale: scale,
            language: lang,
            overrides: [withdrawalRequestProvider.overrideWith(() => _SeededWithdrawal(seed))],
          );
          expectNoLayoutFault(tester, 'IW-004 $label at ${scale}x$tag');
        });
      });

      testWidgets('SP-001 staff gate survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          const Sp001AadhaarDisputeResolutionScreen(),
          textScale: scale,
          language: lang,
          overrides: [
            aadhaarDisputeCaseProvider
                .overrideWith(() => _SeededDispute(disputeAt(DisputeStep.caseIntake))),
          ],
        );
        expectNoLayoutFault(tester, 'SP-001 staff gate at ${scale}x$tag');
      });

      for (final step in DisputeStep.values) {
        testWidgets('SP-001 ${step.name} survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const Sp001AadhaarDisputeResolutionScreen(),
            textScale: scale,
            language: lang,
            overrides: [
              aadhaarDisputeCaseProvider.overrideWith(() => _SeededDispute(disputeAt(step))),
            ],
          );

          // The staff-stub gate stands in front of every step. Without this
          // tap the test lays out the gate seven times over and proves
          // nothing about the steps themselves.
          final gate = find.byType(ElevatedButton);
          expect(gate, findsWidgets, reason: 'staff gate button missing');
          await tester.tap(gate.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expectNoLayoutFault(tester, 'SP-001 ${step.name} at ${scale}x$tag');
        });
      }
    }
  }
}
