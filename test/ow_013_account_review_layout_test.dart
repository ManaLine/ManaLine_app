import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_013_account_review.dart';
import 'package:mana_line/features/owner_workspace/state/account_review_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

final _seed = AccountReviewState(
  bfPanel: OwnerBfPanelData(
    ownerCashInHand: 250000,
    heldByAgents: 50000,
    returningThisSession: 187500,
  ),
  settlements: [
    AccountSettlementSummary(
      settlementId: 's1',
      accountPeriodId: 'ap1',
      businessDate: DateTime(2026, 8, 7),
      agentName: 'Chalasani Ramana',
      totalCollections: 187500,
      totalLoansIssued: 120000,
      totalInterest: 4500,
      totalProcessingFee: 1200,
      expenses: 750,
      short: 100,
      excess: 0,
      difference: 100,
      status: 'Pending Owner Review',
      handOverCash: 150000,
      handOverUpi: 37500,
      handOverCheque: 0,
    ),
    AccountSettlementSummary(
      settlementId: 's2',
      accountPeriodId: 'ap2',
      businessDate: DateTime(2026, 8, 6),
      agentName: 'Lakshmi Narasimha Rao',
      totalCollections: 90000,
      totalLoansIssued: 0,
      totalInterest: 0,
      totalProcessingFee: 0,
      expenses: 0,
      short: 0,
      excess: 0,
      difference: 0,
      status: 'Approved',
      handOverCash: 90000,
      handOverUpi: 0,
      handOverCheque: 0,
    ),
  ],
  accessDays: [
    AgentAccessDay(accessDayId: 'ad1', agentName: 'Chalasani Ramana', allowanceAmount: 200),
  ],
);

class _SeededAccountReviewNotifier extends AccountReviewNotifier {
  @override
  AccountReviewState build() => _seed;

  @override
  Future<void> load(String businessId) async {}
}

/// The real ui_translations rows this screen was wired against
/// (migration 20260808070000 + reused earlier keys).
const _ow013Telugu = <String, Map<String, String>>{
  'account_review': {'English': 'Account Review', 'Telugu': 'ఖాతా సమీక్ష'},
  'daily_allowance': {'English': 'Daily Allowance', 'Telugu': 'రోజువారీ భత్యం'},
  'owner_bf': {'English': 'Owner BF', 'Telugu': 'యజమాని BF'},
  'balance_before_today': {'English': 'Balance Before Today', 'Telugu': 'నేటికి ముందు నిల్వ'},
  'assigned_out_this_session': {'English': 'Assigned Out This Session', 'Telugu': 'ఈ సెషన్‌లో కేటాయించినది'},
  'returning_this_session': {'English': 'Returning This Session', 'Telugu': 'ఈ సెషన్‌లో తిరిగి వస్తున్నది'},
  'owner_bf_current': {'English': 'Owner BF, Current', 'Telugu': 'యజమాని BF, ప్రస్తుతం'},
  'provisional_until_approved_note': {'English': 'Provisional until each pending account is Approved.', 'Telugu': 'ప్రతి పెండింగ్ ఖాతా ఆమోదించబడే వరకు తాత్కాలికం.'},
  'total_collections': {'English': 'Total Collections', 'Telugu': 'మొత్తం వసూళ్లు'},
  'total_loans_issued': {'English': 'Total Loans Issued', 'Telugu': 'మొత్తం జారీ చేసిన రుణాలు'},
  'total_interest': {'English': 'Total Interest', 'Telugu': 'మొత్తం వడ్డీ'},
  'total_processing_fee': {'English': 'Total Processing Fee', 'Telugu': 'మొత్తం ప్రాసెసింగ్ ఫీజు'},
  'expenses': {'English': 'Expenses', 'Telugu': 'ఖర్చులు'},
  'short': {'English': 'Short', 'Telugu': 'తక్కువ'},
  'difference': {'English': 'Difference', 'Telugu': 'తేడా'},
  'hand_over_balance': {'English': 'Hand Over Balance', 'Telugu': 'అప్పగించే నిల్వ'},
  'view': {'English': 'View', 'Telugu': 'చూడండి'},
  'approve': {'English': 'Approve', 'Telugu': 'ఆమోదించండి'},
  'return_label': {'English': 'Return', 'Telugu': 'తిరిగి పంపండి'},
  'lock_account': {'English': 'Lock Account', 'Telugu': 'ఖాతా లాక్ చేయండి'},
  'daily_allowance_tracking_note': {'English': 'Tracking/visibility only — no linkage to Payable Salary or any figure elsewhere on this screen.', 'Telugu': 'ట్రాకింగ్/కనిపించడం మాత్రమే — చెల్లించవలసిన జీతంతో లేదా ఈ స్క్రీన్‌లోని ఏ సంఖ్యతోనూ లింక్ లేదు.'},
  'allowance_note': {'English': 'Allowance: {amount}', 'Telugu': 'భత్యం: {amount}'},
};

void main() {
  Widget screen() => const AccountReviewScreen(businessId: 'b1');
  final overrides = [accountReviewProvider.overrideWith(_SeededAccountReviewNotifier.new)];

  for (final scale in kManaTextScales) {
    testWidgets('OW-013 account review tab survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(tester, screen(), textScale: scale, overrides: overrides);
      expectNoLayoutFault(tester, 'OW-013 review at ${scale}x');
    });

    testWidgets('OW-013 account review tab survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(tester, screen(),
          textScale: scale, language: ManaLanguage.telugu, translations: _ow013Telugu, overrides: overrides);
      expectNoLayoutFault(tester, 'OW-013 review at ${scale}x in Telugu');
    });
  }

  for (final lang in [null, ManaLanguage.telugu]) {
    final suffix = lang == null ? '' : ' in Telugu';
    testWidgets('OW-013 daily allowance tab survives text scale 2.0x$suffix', (tester) async {
      await pumpManaScreen(tester, screen(),
          textScale: 2.0,
          language: lang ?? ManaLanguage.english,
          translations: lang == null ? null : _ow013Telugu,
          overrides: overrides);
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      expectNoLayoutFault(tester, 'OW-013 daily allowance at 2.0x$suffix');
    });
  }

  testWidgets('OW-013 shows the settlements', (tester) async {
    await pumpManaScreen(tester, screen(), overrides: overrides);
    expect(find.textContaining('Chalasani Ramana'), findsWidgets);
  });
}
