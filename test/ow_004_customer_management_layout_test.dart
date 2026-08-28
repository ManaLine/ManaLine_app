import 'package:flutter/material.dart';
import 'package:mana_line/design/components/mana_filter_rail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_004_customer_management.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededCustomerListNotifier extends CustomerListNotifier {
  _SeededCustomerListNotifier(this._seed);
  final CustomerListState _seed;

  @override
  CustomerListState build() => _seed;

  @override
  Future<void> load(String businessId) async {}
}

/// The real ui_translations rows this screen was wired against (migrations
/// 20260807185304 / 20260807185710 + reused earlier keys) — the landing
/// list view only (search, filters, customer rows), not the tabbed
/// Customer Profile drill-in.
const _ow004TeluguTranslations = <String, Map<String, String>>{
  'customer_management': {'English': 'Customers', 'Telugu': 'కస్టమర్లు'},
  'add_customer': {'English': 'Add Customer', 'Telugu': 'కస్టమర్ జోడించండి'},
  'existing_customers': {'English': 'Existing Customers', 'Telugu': 'ఇప్పటికే ఉన్న కస్టమర్లు'},
  'pre_existing_customer': {'English': 'Pre-Existing Customer', 'Telugu': 'ముందుగా ఉన్న కస్టమర్'},
  'search_by_name_mlid_phone': {'English': 'Search by name, MLID, or phone', 'Telugu': 'పేరు, MLID, లేదా ఫోన్ ద్వారా శోధించండి'},
  'all': {'English': 'All', 'Telugu': 'అన్నీ'},
  'active': {'English': 'Active', 'Telugu': 'యాక్టివ్'},
  'suspended': {'English': 'Suspended', 'Telugu': 'సస్పెండ్ చేయబడింది'},
  'removed': {'English': 'Removed', 'Telugu': 'తీసివేయబడింది'},
  'all_villages': {'English': 'All Villages', 'Telugu': 'అన్ని గ్రామాలు'},
  'village': {'English': 'Village', 'Telugu': 'గ్రామం'},
  'due_note': {'English': 'Due {amount}', 'Telugu': '{amount} బకాయి'},
  'sorted_by_note_customers': {
    'English': "Sorted by: village → highest outstanding → today's due → name",
    'Telugu': 'క్రమం: గ్రామం → అత్యధిక బాకీ → నేటి బకాయి → పేరు',
  },
  'no_customers_match_view': {'English': 'No customers match this view.', 'Telugu': 'ఈ వీక్షణకు సరిపోలే కస్టమర్లు లేరు.'},
};

