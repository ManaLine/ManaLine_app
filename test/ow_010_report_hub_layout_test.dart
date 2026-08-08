import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_010_report_hub.dart';
import 'package:mana_line/features/owner_workspace/state/report_hub_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

final _row1 = RecordBookRow(
  businessDayAccountId: 'bda-1',
  dateFrom: DateTime(2026, 8, 5),
  dateTo: DateTime(2026, 8, 7),
  collectionsTotal: 187500,
  loansGivenTotal: 120000,
  expensesTotal: 4750,
  closingCash: 312750,
  agentBalanceStatus: 'Balanced',
  pendingCustomersCount: 3,
);

final _row2 = RecordBookRow(
  businessDayAccountId: 'bda-2',
  dateFrom: DateTime(2026, 8, 4),
  dateTo: DateTime(2026, 8, 4),
  collectionsTotal: 150000,
  loansGivenTotal: 0,
  expensesTotal: 3000,
  closingCash: 250000,
  agentBalanceStatus: 'Short',
  pendingCustomersCount: 1,
  remarks: 'Short by ₹100, agent acknowledged.',
);

final _monthlySummary = MonthlySummary(
  year: 2026,
  month: 8,
  businessDayAccounts: 7,
  totalCollections: 1250000,
  totalLoansGiven: 350000,
  totalExpenses: 42000,
  pendingCustomers: 5,
  outstandingAmount: 980000,
);

final _monthlyClosing = MonthlyClosing(
  year: 2026,
  month: 7,
  businessDayAccounts: 30,
  collections: 4500000,
  loansGiven: 1200000,
  expenses: 150000,
  netCashMovement: 3150000,
);

final _detail = RecordBookRowDetail(
  row: _row1,
  collections: [ReportHubLineItem(id: 'c1', label: 'Venkata Subrahmanyam', amount: 5000)],
  loans: [ReportHubLineItem(id: 'l1', label: 'Lakshmi Narasimha Rao', amount: 25000)],
  expenses: [ReportHubLineItem(id: 'e1', label: 'Fuel', amount: 750)],
  agentSummary: 'Chalasani Ramana collected ₹187,500 across 12 stops.',
  pendingCustomers: [ReportHubLineItem(id: 'p1', label: 'Karri Siri Manikanta Reddy', amount: 5000)],
  corrections: const [],
  dayClosureDetails: 'Closed on time, no short/excess.',
);

class _SeededReportHubNotifier extends ReportHubNotifier {
  @override
  ReportHubState build() => ReportHubState(
        selectedYear: 2026,
        selectedMonth: 8,
        rows: [_row1, _row2],
        monthlySummary: _monthlySummary,
        monthlyClosing: _monthlyClosing,
        selectedBusinessDayAccountId: _row1.businessDayAccountId,
        detail: _detail,
      );

  @override
  Future<void> loadMonth(String businessId, {int? year, int? month}) async {}

  @override
  Future<void> openRowDetail(String businessId, String businessDayAccountId) async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260808040000 + reused earlier keys).
const _ow010TeluguTranslations = <String, Map<String, String>>{
  'report_hub': {'English': 'Report Hub', 'Telugu': 'నివేదిక కేంద్రం'},
  'august': {'English': 'August', 'Telugu': 'ఆగస్టు'},
  'july': {'English': 'July', 'Telugu': 'జూలై'},
  'business_day_accounts': {'English': 'Business-Day-Accounts', 'Telugu': 'వ్యాపార-దిన-ఖాతాలు'},
  'total_collections': {'English': 'Total Collections', 'Telugu': 'మొత్తం వసూళ్లు'},
  'total_loans_given': {'English': 'Total Loans Given', 'Telugu': 'మొత్తం ఇచ్చిన రుణాలు'},
  'total_expenses': {'English': 'Total Expenses', 'Telugu': 'మొత్తం ఖర్చులు'},
  'pending_customers': {'English': 'Pending Customers', 'Telugu': 'పెండింగ్ కస్టమర్లు'},
  'outstanding_amount': {'English': 'Outstanding Amount', 'Telugu': 'బాకీ మొత్తం'},
  'monthly_closing': {'English': 'Monthly Closing', 'Telugu': 'నెలవారీ ముగింపు'},
  'loans_given': {'English': 'Loans Given', 'Telugu': 'ఇచ్చిన రుణాలు'},
  'collections': {'English': 'Collections', 'Telugu': 'వసూళ్లు'},
  'expenses': {'English': 'Expenses', 'Telugu': 'ఖర్చులు'},
  'net_cash_movement': {'English': 'Net Cash Movement', 'Telugu': 'నికర నగదు కదలిక'},
  'closing_cash': {'English': 'Closing Cash', 'Telugu': 'ముగింపు నగదు'},
  'from_to_date_range_note': {'English': 'From: {from}  To: {to}', 'Telugu': 'నుండి: {from}  వరకు: {to}'},
  'loans': {'English': 'Loans', 'Telugu': 'రుణాలు'},
  'agent_summary': {'English': 'Agent Summary', 'Telugu': 'ఏజెంట్ సారాంశం'},
  'day_closure_details': {'English': 'Day Closure Details', 'Telugu': 'దిన ముగింపు వివరాలు'},
  'corrections': {'English': 'Corrections', 'Telugu': 'సరిదిద్దుబాట్లు'},
  'remarks_optional_freeform_note': {'English': 'Remarks (optional, freeform — BR-097)', 'Telugu': 'వ్యాఖ్యలు (ఐచ్ఛికం, స్వేచ్ఛా వచనం)'},
  'save': {'English': 'Save', 'Telugu': 'సేవ్ చేయండి'},
};

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('OW-010 Report Hub list survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const ReportHubScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [reportHubProvider.overrideWith(_SeededReportHubNotifier.new)],
      );
      expectNoLayoutFault(tester, 'OW-010 list at ${scale}x');
    });

    testWidgets('OW-010 Report Hub list survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const ReportHubScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow010TeluguTranslations,
        overrides: [reportHubProvider.overrideWith(_SeededReportHubNotifier.new)],
      );
      expectNoLayoutFault(tester, 'OW-010 list at ${scale}x in Telugu');
    });

    testWidgets('OW-010 row detail sheet survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const ReportHubScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [reportHubProvider.overrideWith(_SeededReportHubNotifier.new)],
      );
      final dateText = find.byType(InkWell).first;
      await tester.ensureVisible(dateText);
      await tester.pumpAndSettle();
      await tester.tap(dateText);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expectNoLayoutFault(tester, 'OW-010 row detail at ${scale}x');
    });

    testWidgets('OW-010 row detail sheet survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const ReportHubScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow010TeluguTranslations,
        overrides: [reportHubProvider.overrideWith(_SeededReportHubNotifier.new)],
      );
      final dateText = find.byType(InkWell).first;
      await tester.ensureVisible(dateText);
      await tester.pumpAndSettle();
      await tester.tap(dateText);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expectNoLayoutFault(tester, 'OW-010 row detail at ${scale}x in Telugu');
    });
  }

  testWidgets('OW-010 shows the record book rows', (tester) async {
    await pumpManaScreen(
      tester,
      const ReportHubScreen(businessId: 'b1'),
      overrides: [reportHubProvider.overrideWith(_SeededReportHubNotifier.new)],
    );
    expect(find.textContaining('05 Aug'), findsWidgets);
    expect(find.textContaining('04 Aug'), findsWidgets);
  });
}
