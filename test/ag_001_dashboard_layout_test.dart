import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_001_agent_home_dashboard.dart';
import 'package:mana_line/features/agent_workspace/state/agent_dashboard_state.dart';

import 'support/mana_harness.dart';

/// Seeded straight into the S2 "running" stage with a no-op enter() — the
/// real enter() reaches Supabase, never initialised in a test process.
class _SeededAgentDashboardNotifier extends AgentDashboardNotifier {
  _SeededAgentDashboardNotifier(this._seed);
  final AgentDashboardState _seed;

  @override
  AgentDashboardState build() => _seed;

  @override
  Future<void> enter({required String agentId, required String businessId}) async {}
}

AgentDashboardData _seedData() => AgentDashboardData(
      businessDate: DateTime(2026, 8, 7),
      assignedRoute: 'Srikalahasti — Uranduru — Puttur Rural Round',
      pendingDraftsCount: 3,
      pendingSettlement: false,
      todaysTarget: 45,
      customersAssigned: 45,
      customersVisited: 28,
      collectionsCash: 84500,
      collectionsUpi: 12300,
      collectionsBank: 0,
      collectionsCheque: 0,
      collectionsMixed: 0,
      loansIssued: 25000,
      pendingCollections: 17,
      skippedCustomers: 2,
      shortAmount: 500,
      excessAmount: 0,
      visibleQuickActions: const {'collection_mode', 'customers', 'history'},
      liveActivity: const [],
      businessName: 'Sri Venkateswara Rural Finance and Chit Fund Society',
      ownerName: 'Karri Siri Manikanta Reddy',
      membershipStatus: 'Active',
      permissionProfile: 'Full Collection Access',
      lastSync: DateTime(2026, 8, 7, 9, 30),
      pendingCustomerRequests: 1,
      pendingExtensionRequests: 0,
      pendingRouteChanges: 0,
      pendingMessages: 0,
      fixedSalary: 12000,
      salaryCycleStatus: 'Monthly — Running',
      dailyAllowance: 100,
      profitSharePercent: 2.5,
      advancesDeducted: 500,
      shortsDeducted: 0,
      pendingSalary: 11500,
    );

void main() {
  final seed = AgentDashboardState(
    stage: AgentSessionStage.running,
    dashboard: _seedData(),
  );

  for (final scale in kManaTextScales) {
    testWidgets('AG-001 Agent Dashboard survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const AgentHomeDashboardScreen(businessId: 'b1', agentId: 'a1'),
        textScale: scale,
        overrides: [agentDashboardProvider.overrideWith(() => _SeededAgentDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'AG-001 Agent Dashboard at ${scale}x');
    });
  }

  testWidgets('AG-001 shows the assigned route', (tester) async {
    await pumpManaScreen(
      tester,
      const AgentHomeDashboardScreen(businessId: 'b1', agentId: 'a1'),
      overrides: [agentDashboardProvider.overrideWith(() => _SeededAgentDashboardNotifier(seed))],
    );
    expect(find.textContaining('Srikalahasti'), findsWidgets);
  });
}
