import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart';
import 'package:mana_line/features/owner_workspace/state/owner_api_service.dart';
import 'package:mana_line/features/owner_workspace/state/owner_workspace_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// Seeded to a known value with a no-op load() — the real load() reaches
/// Supabase, which is never initialised in a test process. Long business
/// name deliberately, since a business name is data and the header Row
/// around it has already overflowed once for exactly that reason
/// (LR-013's own fix note).
class _SeededOwnerDashboardNotifier extends OwnerDashboardNotifier {
  _SeededOwnerDashboardNotifier(this._seed);
  final OwnerDashboardData _seed;

  @override
  Future<OwnerDashboardData> build() async => _seed;

  @override
  Future<void> load(String businessId) async {}
}

/// The real ui_translations rows this screen was wired against (migrations
/// 0047/0048 + 20260807161236/20260807161614), not the vendored fixture —
/// Telugu is data, and the fixture's short placeholder strings would not
/// catch a real overflow the way the actual shipped translations can.
const _ow001TeluguTranslations = <String, Map<String, String>>{
  'todays_business_summary': {'English': "Today's Business Summary", 'Telugu': 'నేటి వ్యాపార సారాంశం'},
  'quick_actions': {'English': 'Quick Actions', 'Telugu': 'త్వరిత చర్యలు'},
  'live_business_activity': {'English': 'Live Business Activity', 'Telugu': 'ప్రత్యక్ష వ్యాపార కార్యకలాపం'},
  'attention_required': {'English': 'Attention Required', 'Telugu': 'శ్రద్ధ అవసరం'},
  'see_all': {'English': 'See All', 'Telugu': 'అన్నీ చూడండి'},
  'session_timed_out': {'English': 'Session Timed Out', 'Telugu': 'సెషన్ గడువు ముగిసింది'},
  'could_not_load_dashboard': {'English': 'Could Not Load Dashboard', 'Telugu': 'డాష్‌బోర్డ్ లోడ్ కాలేదు'},
  'enter_pin': {'English': 'Enter PIN', 'Telugu': 'పిన్ నమోదు చేయండి'},
  'retry': {'English': 'Retry', 'Telugu': 'మళ్ళీ ప్రయత్నించండి'},
  'profile': {'English': 'Profile', 'Telugu': 'ప్రొఫైల్'},
  'business_management': {'English': 'Business Management', 'Telugu': 'వ్యాపార నిర్వహణ'},
  'report_hub': {'English': 'Report Hub', 'Telugu': 'నివేదిక కేంద్రం'},
  'switch_workspace': {'English': 'Switch Workspace', 'Telugu': 'వర్క్‌స్పేస్ మార్చండి'},
  'switch_role': {'English': 'Switch Role', 'Telugu': 'పాత్ర మార్చండి'},
  'settings': {'English': 'Settings', 'Telugu': 'సెట్టింగ్‌లు'},
  'logout': {'English': 'Logout', 'Telugu': 'లాగ్ అవుట్'},
  'more_options': {'English': 'More Options', 'Telugu': 'మరిన్ని ఎంపికలు'},
  'notifications': {'English': 'Notifications', 'Telugu': 'నోటిఫికేషన్‌లు'},
  'nothing_else_to_report': {'English': 'Nothing else to report.', 'Telugu': 'నివేదించడానికి మరేమీ లేదు.'},
  'no_notifications_yet': {'English': 'No notifications yet.', 'Telugu': 'ఇంకా నోటిఫికేషన్‌లు లేవు.'},
  'search': {'English': 'Search', 'Telugu': 'శోధించండి'},
  'search_by_phone_mlid_aadhaar_name': {
    'English': 'Search by Phone, MANA LINE ID, Aadhaar, or Name.',
    'Telugu': 'ఫోన్, MANA LINE ID, ఆధార్ లేదా పేరు ద్వారా శోధించండి.',
  },
  'not_a_member_of_business': {'English': 'Not a member of this business.', 'Telugu': 'ఈ వ్యాపారంలో సభ్యుడు కాదు.'},
  'brought_forward': {'English': 'BF', 'Telugu': 'BF'},
  'opening_balance': {'English': 'Opening Balance', 'Telugu': 'ప్రారంభ నిల్వ'},
  'todays_collections': {'English': "Today's Collections", 'Telugu': 'నేటి వసూళ్లు'},
  'todays_loan_distribution': {'English': "Today's Loan Distribution", 'Telugu': 'నేటి రుణ పంపిణీ'},
  'todays_investments': {'English': "Today's Investments", 'Telugu': 'నేటి పెట్టుబడులు'},
  'todays_withdrawals': {'English': "Today's Withdrawals", 'Telugu': 'నేటి ఉపసంహరణలు'},
  'todays_expenses': {'English': "Today's Expenses", 'Telugu': 'నేటి ఖర్చులు'},
  'todays_outstanding': {'English': "Today's Outstanding", 'Telugu': 'నేటి బాకీ'},
  'todays_difference': {'English': "Today's Difference", 'Telugu': 'నేటి తేడా'},
  'closing_balance': {'English': 'Live Closing Balance', 'Telugu': 'ప్రస్తుత ముగింపు నిల్వ'},
  'customers': {'English': 'Customers', 'Telugu': 'కస్టమర్లు'},
  'new_loan': {'English': 'New Loan', 'Telugu': 'కొత్త రుణం'},
  'collections': {'English': 'Collections', 'Telugu': 'వసూళ్లు'},
  'customer_management': {'English': 'Customer Management', 'Telugu': 'కస్టమర్ నిర్వహణ'},
  'loan_requests': {'English': 'Loan Requests', 'Telugu': 'రుణ అభ్యర్థనలు'},
  'group_loans': {'English': 'Group Loans', 'Telugu': 'సమూహ రుణాలు'},
  'workforce': {'English': 'Workforce', 'Telugu': 'శ్రామికులు'},
  'workforce_management': {'English': 'Workforce Management', 'Telugu': 'శ్రామిక నిర్వహణ'},
  'day_closure': {'English': 'Day Closure', 'Telugu': 'దిన ముగింపు'},
  'daily_record_book': {'English': 'Daily Record Book', 'Telugu': 'రోజువారీ రికార్డు పుస్తకం'},
  'reports': {'English': 'Reports', 'Telugu': 'నివేదికలు'},
  'account_review': {'English': 'Account Review', 'Telugu': 'ఖాతా సమీక్ష'},
  'investor': {'English': 'Investor', 'Telugu': 'పెట్టుబడిదారు'},
  'add_existing_investor': {'English': 'Add Existing Investor', 'Telugu': 'ఇప్పటికే ఉన్న పెట్టుబడిదారుని జోడించండి'},
  'investor_requests': {'English': 'Investor Requests', 'Telugu': 'పెట్టుబడిదారు అభ్యర్థనలు'},
  'investor_management': {'English': 'Investor Management', 'Telugu': 'పెట్టుబడిదారుల నిర్వహణ'},
  'withdrawal_requests': {'English': 'Withdrawal Requests', 'Telugu': 'ఉపసంహరణ అభ్యర్థనలు'},
  'no_activity_today': {'English': 'No activity yet today.', 'Telugu': 'ఈరోజు ఇంకా కార్యకలాపం లేదు.'},
  'nothing_needs_attention': {'English': 'Nothing needs attention right now.', 'Telugu': 'ప్రస్తుతం దేనికీ శ్రద్ధ అవసరం లేదు.'},
  'home': {'English': 'Home', 'Telugu': 'హోమ్'},
  'history': {'English': 'History', 'Telugu': 'చరిత్ర'},
};

