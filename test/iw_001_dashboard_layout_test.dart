import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/investor_workspace/screens/iw_001_investor_home_dashboard.dart';
import 'package:mana_line/features/investor_workspace/state/investor_dashboard_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededInvestorDashboardNotifier extends InvestorDashboardNotifier {
  _SeededInvestorDashboardNotifier(this._seed);
  final InvestorDashboardData _seed;

  @override
  Future<InvestorDashboardData> build() async => _seed;

  @override
  Future<void> load(String businessId) async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260807172001 + reused earlier keys) — same reasoning as OW-001/AG-001/
/// CW-001.
const _iw001TeluguTranslations = <String, Map<String, String>>{
  'my_investments': {'English': 'My Investments', 'Telugu': 'నా పెట్టుబడులు'},
  'request_withdrawal': {'English': 'Request Withdrawal', 'Telugu': 'ఉపసంహరణ అభ్యర్థించండి'},
  'my_account': {'English': 'My Account', 'Telugu': 'నా ఖాతా'},
  'my_profile': {'English': 'My Profile', 'Telugu': 'నా ప్రొఫైల్'},
  'find_a_business': {'English': 'Find A Business', 'Telugu': 'వ్యాపారాన్ని కనుగొనండి'},
  'could_not_load_dashboard': {'English': 'Could Not Load Dashboard', 'Telugu': 'డాష్‌బోర్డ్ లోడ్ కాలేదు'},
  'retry': {'English': 'Retry', 'Telugu': 'మళ్ళీ ప్రయత్నించండి'},
  'notifications': {'English': 'Notifications', 'Telugu': 'నోటిఫికేషన్‌లు'},
  'switch_business': {'English': 'Switch Business', 'Telugu': 'వ్యాపారం మార్చండి'},
  'no_notifications_yet': {'English': 'No notifications yet.', 'Telugu': 'ఇంకా నోటిఫికేషన్‌లు లేవు.'},
  'my_summary': {'English': 'My Summary', 'Telugu': 'నా సారాంశం'},
  'total_investment_balance': {'English': 'Total Investment Balance', 'Telugu': 'మొత్తం పెట్టుబడి నిల్వ'},
  'active_investments': {'English': 'Active Investments', 'Telugu': 'యాక్టివ్ పెట్టుబడులు'},
  'interest_accrued': {'English': 'Interest Accrued', 'Telugu': 'పోగుపడిన వడ్డీ'},
  'interest_paid_to_date': {'English': 'Interest Paid to Date', 'Telugu': 'ఇప్పటివరకు చెల్లించిన వడ్డీ'},
  'pending_withdrawal_requests': {'English': 'Pending Withdrawal Requests', 'Telugu': 'పెండింగ్ ఉపసంహరణ అభ్యర్థనలు'},
  'pending_interest_payment_requests': {
    'English': 'Pending Interest Payment Requests',
    'Telugu': 'పెండింగ్ వడ్డీ చెల్లింపు అభ్యర్థనలు',
  },
  'quick_actions': {'English': 'Quick Actions', 'Telugu': 'త్వరిత చర్యలు'},
  'my_profile_memberships': {'English': 'My Profile / Memberships', 'Telugu': 'నా ప్రొఫైల్ / సభ్యత్వాలు'},
  'no_business_memberships_yet': {'English': 'No Business Memberships Yet', 'Telugu': 'ఇంకా వ్యాపార సభ్యత్వాలు లేవు'},
  'find_investor_membership_note': {
    'English': 'Find a Business to request Investor membership. Once the Owner approves, it will appear here.',
    'Telugu': 'ఇన్వెస్టర్ సభ్యత్వం కోసం అభ్యర్థించడానికి ఒక వ్యాపారాన్ని కనుగొనండి. యజమాని ఆమోదించిన తర్వాత, అది ఇక్కడ కనిపిస్తుంది.',
  },
};

void main() {
  final seed = InvestorDashboardData(
    hasActiveMembership: true,
    businessName: 'Sri Venkateswara Rural Finance and Chit Fund Society',
    investorName: 'Chalasani Venkata Ramana Murthy',
    investorVerified: true,
    totalInvestmentBalance: 500000,
    activeInvestmentCount: 3,
    totalInterestAccrued: 45000,
    interestPaidToDate: 30000,
    pendingWithdrawalRequests: 1,
    pendingInterestPaymentRequests: 0,
  );

  for (final scale in kManaTextScales) {
    testWidgets('IW-001 Investor Dashboard survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const InvestorHomeDashboardScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [investorDashboardProvider.overrideWith(() => _SeededInvestorDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'IW-001 Investor Dashboard at ${scale}x');
    });

    testWidgets('IW-001 Investor Dashboard survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const InvestorHomeDashboardScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _iw001TeluguTranslations,
        overrides: [investorDashboardProvider.overrideWith(() => _SeededInvestorDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'IW-001 Investor Dashboard at ${scale}x in Telugu');
    });
  }

  testWidgets('IW-001 shows the investor name', (tester) async {
    await pumpManaScreen(
      tester,
      const InvestorHomeDashboardScreen(businessId: 'b1'),
      overrides: [investorDashboardProvider.overrideWith(() => _SeededInvestorDashboardNotifier(seed))],
    );
    expect(find.textContaining('Chalasani'), findsWidgets);
  });
}
