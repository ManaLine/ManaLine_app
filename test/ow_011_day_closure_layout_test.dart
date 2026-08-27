import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_011_day_closure.dart';
import 'package:mana_line/features/owner_workspace/state/day_closure_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededDayClosureNotifier extends DayClosureNotifier {
  _SeededDayClosureNotifier(this._seed);
  final DayClosureState _seed;

  @override
  DayClosureState build() => _seed;

  @override
  Future<void> runPrecheck({required String businessId, required String businessDate}) async {}

  @override
  Future<void> loadForReopen({required String businessId, required String businessDate}) async {}
}

final _blockedState = DayClosureState(
  phase: DayClosurePhase.blocked,
  businessDate: '2026-08-07',
  blockingIssues: [
    DayClosureBlockingIssue(type: 'Pending Collections', count: 3, detailLink: '/ow-006'),
    DayClosureBlockingIssue(type: 'Pending Loan Processing', count: 1, detailLink: '/ow-005'),
  ],
  warnings: [
    DayClosureBlockingIssue(type: 'Pending Drafts', count: 2),
  ],
);

final _differenceFoundState = DayClosureState(
  phase: DayClosurePhase.differenceFound,
  businessDate: '2026-08-07',
  expected: ExpectedFigures(expectedCash: 187500, expectedUpi: 25000, expectedBank: 0, expectedCheque: 0),
  physicalCash: 187000,
  upiBalance: 25000,
  bankBalance: 0,
  chequeBalance: 0,
  differenceLines: [
    DifferenceLine(method: 'Cash', expected: 187500, actual: 187000),
    DifferenceLine(method: 'UPI', expected: 25000, actual: 25000),
  ],
  recordedAdjustments: [
    RecordedAdjustment(adjustmentType: 'Short', amount: 500, appliedTo: 'Agent Salary Deduction'),
  ],
);

final _cashVerificationState = DayClosureState(
  phase: DayClosurePhase.cashVerification,
  businessDate: '2026-08-07',
  expected: ExpectedFigures(expectedCash: 187500, expectedUpi: 25000, expectedBank: 0, expectedCheque: 0),
);

final _finalReviewState = DayClosureState(
  phase: DayClosurePhase.finalReview,
  businessDate: '2026-08-07',
  expected: ExpectedFigures(expectedCash: 187500, expectedUpi: 25000, expectedBank: 0, expectedCheque: 0),
  physicalCash: 187500,
  upiBalance: 25000,
);

final _closedState = DayClosureState(
  phase: DayClosurePhase.closed,
  businessDate: '2026-08-06',
  closureDetail: DayClosureDetail(
    closureId: 'cl1',
    businessDate: '2026-08-06',
    openingBalance: 250000,
    collections: 187500,
    loansIssued: 120000,
    expenses: 4750,
    depositsInvestor: 0,
    withdrawalsInvestor: 0,
    adjustments: 500,
    closingBalance: 312750,
    difference: 0,
    remarks: 'Closed on time.',
    closedByName: 'Karri Siri Manikanta Reddy',
    closedAt: DateTime(2026, 8, 6, 21, 0),
    reopenedAt: DateTime(2026, 8, 6, 22, 0),
    reopenReason: 'Owner requested a correction to the collections figure.',
  ),
);

const _reopenedState = DayClosureState(
  phase: DayClosurePhase.reopened,
  businessDate: '2026-08-06',
);