void main() {
  final customers = [
    CustomerSummary(
      customerId: 'c1',
      fullName: 'Nagabhushanam Venkata Subba Reddy',
      fatherHusbandName: 'Venkata Subba Reddy',
      village: 'Srikalahasti — Uranduru Colony',
      phoneNumber: '9493509919',
      mlid: 'MLCU0000012345',
      activeLoanCount: 1,
      todaysDue: 1500,
      totalLoanAmount: 120000,
      outstandingBalance: 84500,
      lineRepaymentIndex: 12,
      customerStatus: 'Active',
      membershipStatus: 'Active',
    ),
    CustomerSummary(
      customerId: 'c2',
      fullName: 'Chalasani Ramana',
      fatherHusbandName: 'Chalasani Rao',
      village: 'Puttur',
      phoneNumber: '9876543210',
      mlid: 'MLCU0000012346',
      activeLoanCount: 0,
      todaysDue: 0,
      outstandingBalance: 0,
      lineRepaymentIndex: 0,
      customerStatus: 'Active',
      membershipStatus: 'Suspended',
    ),
  ];
  final seed = CustomerListState(customers: customers);

  for (final scale in kManaTextScales) {
    testWidgets('OW-004 Customer Management survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const CustomerManagementScreen(businessId: 'b1'),
        location: '/ow-004',
        textScale: scale,
        overrides: [customerListProvider.overrideWith(() => _SeededCustomerListNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-004 Customer Management at ${scale}x');
    });

    testWidgets('OW-004 Customer Management survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const CustomerManagementScreen(businessId: 'b1'),
        location: '/ow-004',
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow004TeluguTranslations,
        overrides: [customerListProvider.overrideWith(() => _SeededCustomerListNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-004 Customer Management at ${scale}x in Telugu');
    });
  }

  testWidgets('OW-004 shows the customers', (tester) async {
    await pumpManaScreen(
      tester,
      const CustomerManagementScreen(businessId: 'b1'),
      overrides: [customerListProvider.overrideWith(() => _SeededCustomerListNotifier(seed))],
    );
    expect(find.textContaining('Nagabhushanam'), findsWidgets);
  });
  testWidgets('the row shows what was lent and what is left, both labelled',
      (tester) async {
    // It used to lead with the outstanding balance and end with "Today's Due",
    // which put the same-looking number under two names across two screens
    // and never said how big the loan was.
    await pumpManaScreen(
      tester,
      const CustomerManagementScreen(businessId: 'b1'),
      overrides: [customerListProvider.overrideWith(() => _SeededCustomerListNotifier(seed))],
    );

    // Short labels on purpose: "Loan Amount" and "Balance" pushed both
    // figures into an ellipsis on a 360dp row. The figures must appear WHOLE
    // -- a truncated rupee amount is a wrong number that looks right.
    expect(find.textContaining('T.L.A. '), findsWidgets,
        reason: 'the total lent must be on the row, and named');
    expect(find.textContaining('1,20,000'), findsWidgets,
        reason: 'the whole figure, not an ellipsis');
    expect(find.textContaining('R. Bal '), findsWidgets,
        reason: 'what is still owed must be on the row, and named');
    expect(find.textContaining('84,500'), findsWidgets,
        reason: 'the balance in full too');
    expect(find.textContaining("Today's Due"), findsNothing,
        reason: "today's due belongs to the round, not to this list");
  });
  testWidgets('one filter rail: order, village, sort by, status', (tester) async {
    // The round and this list are the same book asked different questions,
    // and they had drifted into different shapes -- this one kept its sort as
    // a line of grey text nobody could change.
    await pumpManaScreen(
      tester,
      const CustomerManagementScreen(businessId: 'b1'),
      overrides: [customerListProvider.overrideWith(() => _SeededCustomerListNotifier(seed))],
    );
    await tester.pumpAndSettle();

    expect(find.byType(ManaFilterRail), findsOneWidget);
    // The four the Owner asked for, by name. They scroll rather than wrap:
    // four labelled dropdowns across 360dp is 84dp each before a single
    // Telugu label is measured.
    expect(find.byType(ManaFilterChip<bool>), findsOneWidget,
        reason: 'sort order');
    expect(find.byType(ManaFilterChip<String?>), findsNWidgets(2),
        reason: 'village and status');
    expect(find.byType(ManaFilterChip<CustomerSort>), findsOneWidget,
        reason: 'sort by');
    expect(find.textContaining('Sorted by:'), findsNothing,
        reason: 'the fixed sort note is replaced by a control');
  });

  testWidgets('search is an icon, not a box in the header', (tester) async {
    await pumpManaScreen(
      tester,
      const CustomerManagementScreen(businessId: 'b1'),
      // At its own route, because the header's three actions are installed by
      // route prefix. Pumped at '/' this screen renders a bar the app never
      // draws.
      location: '/ow-004',
      overrides: [customerListProvider.overrideWith(() => _SeededCustomerListNotifier(seed))],
    );
    await tester.pumpAndSettle();

    // Exactly one. This screen used to carry its own search action opening
    // Universal Search -- the same destination the header's now opens -- so
    // it drew the magnifier twice side by side.
    expect(find.byIcon(Icons.search), findsOneWidget,
        reason: "search is the header's, and only the header's");
    // The header search FIELD is gone; the only TextFields left belong to
    // sheets that are not open.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byType(TextField)),
      findsNothing,
      reason: 'a search box took a third of the header',
    );
  });
}
