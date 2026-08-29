import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/tokens/colors.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_006_owner_settlement.dart';
import 'package:mana_line/features/agent_workspace/state/agent_settlement_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _Seeded extends AgentSettlementNotifier {
  _Seeded(this._seed);
  final AgentSettlementState _seed;

  @override
  AgentSettlementState build() => _seed;

  @override
  Future<void> enter({
    required String businessId,
    required String agentId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {}
}

/// Every line non-zero except bankCollected, which is here on purpose: a zero
/// line is dropped rather than printed as +Rs 0, and the layout must survive
/// that too.
///
/// The figures reconcile -- 50000 + 700 + 187500 + 25000 + 12000 + 3000
/// - 120000 - 4750 - 2000 = 151450 -- because a breakdown that does not reach
/// its own total is the bug this card was written to fix. Interest and fee sit
/// outside the sum: withheld at disbursement, and already inside the
/// collection figure when a customer repays them.
final _preview = SettlementPreview(
  openingBalance: 50000,
  bfReceived: 700,
  cashCollected: 187500,
  upiCollected: 25000,
  bankCollected: 0,
  chequeCollected: 12000,
  transfersIn: 3000,
  loanDistribution: 120000,
  expenses: 4750,
  transfersOut: 2000,
  interestEarned: 18000,
  processingFees: 1500,
  expectedClosingBalance: 151450,
);

final _draft = AgentSettlementState(
  stage: SettlementScreenStage.draftEntry,
  preview: _preview,
  cycleType: 'Daily',
  physicalCashDeclared: 112750,
);

const _telugu = <String, Map<String, String>>{
  'settlement': {'English': 'Settlement', 'Telugu': 'సెటిల్‌మెంట్'},
  'expense': {'English': 'Expense', 'Telugu': 'ఖర్చు'},
  'settlement_summary': {'English': 'Settlement Summary', 'Telugu': 'సెటిల్‌మెంట్ సారాంశం'},
  'opening_balance_bf': {'English': 'Opening Balance (BF)', 'Telugu': 'ప్రారంభ నిల్వ (BF)'},
  'cash_collected': {'English': 'Cash Collected', 'Telugu': 'వసూలు చేసిన నగదు'},
  'upi_collected': {'English': 'UPI Collected', 'Telugu': 'వసూలు చేసిన UPI'},
  'bank_collection': {'English': 'Bank Collection', 'Telugu': 'బ్యాంక్ వసూలు'},
  'cheque_collection': {'English': 'Cheque Collection', 'Telugu': 'చెక్ వసూలు'},
  'loan_distribution': {'English': 'Loan Distribution', 'Telugu': 'రుణ పంపిణీ'},
  'expenses': {'English': 'Expenses', 'Telugu': 'ఖర్చులు'},
  'expected_closing_balance': {'English': 'Expected Closing Balance', 'Telugu': 'ఆశించిన ముగింపు నిల్వ'},
  'physical_cash_declared': {'English': 'Physical Cash Declared', 'Telugu': 'ప్రకటించిన భౌతిక నగదు'},
  'cycle_account_note': {'English': '{cycle} Account', 'Telugu': '{cycle} ఖాతా'},
  'settlement_details': {'English': 'Settlement Details', 'Telugu': 'సెటిల్‌మెంట్ వివరాలు'},
  'physical_cash_field': {'English': 'Physical Cash (₹)', 'Telugu': 'భౌతిక నగదు (₹)'},
  'cheque_count_field': {'English': 'Cheque Count (tally, not persisted)', 'Telugu': 'చెక్ లెక్క (సరిపోల్చడానికి, నిల్వ చేయబడదు)'},
  'cheque_count_helper': {
    'English': 'Sits alongside Cheque Collection {amount} for your own reconciliation.',
    'Telugu': 'మీ స్వంత సరిపోల్చడం కోసం చెక్ వసూలు {amount} పక్కన ఉంటుంది.',
  },
  'supporting_remarks_field': {'English': 'Supporting Remarks', 'Telugu': 'సహాయక వ్యాఖ్యలు'},
  'supporting_remarks_hint': {'English': 'Optional — note anything the Owner should know', 'Telugu': 'ఐచ్ఛికం — యజమాని తెలుసుకోవలసినది ఏదైనా రాయండి'},
  'submit_settlement': {'English': 'Submit Settlement', 'Telugu': 'సెటిల్‌మెంట్ సమర్పించండి'},
  'bf_received': {'English': 'BF Received', 'Telugu': 'BF అందింది'},
  'cash': {'English': 'Cash', 'Telugu': 'నగదు'},
  'upi': {'English': 'UPI', 'Telugu': 'UPI'},
  'bank': {'English': 'Bank', 'Telugu': 'బ్యాంక్'},
  'cheque': {'English': 'Cheque', 'Telugu': 'చెక్కు'},
  'opening_bf': {'English': 'Opening (BF)', 'Telugu': 'ప్రారంభ (BF)'},
  'loans_issued': {'English': 'Loans Issued', 'Telugu': 'జారీ చేసిన రుణాలు'},
  'transfers_in': {'English': 'Received From Agents', 'Telugu': 'ఏజెంట్ల నుండి అందినది'},
  'transfers_out': {'English': 'Given To Agents', 'Telugu': 'ఏజెంట్లకు ఇచ్చినది'},
  'total_amount': {'English': 'Total Amount', 'Telugu': 'మొత్తం సొమ్ము'},
  'total_amount_note': {
    'English': 'Everything you are holding right now — cash, UPI, bank and cheque.',
    'Telugu': 'మీరు ఇప్పుడు కలిగి ఉన్నదంతా — నగదు, UPI, బ్యాంక్ మరియు చెక్కు.',
  },
  'earned_not_held_note': {
    'English': 'Interest {interest} and processing fee {fees} are already earned at disbursement — not part of the cash you hold.',
    'Telugu': 'వడ్డీ {interest} మరియు ప్రాసెసింగ్ ఫీజు {fees} రుణం ఇచ్చినప్పుడే ఆర్జించబడ్డాయి — మీ వద్ద ఉన్న నగదులో భాగం కాదు.',
  },
  'count_cash_declare_note': {
    'English': 'Count your cash and declare it. The difference is worked out when you submit.',
    'Telugu': 'మీ నగదును లెక్కించి ప్రకటించండి. మీరు సమర్పించినప్పుడు తేడా లెక్కించబడుతుంది.',
  },
};

void main() {
  final start = DateTime(2026, 8, 1);
  final end = DateTime(2026, 8, 7);

  for (final scale in kManaTextScales) {
    testWidgets('AG-006 settlement survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        OwnerSettlementScreen(businessId: 'b1', agentId: 'a1', periodStart: start, periodEnd: end),
        textScale: scale,
        overrides: [agentSettlementProvider.overrideWith(() => _Seeded(_draft))],
      );
      expectNoLayoutFault(tester, 'AG-006 at ${scale}x');
    });

    testWidgets('AG-006 settlement survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        OwnerSettlementScreen(businessId: 'b1', agentId: 'a1', periodStart: start, periodEnd: end),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _telugu,
        overrides: [agentSettlementProvider.overrideWith(() => _Seeded(_draft))],
      );
      expectNoLayoutFault(tester, 'AG-006 at ${scale}x in Telugu');
    });
  }

  testWidgets('the breakdown lines reach the total they sit above',
      (tester) async {
    // The whole point of showing the lines. When this first shipped they came
    // to Rs 5,08,860 against a float of Rs 5,08,930 -- the BF the Owner had
    // granted mid-round was missing -- and a card that does not add up teaches
    // people to stop reading it.
    final p = _preview;
    final sum = p.openingBalance +
        p.bfReceived +
        p.cashCollected +
        p.upiCollected +
        p.bankCollected +
        p.chequeCollected +
        p.transfersIn -
        p.loanDistribution -
        p.expenses -
        p.transfersOut;

    expect(sum, p.expectedClosingBalance,
        reason: 'green minus red must equal the Total Amount shown');
    expect(sum + p.interestEarned + p.processingFees,
        isNot(p.expectedClosingBalance),
        reason: 'interest and fee are earnings, never cash in hand -- adding '
            'them would double count the interest already inside collections');
  });

  testWidgets('money in is green, money out is red, and zero lines are dropped',
      (tester) async {
    await pumpManaScreen(
      tester,
      OwnerSettlementScreen(
          businessId: 'b1', agentId: 'a1', periodStart: start, periodEnd: end),
      overrides: [agentSettlementProvider.overrideWith(() => _Seeded(_draft))],
    );

    Color colourOf(String needle) {
      final t = tester.widget<Text>(find
          .byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(needle))
          .first);
      return t.style!.color!;
    }

    expect(colourOf('1,87,500'), ManaColors.statusGood);
    expect(colourOf('1,20,000'), ManaColors.statusBad);

    // bankCollected is 0 and must not appear at all.
    expect(find.textContaining('Bank'), findsNothing);
    // The total itself is not a signed line.
    expect(find.textContaining('+₹1,51,450'), findsNothing);
  });
}