/// The real ui_translations rows this screen was wired against (migration
/// 20260808050000 + reused earlier keys).
const _ow011TeluguTranslations = <String, Map<String, String>>{
  'day_closure': {'English': 'Day Closure', 'Telugu': 'దిన ముగింపు'},
  'expense': {'English': 'Expense', 'Telugu': 'ఖర్చు'},
  'day_closure_cannot_start': {'English': 'Day Closure Cannot Start', 'Telugu': 'దిన ముగింపు ప్రారంభం కాదు'},
  'items_must_be_resolved_note': {
    'English': 'The following items must be resolved before Cash Verification can open.',
    'Telugu': 'నగదు ధృవీకరణ తెరవడానికి ముందు ఈ క్రింది అంశాలు పరిష్కరించాలి.',
  },
  'items_outstanding_note': {'English': '{count} item(s) outstanding', 'Telugu': '{count} అంశం(లు) బాకీ ఉన్నాయి'},
  'resolve': {'English': 'Resolve', 'Telugu': 'పరిష్కరించండి'},
  'warnings_may_proceed': {'English': 'Warnings (May Proceed)', 'Telugu': 'హెచ్చరికలు (కొనసాగవచ్చు)'},
  'items_count_note': {'English': '{count} item(s)', 'Telugu': '{count} అంశం(లు)'},
  'cash_verification': {'English': 'Cash Verification', 'Telugu': 'నగదు ధృవీకరణ'},
  'enter_physical_count_note': {
    'English': 'Enter the physical count — actual on-hand — for each payment method.',
    'Telugu': 'ప్రతి చెల్లింపు పద్ధతికి భౌతిక లెక్క — వాస్తవంగా చేతిలో ఉన్నది — నమోదు చేయండి.',
  },
  'physical_cash': {'English': 'Physical Cash', 'Telugu': 'భౌతిక నగదు'},
  'upi_balance': {'English': 'UPI Balance', 'Telugu': 'UPI నిల్వ'},
  'bank_balance': {'English': 'Bank Balance', 'Telugu': 'బ్యాంక్ నిల్వ'},
  'cheque_balance': {'English': 'Cheque Balance', 'Telugu': 'చెక్ నిల్వ'},
  'system_expected_computed': {'English': 'System Expected (Computed)', 'Telugu': 'సిస్టమ్ ఆశించినది (లెక్కించబడింది)'},
  'expected_cash': {'English': 'Expected Cash', 'Telugu': 'ఆశించిన నగదు'},
  'expected_upi': {'English': 'Expected UPI', 'Telugu': 'ఆశించిన UPI'},
  'expected_bank': {'English': 'Expected Bank', 'Telugu': 'ఆశించిన బ్యాంక్'},
  'expected_cheque': {'English': 'Expected Cheque', 'Telugu': 'ఆశించిన చెక్'},
  'recalculate': {'English': 'Recalculate', 'Telugu': 'తిరిగి లెక్కించండి'},
  'difference_found': {'English': 'Difference Found', 'Telugu': 'తేడా కనుగొనబడింది'},
  'overall_difference_note': {'English': 'Overall Difference: {amount}', 'Telugu': 'మొత్తం తేడా: {amount}'},
  'difference_details': {'English': 'Difference Details', 'Telugu': 'తేడా వివరాలు'},
  'expected_actual_note': {'English': 'Expected {expected} · Actual {actual}', 'Telugu': 'ఆశించినది {expected} · వాస్తవం {actual}'},
  'owner_must_resolve_note': {
    'English': 'Owner must resolve — correct a mis-entered Actual figure above, or record a Short/Excess adjustment, then Recalculate.',
    'Telugu': 'యజమాని పరిష్కరించాలి — పైన తప్పుగా నమోదైన వాస్తవ సంఖ్యను సరిచేయండి, లేదా తక్కువ/అధిక సర్దుబాటును నమోదు చేసి, తిరిగి లెక్కించండి.',
  },
  'adjustments_recorded_session': {'English': 'Adjustments Recorded This Session', 'Telugu': 'ఈ సెషన్‌లో నమోదు చేసిన సర్దుబాట్లు'},
  'record_short_excess': {'English': 'Record Short / Excess', 'Telugu': 'తక్కువ / అధికం నమోదు చేయండి'},
  'opening_balance': {'English': 'Opening Balance', 'Telugu': 'ప్రారంభ నిల్వ'},
  'collections': {'English': 'Collections', 'Telugu': 'వసూళ్లు'},
  'adjustments': {'English': 'Adjustments', 'Telugu': 'సర్దుబాట్లు'},
  'closing_balance_label': {'English': 'Closing Balance', 'Telugu': 'ముగింపు నిల్వ'},
  'difference': {'English': 'Difference', 'Telugu': 'తేడా'},
  'balanced': {'English': 'Balanced', 'Telugu': 'సరిపోయింది'},
  'remarks_optional': {'English': 'Remarks (Optional)', 'Telugu': 'వ్యాఖ్యలు (ఐచ్ఛికం)'},
  'confirm_close_business_day': {'English': 'Confirm — Close Business Day', 'Telugu': 'నిర్ధారించండి — వ్యాపార దినం మూసివేయండి'},
  'business_day_closed': {'English': 'Business Day Closed', 'Telugu': 'వ్యాపార దినం మూసివేయబడింది'},
  'closed_by_note': {'English': '{date} · Closed by {name}', 'Telugu': '{date} · {name} మూసివేసారు'},
  'loans_issued': {'English': 'Loans Issued', 'Telugu': 'జారీ చేసిన రుణాలు'},
  'expenses': {'English': 'Expenses', 'Telugu': 'ఖర్చులు'},
  'deposits_investor': {'English': 'Deposits (Investor)', 'Telugu': 'జమలు (పెట్టుబడిదారు)'},
  'withdrawals_investor': {'English': 'Withdrawals (Investor)', 'Telugu': 'ఉపసంహరణలు (పెట్టుబడిదారు)'},
  'remarks_colon_note': {'English': 'Remarks: {remarks}', 'Telugu': 'వ్యాఖ్యలు: {remarks}'},
  'reopened_reason_note': {'English': 'Reopened {at} — Reason: {reason}', 'Telugu': '{at} తిరిగి తెరవబడింది — కారణం: {reason}'},
  'reopen_closed_day': {'English': 'Reopen Closed Day', 'Telugu': 'మూసివేసిన దినాన్ని తిరిగి తెరవండి'},
  'day_reopened': {'English': 'Day Reopened', 'Telugu': 'దినం తిరిగి తెరవబడింది'},
  'reopened_awaiting_note': {
    'English': 'Only new adjustment entries dated to this business day are permitted. Existing Collections, Loans, and Expenses for this date cannot be edited. Once adjustments are entered, run Close Again to re-close.',
    'Telugu': 'ఈ వ్యాపార దినానికి కొత్త సర్దుబాటు ఎంట్రీలు మాత్రమే అనుమతించబడతాయి. ఈ తేదీకి ఉన్న వసూళ్లు, రుణాలు, ఖర్చులను మార్చలేరు. సర్దుబాట్లు నమోదు చేసిన తర్వాత, మళ్లీ మూసివేయడానికి "మళ్లీ మూసివేయండి" నొక్కండి.',
  },
  'close_again': {'English': 'Close Again', 'Telugu': 'మళ్లీ మూసివేయండి'},
};

