import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_009_daily_record_book.dart';
import 'package:mana_line/features/owner_workspace/state/record_book_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

final _row1 = DayLedgerRow(
  businessDate: DateTime(2026, 8, 7),
  openingBalance: 250000,
  totalCollections: 187500,
  totalLoanDistribution: 120000,
  investorDeposits: 50000,
  investorWithdrawals: 0,
  totalExpenses: 4750,
  chetiPaid: 2000,
  chetiReceived: 0,
  shortAmount: 0,
  excessAmount: 250,
  closingBalance: 312750,
  status: 'Open',
  penaltyCollected: 500,
);

final _row2 = DayLedgerRow(
  businessDate: DateTime(2026, 8, 6),
  openingBalance: 200000,
  totalCollections: 150000,
  totalLoanDistribution: 0,
  investorDeposits: 0,
  investorWithdrawals: 0,
  totalExpenses: 3000,
  shortAmount: 100,
  excessAmount: 0,
  closingBalance: 250000,
  status: 'Closed',
  remarks: 'Day closed on time, no discrepancies.',
);

final _dayDetail = DayDetail(
  ledger: _row1,
  collections: [
    DayDetailEntry(
      id: 'c1',
      label: 'Venkata Subrahmanyam — RCT-20260807-a1b2c3',
      amount: 125000,
      timestamp: DateTime(2026, 8, 7, 10, 30),
      isCorrection: true,
      sourceLoanId: 'loan-1',
    ),
  ],
  expenses: [
    DayDetailEntry(id: 'e1', label: 'Fuel', amount: 4750, timestamp: DateTime(2026, 8, 7, 9, 0)),
  ],
  auditLog: [
    AuditLogEntry(
      auditId: 'a1',
      actionType: 'Day Reopened',
      entityType: 'day_ledger',
      entityId: '2026-08-07',
      entryTimestamp: DateTime(2026, 8, 7, 11, 0),
    ),
  ],
);

class _SeededRecordBookNotifier extends RecordBookNotifier {
  @override
  RecordBookState build() => RecordBookState(
        rows: [_row1, _row2],
        // The same two days the rows carry. In production both come from one
        // app.active_account_dates call, so they cannot disagree; a seeded
        // state has to say so explicitly or the date picker opens empty.
        activeDates: {'2026-08-07', '2026-08-06'},
        selectedDate: _row1.businessDate,
        dayDetail: _dayDetail,
      );

  @override
  Future<void> load(String businessId, {DateTime? dateFrom, DateTime? dateTo, String? status}) async {}

  @override
  Future<void> openDayDetails(String businessId, DateTime businessDate) async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260808030000 + reused earlier keys).
