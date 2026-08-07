import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_003_todays_route.dart';
import 'package:mana_line/features/agent_workspace/state/todays_route_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededTodaysRouteNotifier extends TodaysRouteNotifier {
  _SeededTodaysRouteNotifier(this._seed);
  final TodaysRouteState _seed;

  @override
  TodaysRouteState build() => _seed;

  @override
  Future<void> load({required String businessId, required String agentMembershipId}) async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260807173830 + reused earlier keys).
const _ag003TeluguTranslations = <String, Map<String, String>>{
  'todays_route': {'English': "Today's Route", 'Telugu': 'నేటి మార్గం'},
  'dashboard': {'English': 'Dashboard', 'Telugu': 'డాష్‌బోర్డ్'},
  'villages': {'English': 'Villages', 'Telugu': 'గ్రామాలు'},
  'assigned': {'English': 'Assigned', 'Telugu': 'కేటాయించబడింది'},
  'completed': {'English': 'Completed', 'Telugu': 'పూర్తయింది'},
  'pending_label': {'English': 'Pending', 'Telugu': 'పెండింగ్'},
  'est_collection': {'English': 'Est. Collection', 'Telugu': 'అంచనా వసూలు'},
  'collected': {'English': 'Collected', 'Telugu': 'వసూలైంది'},
  'village_customer_order_note': {
    'English': 'Village and customer order are set by your Owner — this route cannot be reordered.',
    'Telugu': 'గ్రామం మరియు కస్టమర్ క్రమాన్ని మీ యజమాని నిర్ణయిస్తారు — ఈ మార్గాన్ని తిరిగి క్రమబద్ధీకరించలేరు.',
  },
  'visit_percent': {'English': 'Visit {percent}%', 'Telugu': 'సందర్శన {percent}%'},
  'collection_percent': {'English': 'Collection {percent}%', 'Telugu': 'వసూలు {percent}%'},
  'remaining_percent': {'English': 'Remaining {percent}%', 'Telugu': 'మిగిలిన {percent}%'},
  'partial': {'English': 'Partial', 'Telugu': 'పాక్షికం'},
  'skipped': {'English': 'Skipped', 'Telugu': 'దాటవేయబడింది'},
  'house_locked': {'English': 'House Locked', 'Telugu': 'ఇల్లు లాక్ చేయబడింది'},
  'shifted_village': {'English': 'Shifted Village', 'Telugu': 'గ్రామం మారింది'},
  'extension_requested': {'English': 'Extension Requested', 'Telugu': 'పొడిగింపు అభ్యర్థించారు'},
  'closed': {'English': 'Closed', 'Telugu': 'మూసివేయబడింది'},
  'customers_left_to_visit': {
    'English': '{count} customer(s) left to visit.',
    'Telugu': '{count} కస్టమర్(లు) సందర్శించాల్సి ఉంది.',
  },
  'route_complete_return_to_dashboard': {
    'English': 'Route Complete — Return to Dashboard',
    'Telugu': 'మార్గం పూర్తయింది — డాష్‌బోర్డ్‌కు తిరిగి వెళ్లండి',
  },
};

void main() {
  final stops = [
    RouteStop(
      loanId: 'l1',
      customerId: 'c1',
      customerName: 'Nagabhushanam Venkata Subba Reddy',
      village: 'Srikalahasti — Uranduru Colony',
      visitOrder: 1,
      loanNumber: 'MLLN0000012345',
      todaysDue: 1500,
      outstandingBalance: 84500,
      lineRepaymentIndex: 12,
      loanStatus: 'Active',
    ),
    RouteStop(
      loanId: 'l2',
      customerId: 'c2',
      customerName: 'Chalasani Ramana',
      village: 'Puttur',
      visitOrder: 2,
      loanNumber: 'MLLN0000012346',
      todaysDue: 500,
      outstandingBalance: 12000,
      lineRepaymentIndex: 3,
      loanStatus: 'Grace Period',
    ),
  ];
  final seed = TodaysRouteState(stops: stops);

  for (final scale in kManaTextScales) {
    testWidgets('AG-003 Today\'s Route survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const TodaysRouteScreen(businessId: 'b1', agentMembershipId: 'm1'),
        textScale: scale,
        overrides: [todaysRouteProvider.overrideWith(() => _SeededTodaysRouteNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'AG-003 Today\'s Route at ${scale}x');
    });

    testWidgets('AG-003 Today\'s Route survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const TodaysRouteScreen(businessId: 'b1', agentMembershipId: 'm1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ag003TeluguTranslations,
        overrides: [todaysRouteProvider.overrideWith(() => _SeededTodaysRouteNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'AG-003 Today\'s Route at ${scale}x in Telugu');
    });
  }

  testWidgets('AG-003 shows the route stops', (tester) async {
    await pumpManaScreen(
      tester,
      const TodaysRouteScreen(businessId: 'b1', agentMembershipId: 'm1'),
      overrides: [todaysRouteProvider.overrideWith(() => _SeededTodaysRouteNotifier(seed))],
    );
    expect(find.textContaining('Nagabhushanam'), findsWidgets);
  });
}