void main() {
  Widget screen() =>
      const DayClosureScreen(businessId: 'b1', businessDate: '2026-08-07');

  for (final scale in kManaTextScales) {
    testWidgets('OW-011 blocked (S1) survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        screen(),
        textScale: scale,
        overrides: [dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(_blockedState))],
      );
      expectNoLayoutFault(tester, 'OW-011 blocked at ${scale}x');
    });

    testWidgets('OW-011 blocked (S1) survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        screen(),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow011TeluguTranslations,
        overrides: [dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(_blockedState))],
      );
      expectNoLayoutFault(tester, 'OW-011 blocked at ${scale}x in Telugu');
    });

    testWidgets('OW-011 difference found (S3) survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        screen(),
        textScale: scale,
        overrides: [dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(_differenceFoundState))],
      );
      expectNoLayoutFault(tester, 'OW-011 difference found at ${scale}x');
    });

    testWidgets('OW-011 difference found (S3) survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        screen(),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow011TeluguTranslations,
        overrides: [dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(_differenceFoundState))],
      );
      expectNoLayoutFault(tester, 'OW-011 difference found at ${scale}x in Telugu');
    });

    testWidgets('OW-011 closed receipt (S5) survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        screen(),
        textScale: scale,
        overrides: [dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(_closedState))],
      );
      expectNoLayoutFault(tester, 'OW-011 closed receipt at ${scale}x');
    });

    testWidgets('OW-011 closed receipt (S5) survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        screen(),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow011TeluguTranslations,
        overrides: [dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(_closedState))],
      );
      expectNoLayoutFault(tester, 'OW-011 closed receipt at ${scale}x in Telugu');
    });
  }

  // Lighter single-scale smoke coverage for the remaining phases (S2, S4,
  // S6) — same translation keys/patterns already exercised above, just
  // fewer distinct text combinations to prove.
  for (final phase in [
    ('cash verification (S2)', _cashVerificationState),
    ('final review (S4)', _finalReviewState),
    ('reopened (S6)', _reopenedState),
  ]) {
    testWidgets('OW-011 ${phase.$1} survives text scale 2.0x', (tester) async {
      await pumpManaScreen(
        tester,
        screen(),
        textScale: 2.0,
        overrides: [dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(phase.$2))],
      );
      expectNoLayoutFault(tester, 'OW-011 ${phase.$1} at 2.0x');
    });

    testWidgets('OW-011 ${phase.$1} survives text scale 2.0x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        screen(),
        textScale: 2.0,
        language: ManaLanguage.telugu,
        translations: _ow011TeluguTranslations,
        overrides: [dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(phase.$2))],
      );
      expectNoLayoutFault(tester, 'OW-011 ${phase.$1} at 2.0x in Telugu');
    });
  }

  testWidgets('OW-011 shows the blocking issues', (tester) async {
    await pumpManaScreen(
      tester,
      screen(),
      overrides: [dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(_blockedState))],
    );
    expect(find.textContaining('Pending Collections'), findsOneWidget);
  });
  // The Reopen dialog. Every phase body of OW-011 was already covered, but
  // the dialog on top of the closed phase was not: showDialog content is a
  // separate route with its own constraints, and an AlertDialog does not
  // scroll its content. Reopening a closed day is a supervised, auditable
  // action -- the reason field is the whole point of the dialog.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('OW-011 reopen dialog survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          const DayClosureScreen(businessId: 'b1', businessDate: '2026-08-07'),
          textScale: scale,
          language: lang,
          translations: lang == ManaLanguage.telugu ? _ow011TeluguTranslations : null,
          overrides: [
            dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(_closedState)),
          ],
        );
        // The receipt is a ListView and the button sits at its foot, so it is
        // not built until it is scrolled to. A plain find would report it
        // missing -- which is its own small lesson about what a widget test
        // has actually laid out.
        await tester.scrollUntilVisible(
          find.byType(OutlinedButton),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(OutlinedButton).first, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'dialog did not open -- a green result here would prove nothing');
        expectNoLayoutFault(tester, 'OW-011 reopen dialog at ${scale}x$tag');
      });
    }
  }
  // Record Short / Excess. A dialog on the differenceFound phase, holding a
  // dropdown -- and a dropdown inside a dialog is the narrowest place one can
  // sit. This is where the Owner names what a cash difference was.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('OW-011 adjustment dialog survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          const DayClosureScreen(businessId: 'b1', businessDate: '2026-08-07'),
          textScale: scale,
          language: lang,
          translations: lang == ManaLanguage.telugu ? _ow011TeluguTranslations : null,
          overrides: [
            dayClosureProvider
                .overrideWith(() => _SeededDayClosureNotifier(_differenceFoundState)),
          ],
        );
        await tester.pumpAndSettle();

        // Below the fold of a lazy list, so it is not built until scrolled to
        // -- the same trap as the reopen button above.
        await tester.scrollUntilVisible(
          find.byType(OutlinedButton),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(OutlinedButton).first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'adjustment dialog did not open');
        expectNoLayoutFault(tester, 'OW-011 adjustment dialog at ${scale}x$tag');
      });
    }
  }
}
