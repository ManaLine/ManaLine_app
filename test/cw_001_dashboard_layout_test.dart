import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/customer_workspace/screens/cw_001_customer_home_dashboard.dart';
import 'package:mana_line/features/customer_workspace/state/customer_dashboard_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededCustomerDashboardNotifier extends CustomerDashboardNotifier {
  _SeededCustomerDashboardNotifier(this._seed);
  final CustomerDashboardData _seed;

  @override
  Future<CustomerDashboardData> build() async => _seed;

  @override
  Future<void> load(String businessId) async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260807171600 + reused earlier keys) — same reasoning as OW-001/AG-001.
const _cw001TeluguTranslations = <String, Map<String, String>>{
  'my_loans': {'English': 'My Loans', 'Telugu': 'నా రుణాలు'},
  'request_new_loan': {'English': 'Request New Loan', 'Telugu': 'కొత్త రుణం అభ్యర్థించండి'},
  'make_a_payment': {'English': 'Make A Payment', 'Telugu': 'చెల్లింపు చేయండి'},
  'my_account': {'English': 'My Account', 'Telugu': 'నా ఖాతా'},
  'my_profile': {'English': 'My Profile', 'Telugu': 'నా ప్రొఫైల్'},
  'find_a_business': {'English': 'Find A Business', 'Telugu': 'వ్యాపారాన్ని కనుగొనండి'},
  'could_not_load_dashboard': {'English': 'Could Not Load Dashboard', 'Telugu': 'డాష్‌బోర్డ్ లోడ్ కాలేదు'},
  'retry': {'English': 'Retry', 'Telugu': 'మళ్ళీ ప్రయత్నించండి'},
  'notifications': {'English': 'Notifications', 'Telugu': 'నోటిఫికేషన్‌లు'},
  'switch_business': {'English': 'Switch Business', 'Telugu': 'వ్యాపారం మార్చండి'},
  'my_summary': {'English': 'My Summary', 'Telugu': 'నా సారాంశం'},
  'active_loans': {'English': 'Active Loans', 'Telugu': 'యాక్టివ్ రుణాలు'},
  'total_outstanding': {'English': 'Total Outstanding', 'Telugu': 'మొత్తం బాకీ'},
  'next_payment_due': {'English': 'Next Payment Due', 'Telugu': 'తదుపరి చెల్లింపు గడువు'},
  'pending_loan_requests': {'English': 'Pending Loan Requests', 'Telugu': 'పెండింగ్ రుణ అభ్యర్థనలు'},
  'pending_online_payments': {'English': 'Pending Online Payments', 'Telugu': 'పెండింగ్ ఆన్‌లైన్ చెల్లింపులు'},
  'quick_actions': {'English': 'Quick Actions', 'Telugu': 'త్వరిత చర్యలు'},
  'my_profile_memberships': {'English': 'My Profile / Memberships', 'Telugu': 'నా ప్రొఫైల్ / సభ్యత్వాలు'},
  'no_business_memberships_yet': {'English': 'No Business Memberships Yet', 'Telugu': 'ఇంకా వ్యాపార సభ్యత్వాలు లేవు'},
  'find_business_membership_note': {
    'English': 'Find a Business to request Customer membership. Once the Owner or Agent approves, it will appear here.',
    'Telugu': 'కస్టమర్ సభ్యత్వం కోసం అభ్యర్థించడానికి ఒక వ్యాపారాన్ని కనుగొనండి. యజమాని లేదా ఏజెంట్ ఆమోదించిన తర్వాత, అది ఇక్కడ కనిపిస్తుంది.',
  },
};

void main() {
  final seed = CustomerDashboardData(
    hasActiveMembership: true,
    businessName: 'Sri Venkateswara Rural Finance and Chit Fund Society',
    customerName: 'Nagabhushanam Venkata Subba Reddy',
    verified: true,
    activeLoansCount: 2,
    totalOutstanding: 84500,
    nextPaymentDueDate: DateTime(2026, 8, 10),
    nextPaymentDueAmount: 1500,
    pendingLoanRequestsCount: 1,
    pendingOnlinePaymentsCount: 0,
  );

  for (final scale in kManaTextScales) {
    testWidgets('CW-001 Customer Dashboard survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const CustomerHomeDashboardScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [customerDashboardProvider.overrideWith(() => _SeededCustomerDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'CW-001 Customer Dashboard at ${scale}x');
    });

    testWidgets('CW-001 Customer Dashboard survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const CustomerHomeDashboardScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _cw001TeluguTranslations,
        overrides: [customerDashboardProvider.overrideWith(() => _SeededCustomerDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'CW-001 Customer Dashboard at ${scale}x in Telugu');
    });
  }

  testWidgets('CW-001 shows the customer name', (tester) async {
    await pumpManaScreen(
      tester,
      const CustomerHomeDashboardScreen(businessId: 'b1'),
      overrides: [customerDashboardProvider.overrideWith(() => _SeededCustomerDashboardNotifier(seed))],
    );
    expect(find.textContaining('Nagabhushanam'), findsWidgets);
  });
}