void main() {
  final seed = OwnerDashboardData.zero(
    businessName: 'Sri Venkateswara Rural Finance and Chit Fund Society',
  );

  for (final scale in kManaTextScales) {
    testWidgets('OW-001 Owner Dashboard survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const OwnerHomeDashboardScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [ownerDashboardProvider.overrideWith(() => _SeededOwnerDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-001 Owner Dashboard at ${scale}x');
    });

    // The concern this covers: does the actual shipped Telugu — not the
    // short vendored fixture — fit at every text scale a real device can
    // reach? Telugu strings run noticeably longer than their English
    // source (e.g. "Add Existing Investor" -> "ఇప్పటికే ఉన్న
    // పెట్టుబడిదారుని జోడించండి"), so this is the scenario most likely to
    // overflow first.
    testWidgets('OW-001 Owner Dashboard survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const OwnerHomeDashboardScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow001TeluguTranslations,
        overrides: [ownerDashboardProvider.overrideWith(() => _SeededOwnerDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-001 Owner Dashboard at ${scale}x in Telugu');
    });
  }

  testWidgets('OW-001 shows the business name', (tester) async {
    await pumpManaScreen(
      tester,
      const OwnerHomeDashboardScreen(businessId: 'b1'),
      overrides: [ownerDashboardProvider.overrideWith(() => _SeededOwnerDashboardNotifier(seed))],
    );
    expect(find.textContaining('Sri Venkateswara'), findsWidgets);
  });
}
