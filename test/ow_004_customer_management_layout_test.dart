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
  'customer_management': {'English': 'Customer Management', 'Telugu': 'కస్టమర్ నిర్వహణ'},
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
    'English': "Sorted by: highest outstanding → penalty → grace period → today's due → village → name",
    'Telugu': 'క్రమం: అత్యధిక బాకీ → జరిమానా → గ్రేస్ పీరియడ్ → నేటి బకాయి → గ్రామం → పేరు',
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
        textScale: scale,
        overrides: [customerListProvider.overrideWith(() => _SeededCustomerListNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-004 Customer Management at ${scale}x');
    });

    testWidgets('OW-004 Customer Management survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const CustomerManagementScreen(businessId: 'b1'),
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
}
