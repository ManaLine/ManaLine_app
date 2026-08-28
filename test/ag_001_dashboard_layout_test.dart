import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_001_agent_home_dashboard.dart';
import 'package:mana_line/features/agent_workspace/state/agent_dashboard_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

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
      // Collection Mode and Universal Search are still PERMITTED here and
      // still not drawn: the quick actions offer three, and those two go
      // where the footer's Collections tab and the header's magnifier
      // already go.
      visibleQuickActions: const {
        'Collection Mode',
        'Universal Search',
        'Loan Distribution',
        'Draft Transactions',
        'Settlement',
      },
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

/// The real ui_translations rows this screen was wired against (migration
/// 20260807170335 + reused OW-001/earlier keys), not the vendored fixture —
/// same reasoning as ow_001_dashboard_layout_test.dart. `visibleQuickActions`
/// above is now populated (unlike before this wiring pass), so this run also
/// exercises the Quick Actions grid, previously untested here.
const _ag001TeluguTranslations = <String, Map<String, String>>{
  'customers': {'English': 'Customers', 'Telugu': 'కస్టమర్లు'},
  'customer_management': {'English': 'Customer Management', 'Telugu': 'కస్టమర్ నిర్వహణ'},
  'todays_route': {'English': "Today's Route", 'Telugu': 'నేటి మార్గం'},
  'my_work': {'English': 'My Work', 'Telugu': 'నా పని'},
  'draft_transactions': {'English': 'Draft Transactions', 'Telugu': 'డ్రాఫ్ట్ లావాదేవీలు'},
  'transaction_history': {'English': 'Transaction History', 'Telugu': 'లావాదేవీల చరిత్ర'},
  'change_area': {'English': 'Change Area', 'Telugu': 'ప్రాంతం మార్చండి'},
  'create_new_business': {'English': 'Create New Business', 'Telugu': 'కొత్త వ్యాపారాన్ని సృష్టించండి'},
  'notifications': {'English': 'Notifications', 'Telugu': 'నోటిఫికేషన్‌లు'},
  'profile': {'English': 'Profile', 'Telugu': 'ప్రొఫైల్'},
  'home': {'English': 'Home', 'Telugu': 'హోమ్'},
  'collections': {'English': 'Collections', 'Telugu': 'వసూళ్లు'},
  'history': {'English': 'History', 'Telugu': 'చరిత్ర'},
  'business_status': {'English': 'Business Status', 'Telugu': 'వ్యాపార స్థితి'},
  'business_date': {'English': 'Business Date', 'Telugu': 'వ్యాపార తేదీ'},
  'assigned_route': {'English': 'Assigned Route', 'Telugu': 'కేటాయించిన మార్గం'},
  'pending_drafts': {'English': 'Pending Drafts', 'Telugu': 'పెండింగ్ డ్రాఫ్ట్‌లు'},
  'pending_settlement': {'English': 'Pending Settlement', 'Telugu': 'పెండింగ్ సెటిల్‌మెంట్'},
  'yes': {'English': 'Yes', 'Telugu': 'అవును'},
  'no': {'English': 'No', 'Telugu': 'కాదు'},
  'todays_target': {'English': "Today's Target", 'Telugu': 'నేటి లక్ష్యం'},
  'today_summary': {'English': 'Today Summary', 'Telugu': 'నేటి సారాంశం'},
  'customers_assigned': {'English': 'Customers Assigned', 'Telugu': 'కేటాయించిన కస్టమర్లు'},
  'customers_visited': {'English': 'Customers Visited', 'Telugu': 'సందర్శించిన కస్టమర్లు'},
  'customers_remaining': {'English': 'Customers Remaining', 'Telugu': 'మిగిలిన కస్టమర్లు'},
  'cash': {'English': 'Cash', 'Telugu': 'నగదు'},
  'upi': {'English': 'UPI', 'Telugu': 'UPI'},
  'bank': {'English': 'Bank', 'Telugu': 'బ్యాంక్'},
  'cheque': {'English': 'Cheque', 'Telugu': 'చెక్కు'},
  'mixed': {'English': 'Mixed', 'Telugu': 'మిశ్రమ'},
  'todays_collections_total': {'English': "Today's Collections Total", 'Telugu': 'నేటి మొత్తం వసూళ్లు'},
  'loans_issued': {'English': 'Loans Issued', 'Telugu': 'జారీ చేసిన రుణాలు'},
  'pending_collections': {'English': 'Pending Collections', 'Telugu': 'పెండింగ్ వసూళ్లు'},
  'skipped_customers': {'English': 'Skipped Customers', 'Telugu': 'దాటవేసిన కస్టమర్లు'},
  'short': {'English': 'Short', 'Telugu': 'తక్కువ'},
  'excess': {'English': 'Excess', 'Telugu': 'అధికం'},
  'quick_actions': {'English': 'Quick Actions', 'Telugu': 'త్వరిత చర్యలు'},
  'collection_mode': {'English': 'Collection Mode', 'Telugu': 'వసూలు మోడ్'},
  'universal_search': {'English': 'Universal Search', 'Telugu': 'యూనివర్సల్ శోధన'},
  'attention_required': {'English': 'Attention Required', 'Telugu': 'శ్రద్ధ అవసరం'},
  'pending_customer_requests': {'English': 'Pending Customer Requests', 'Telugu': 'పెండింగ్ కస్టమర్ అభ్యర్థనలు'},
  'pending_extension_requests': {'English': 'Pending Extension Requests', 'Telugu': 'పెండింగ్ పొడిగింపు అభ్యర్థనలు'},
  'pending_route_changes': {'English': 'Pending Route Changes', 'Telugu': 'పెండింగ్ మార్గం మార్పులు'},
  'pending_messages': {'English': 'Pending Messages', 'Telugu': 'పెండింగ్ సందేశాలు'},
  'live_activity': {'English': 'Live Activity', 'Telugu': 'ప్రత్యక్ష కార్యకలాపం'},
  'nothing_yet_today': {'English': 'Nothing yet today.', 'Telugu': 'ఈరోజు ఇంకా ఏమీ లేదు.'},
  'my_compensation': {'English': 'My Compensation', 'Telugu': 'నా వేతనం'},
  'read_only_set_by_owner': {'English': 'Read-only, set by Owner.', 'Telugu': 'చదవడానికి మాత్రమే, యజమాని నిర్ణయించారు.'},
  'fixed_salary': {'English': 'Fixed Salary', 'Telugu': 'స్థిర జీతం'},
  'salary_cycle': {'English': 'Salary Cycle', 'Telugu': 'జీతం చక్రం'},
  'daily_allowance': {'English': 'Daily Allowance', 'Telugu': 'రోజువారీ భత్యం'},
  'profit_share': {'English': 'Profit Share', 'Telugu': 'లాభ వాటా'},
  'advances_deducted': {'English': 'Advances Deducted', 'Telugu': 'తీసివేసిన అడ్వాన్సులు'},
  'shorts_deducted': {'English': 'Shorts Deducted', 'Telugu': 'తీసివేసిన లోటులు'},
  'pending_salary': {'English': 'Pending Salary', 'Telugu': 'పెండింగ్ జీతం'},
  'salary_history': {'English': 'Salary History', 'Telugu': 'జీతం చరిత్ర'},
  'workspace_information': {'English': 'Workspace Information', 'Telugu': 'వర్క్‌స్పేస్ సమాచారం'},
  'business_name': {'English': 'Business Name', 'Telugu': 'వ్యాపార పేరు'},
  'owner': {'English': 'Owner', 'Telugu': 'యజమాని'},
  'membership_status': {'English': 'Membership Status', 'Telugu': 'సభ్యత్వ స్థితి'},
  'permission_profile': {'English': 'Permission Profile', 'Telugu': 'అనుమతి ప్రొఫైల్'},
  'last_sync': {'English': 'Last Sync', 'Telugu': 'చివరి సింక్'},
};

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

    testWidgets('AG-001 Agent Dashboard survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const AgentHomeDashboardScreen(businessId: 'b1', agentId: 'a1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ag001TeluguTranslations,
        overrides: [agentDashboardProvider.overrideWith(() => _SeededAgentDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'AG-001 Agent Dashboard at ${scale}x in Telugu');
    });
  }

  testWidgets('AG-001 shows the assigned route, once Business Status is opened',
      (tester) async {
    await pumpManaScreen(
      tester,
      const AgentHomeDashboardScreen(businessId: 'b1', agentId: 'a1'),
      location: '/ag-001',
      overrides: [agentDashboardProvider.overrideWith(() => _SeededAgentDashboardNotifier(seed))],
    );
    await tester.pumpAndSettle();

    // Shut on arrival, and that is the point: five sections open at once was
    // four screens of scrolling before the last one was reached.
    expect(find.textContaining('Srikalahasti'), findsNothing);

    final header = find.text('Business Status');
    await tester.scrollUntilVisible(header, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.textContaining('Srikalahasti'), findsWidgets);
  });

  testWidgets('the day starts with cash in hand, then three actions',
      (tester) async {
    await pumpManaScreen(
      tester,
      const AgentHomeDashboardScreen(businessId: 'b1', agentId: 'a1'),
      location: '/ag-001',
      overrides: [agentDashboardProvider.overrideWith(() => _SeededAgentDashboardNotifier(seed))],
    );
    await tester.pumpAndSettle();

    // BF was not on this screen at all -- it lived on AG-007, two taps away,
    // reading the column the Agent set out with rather than the one they hold.
    expect(find.text('Cash in Hand (BF)'), findsOneWidget);

    // Three, not seven. Collection Mode, Customer List, Notifications and
    // Universal Search all went where the footer, the bell and the header
    // magnifier already go.
    expect(find.text('Loan Distribution'), findsOneWidget);
    expect(find.text('Draft Transactions'), findsOneWidget);
    expect(find.text('Settlement'), findsOneWidget);
    expect(find.text('Customer List'), findsNothing);
    expect(find.text('Collection Mode'), findsNothing);
  });

  testWidgets("Today's Summary is the one section open on arrival",
      (tester) async {
    await pumpManaScreen(
      tester,
      const AgentHomeDashboardScreen(businessId: 'b1', agentId: 'a1'),
      location: '/ag-001',
      overrides: [agentDashboardProvider.overrideWith(() => _SeededAgentDashboardNotifier(seed))],
    );
    await tester.pumpAndSettle();

    expect(find.text('Customers Assigned'), findsOneWidget,
        reason: "the day's own figures are what this screen is for");
  });

  testWidgets('no + Expense button floating over the dashboard',
      (tester) async {
    // It sat over the bottom-right of the one screen an Agent is NOT on when
    // they buy petrol between two villages. The action is in the header of
    // every other Agent screen now.
    await pumpManaScreen(
      tester,
      const AgentHomeDashboardScreen(businessId: 'b1', agentId: 'a1'),
      location: '/ag-001',
      overrides: [agentDashboardProvider.overrideWith(() => _SeededAgentDashboardNotifier(seed))],
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
