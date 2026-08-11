import 'package:flutter_test/flutter_test.dart';
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

final _preview = SettlementPreview(
  openingBalance: 50000,
  cashCollected: 187500,
  upiCollected: 25000,
  bankCollected: 0,
  chequeCollected: 12000,
  loanDistribution: 120000,
  expenses: 4750,
  expectedClosingBalance: 112750,
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
}