const _ow009TeluguTranslations = <String, Map<String, String>>{
  'daily_record_book': {'English': 'Daily Record Book', 'Telugu': 'రోజువారీ రికార్డు పుస్తకం'},
  'filter_by_status': {'English': 'Filter by status', 'Telugu': 'స్థితి ద్వారా వడపోత'},
  'all': {'English': 'All', 'Telugu': 'అన్నీ'},
  'open': {'English': 'Open', 'Telugu': 'తెరిచి ఉంది'},
  'closed': {'English': 'Closed', 'Telugu': 'మూసివేయబడింది'},
  'recent_deletes': {'English': 'Recent Deletes', 'Telugu': 'ఇటీవలి తొలగింపులు'},
  'opening_bf': {'English': 'Opening (BF)', 'Telugu': 'ప్రారంభ (BF)'},
  'collections': {'English': 'Collections', 'Telugu': 'వసూళ్లు'},
  'penalty_collected': {'English': 'Penalty Collected', 'Telugu': 'జరిమానా వసూలు చేయబడింది'},
  'loan_dist': {'English': 'Loan Dist.', 'Telugu': 'రుణ పంపిణీ'},
  'investor_dep': {'English': 'Investor Dep.', 'Telugu': 'పెట్టుబడిదారు జమ'},
  'investor_wd': {'English': 'Investor W/D', 'Telugu': 'పెట్టుబడిదారు ఉపసంహరణ'},
  'expenses': {'English': 'Expenses', 'Telugu': 'ఖర్చులు'},
  'cheti_paid': {'English': 'Cheti Paid', 'Telugu': 'చేతి చెల్లించినది'},
  'cheti_received': {'English': 'Cheti Received', 'Telugu': 'చేతి అందుకున్నది'},
  'short': {'English': 'Short', 'Telugu': 'తక్కువ'},
  'excess': {'English': 'Excess', 'Telugu': 'అధికం'},
  'difference': {'English': 'Difference', 'Telugu': 'తేడా'},
  'closing': {'English': 'Closing', 'Telugu': 'ముగింపు'},
  'loans': {'English': 'Loans', 'Telugu': 'రుణాలు'},
  'deposits': {'English': 'Deposits', 'Telugu': 'జమలు'},
  'withdrawals': {'English': 'Withdrawals', 'Telugu': 'ఉపసంహరణలు'},
  'adjustments': {'English': 'Adjustments', 'Telugu': 'సర్దుబాట్లు'},
  'audit': {'English': 'Audit', 'Telugu': 'ఆడిట్'},
  'timeline': {'English': 'Timeline', 'Telugu': 'కాలక్రమం'},
  'no_expenses_this_day': {'English': 'No expenses this day.', 'Telugu': 'ఈ రోజు ఖర్చులు లేవు.'},
  'remarks_optional_freeform_note': {'English': 'Remarks (optional, freeform — BR-097)', 'Telugu': 'వ్యాఖ్యలు (ఐచ్ఛికం, స్వేచ్ఛా వచనం)'},
  'save': {'English': 'Save', 'Telugu': 'సేవ్ చేయండి'},
  'correction': {'English': 'Correction', 'Telugu': 'సరిదిద్దుబాటు'},
  'delete': {'English': 'Delete', 'Telugu': 'తొలగించండి'},
};

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('OW-009 Daily Record Book list survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const DailyRecordBookScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [recordBookProvider.overrideWith(_SeededRecordBookNotifier.new)],
      );
      expectNoLayoutFault(tester, 'OW-009 list at ${scale}x');
    });

    testWidgets('OW-009 Daily Record Book list survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const DailyRecordBookScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow009TeluguTranslations,
        overrides: [recordBookProvider.overrideWith(_SeededRecordBookNotifier.new)],
      );
      expectNoLayoutFault(tester, 'OW-009 list at ${scale}x in Telugu');
    });

    testWidgets('OW-009 day details sheet survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const DailyRecordBookScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [recordBookProvider.overrideWith(_SeededRecordBookNotifier.new)],
      );
      // LONG PRESS below, since 2026-09-17: tapping the date opens the
      // calendar now, and the day details moved to a long press at the
      // Owner's request. These tests went on tapping and would have gone on
      // passing -- against a Flutter date picker instead of the sheet they
      // are named for.
      //
      // The comment lives ABOVE this line, not beside the gesture: the
      // silent-tap guard looks exactly 8 lines back for an ensureVisible,
      // and five lines of prose in that gap put a real tap out of its reach.
      final dateText = find.textContaining('07 Aug 2026').first;
      await tester.ensureVisible(dateText);
      await tester.pumpAndSettle();
      await tester.longPress(dateText);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expectNoLayoutFault(tester, 'OW-009 day details at ${scale}x');
    });

    testWidgets('OW-009 day details sheet survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const DailyRecordBookScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow009TeluguTranslations,
        overrides: [recordBookProvider.overrideWith(_SeededRecordBookNotifier.new)],
      );
      // LONG PRESS below, since 2026-09-17: tapping the date opens the
      // calendar now, and the day details moved to a long press at the
      // Owner's request. These tests went on tapping and would have gone on
      // passing -- against a Flutter date picker instead of the sheet they
      // are named for.
      //
      // The comment lives ABOVE this line, not beside the gesture: the
      // silent-tap guard looks exactly 8 lines back for an ensureVisible,
      // and five lines of prose in that gap put a real tap out of its reach.
      final dateText = find.textContaining('07 Aug 2026').first;
      await tester.ensureVisible(dateText);
      await tester.pumpAndSettle();
      await tester.longPress(dateText);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expectNoLayoutFault(tester, 'OW-009 day details at ${scale}x in Telugu');
    });
  }

  // The day-details sheet is eight tabs deep and TabBarView lays out only the
  // visible page, so the two tests above proved Collections and nothing else.
  // The remaining seven are walked here.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      for (var i = 1; i < 8; i++) {
        testWidgets('OW-009 day details tab $i survives text scale ${scale}x$tag',
            (tester) async {
          await pumpManaScreen(
            tester,
            const DailyRecordBookScreen(businessId: 'b1'),
            textScale: scale,
            language: lang,
            translations: lang == ManaLanguage.telugu ? _ow009TeluguTranslations : null,
            overrides: [recordBookProvider.overrideWith(_SeededRecordBookNotifier.new)],
          );
          // LONG PRESS below, since 2026-09-17: tapping the date opens the
      // calendar now, and the day details moved to a long press at the
      // Owner's request. These tests went on tapping and would have gone on
      // passing -- against a Flutter date picker instead of the sheet they
      // are named for.
      //
      // The comment lives ABOVE this line, not beside the gesture: the
      // silent-tap guard looks exactly 8 lines back for an ensureVisible,
      // and five lines of prose in that gap put a real tap out of its reach.
      final dateText = find.textContaining('07 Aug 2026').first;
          await tester.ensureVisible(dateText);
          await tester.pumpAndSettle();
          await tester.longPress(dateText);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          final tabs = find.byType(Tab);
          if (tabs.evaluate().length > i) {
            await tester.tap(tabs.at(i), warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
          expectNoLayoutFault(tester, 'OW-009 day details tab $i at ${scale}x$tag');
        });
      }
    }
  }

  testWidgets('OW-009 shows the ledger rows', (tester) async {
    await pumpManaScreen(
      tester,
      const DailyRecordBookScreen(businessId: 'b1'),
      overrides: [recordBookProvider.overrideWith(_SeededRecordBookNotifier.new)],
    );
    expect(find.textContaining('07 Aug 2026'), findsWidgets);

    // SWIPED TO, since 2026-09-17: "show latest account on top and on swipe
    // up show previous one." One account fills the screen and the previous
    // one is a page turn away, so the second day is not merely below the
    // fold -- PageView has not built it at all.
    //
    // scrollUntilVisible cannot express this. It calls `.single` on the
    // target finder before the page exists, which throws "Bad state: No
    // element" rather than scrolling until it does. A fling on the pager is
    // both the gesture the Owner asked for and the only one that builds it.
    // hitTestable, not plain existence. PageView BUILDS the adjacent page so
    // it can animate to it, so '06 Aug 2026' is in the tree from the first
    // frame -- asserting findsNothing on it fails against correct code, which
    // is what the first version of this test did. What the Owner asked about
    // is what is in front of them, and that is what hitTestable measures.
    expect(find.textContaining('06 Aug 2026').hitTestable(), findsNothing,
        reason: 'the previous day must not already be on screen, or the '
            'swipe below proves nothing');

    // SCROLLED TO. A day is drawn as the two-column account sheet now --
    // credits, debits, both totals and the carried closing -- so two days no
    // longer fit one screen at 1.0x. That is the format the Owner asked for,
    // and "swipe up show previous one" is what this scroll is.
    //
    // No `.first` on the target: it is evaluated eagerly and throws "Bad
    // state: No element" on a finder for something not yet built, which is
    // the whole reason this call is here.
    await tester.scrollUntilVisible(
      find.textContaining('06 Aug 2026'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('06 Aug 2026'), findsWidgets);
  });

  testWidgets('OW-009 offers only the days it holds', (tester) async {
    // "tap on date (beside BF) opens calendar ... and only show dates that
    // are actively submitted account dates." The seeded book holds 7 and 6
    // August; every other August day must be unselectable.
    await pumpManaScreen(
      tester,
      const DailyRecordBookScreen(businessId: 'b1'),
      overrides: [recordBookProvider.overrideWith(_SeededRecordBookNotifier.new)],
    );

    await tester.tap(find.textContaining('07 Aug 2026').first);
    await tester.pumpAndSettle();

    // A day the book does not hold. Disabled, not absent -- the calendar
    // draws the whole month either way.
    final fifth = find.descendant(
        of: find.byType(DatePickerDialog), matching: find.text('5'));
    expect(fifth, findsOneWidget, reason: 'the calendar opened');
    final enabled = tester
        .widget<Semantics>(find
            .ancestor(of: fifth, matching: find.byType(Semantics))
            .first)
        .properties
        .enabled;
    expect(enabled, isFalse,
        reason: '5 Aug has no account, so it must not be selectable');
  });
}
