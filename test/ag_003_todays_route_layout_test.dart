import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_003_todays_route.dart';
import 'package:mana_line/features/agent_workspace/state/todays_route_state.dart';

import 'support/mana_harness.dart';

class _SeededTodaysRouteNotifier extends TodaysRouteNotifier {
  _SeededTodaysRouteNotifier(this._seed);
  final TodaysRouteState _seed;

  @override
  TodaysRouteState build() => _seed;

  @override
  Future<void> load({required String businessId, required String agentMembershipId}) async {}
}

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
