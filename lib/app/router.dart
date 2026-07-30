import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'design_showcase_screen.dart';
import '../features/login_registration/state/auth_flow_state.dart';
import '../features/login_registration/screens/lr_001_system_startup.dart';
import '../features/login_registration/screens/lr_002_workspace_choice.dart';
import '../features/login_registration/screens/lr_003_login_registration_choice.dart';
import '../features/login_registration/screens/lr_004_registration_form.dart';
import '../features/login_registration/screens/lr_005_otp_verification.dart';
import '../features/login_registration/screens/lr_006_registration_result.dart';
import '../features/login_registration/screens/lr_007_first_login.dart';
import '../features/login_registration/screens/lr_008_create_pin.dart';
import '../features/login_registration/screens/lr_009_daily_login.dart';
import '../features/login_registration/screens/lr_010_forgot_password.dart';
import '../features/login_registration/screens/lr_011_forgot_pin.dart';
import '../features/login_registration/screens/lr_012_business_selector.dart';
import '../features/login_registration/screens/lr_013_role_selector.dart';
import '../shared/login_nav_args.dart';
import '../features/owner_workspace/screens/ow_000_first_business_setup.dart';
import '../features/owner_workspace/screens/ow_001_owner_home_dashboard.dart';
import '../features/owner_workspace/screens/ow_002_workforce_management.dart';
import '../features/owner_workspace/screens/ow_003_investor_management.dart';
import '../features/owner_workspace/screens/ow_004_customer_management.dart';
import '../features/owner_workspace/screens/ow_005_new_loan_workflow.dart';
import '../features/owner_workspace/screens/ow_006_collection_mode.dart';
import '../features/owner_workspace/screens/ow_007_loan_details.dart';
import '../features/owner_workspace/screens/ow_009_daily_record_book.dart';
import '../features/owner_workspace/screens/ow_010_report_hub.dart';
import '../features/owner_workspace/screens/ow_011_day_closure.dart';
import '../features/owner_workspace/screens/ow_012_business_management.dart';
import '../features/owner_workspace/state/business_management_state.dart' show BusinessDetailTab;
import '../features/owner_workspace/screens/ow_013_account_review.dart';
import '../features/owner_workspace/screens/ow_014_global_workflow.dart';
import '../features/owner_workspace/screens/ow_014_profile_completion.dart';
import '../features/owner_workspace/screens/ow_015_group_loan_management.dart';
import '../features/owner_workspace/screens/ow_016_profile.dart';
import '../features/owner_workspace/screens/ow_017_transaction_history.dart';
import '../features/owner_workspace/screens/loan_requests_screen.dart';
import '../features/owner_workspace/screens/withdrawal_requests_screen.dart';
import '../shared/settings_screen.dart';
import '../features/agent_workspace/screens/ag_001_agent_home_dashboard.dart';
import '../features/agent_workspace/screens/ag_002_collection_mode.dart';
import '../features/agent_workspace/screens/ag_003_todays_route.dart';
import '../features/agent_workspace/screens/ag_004_customer_management.dart';
import '../features/agent_workspace/screens/ag_005_draft_transactions.dart';
import '../features/agent_workspace/screens/ag_006_owner_settlement.dart';
import '../features/agent_workspace/screens/ag_007_loan_distribution.dart';
import '../features/agent_workspace/screens/ag_008_notifications.dart';
import '../features/agent_workspace/screens/ag_009_profile.dart';
import '../features/customer_workspace/screens/cw_001_customer_home_dashboard.dart';
import '../features/customer_workspace/screens/cw_002_find_a_business.dart' as cw002;
import '../features/customer_workspace/screens/cw_003_request_new_loan.dart';
import '../features/customer_workspace/screens/cw_004_my_loans.dart';
import '../features/customer_workspace/screens/cw_005_make_a_payment.dart';
import '../features/customer_workspace/screens/cw_006_my_profile_memberships.dart' as cw006;
import '../features/investor_workspace/screens/iw_001_investor_home_dashboard.dart';
import '../features/support_admin/screens/sp_001_aadhaar_dispute_resolution.dart';
import '../features/admin/admin_panel_screen.dart';
import '../features/investor_workspace/screens/iw_002_find_a_business.dart';
import '../features/investor_workspace/screens/iw_003_my_investments.dart';
import '../features/investor_workspace/screens/iw_004_request_withdrawal.dart';
import '../features/investor_workspace/screens/iw_005_my_profile_memberships.dart';

/// Route map mirrors the locked screen inventory 1:1 — file/screen
/// numbers double as route names, so anyone cross-referencing this
/// router against the UI spec finds a direct match, not a renamed
/// abstraction layer.
///
/// Each route currently points to `_ScaffoldPlaceholder` — swap in the
/// real screen widget as each one is built (Week 2 onward per the
/// Development Timeline). This file's job for Week 1 is to prove the
/// navigation graph matches the spec's own NAVIGATION sections, not to
/// implement every screen yet.
/// Resolves the businessId a workspace route should use: `extra` when
/// go_router actually carried one (in-app navigation), else the last
/// businessId a route was reached with (survives browser refresh/direct
/// URL, which lose `extra`), else the review-mode stub. Also the single
/// place that persists `extra` when it IS present, so every route that
/// uses this stays in sync without each call site remembering to do it.
String _resolveBusinessId(GoRouterState s) {
  final extra = s.extra as String?;
  if (extra != null) {
    ManaSession.instance.rememberBusinessId(extra);
    return extra;
  }
  return ManaSession.instance.lastBusinessId ?? 'stub-business-id';
}

final manaRouter = GoRouter(
  initialLocation: '/lr-001',
  routes: [
    // Temporary — remove once you're done reviewing the design system.
    // Reach it manually by navigating to /_design.
    GoRoute(path: '/_design', builder: (c, s) => const DesignShowcaseScreen()),

    // --- Login & Registration (Module) --------------------------------
    // LR-001 through LR-008 are real, built screens. LR-009 through
    // LR-013 are still placeholders — next batch.
    GoRoute(path: '/lr-001', builder: (c, s) => const SystemStartupScreen()),
    GoRoute(path: '/lr-002', builder: (c, s) => const WorkspaceChoiceScreen()),
    GoRoute(path: '/lr-003', builder: (c, s) => const LoginRegistrationChoiceScreen()),
    GoRoute(path: '/lr-004', builder: (c, s) => const RegistrationFormScreen()),
    GoRoute(
      path: '/lr-005',
      builder: (c, s) {
        final extra = s.extra;
        if (extra is OtpEntryArgs) {
          return OtpVerificationScreen(purpose: extra.purpose, membershipId: extra.membershipId);
        }
        // Backward-compatible fallback for the old bare-enum extra shape.
        return OtpVerificationScreen(purpose: (extra as OtpPurpose?) ?? OtpPurpose.registration);
      },
    ),
    GoRoute(path: '/lr-006', builder: (c, s) => const RegistrationResultScreen()),
    GoRoute(
      path: '/lr-007',
      builder: (c, s) {
        final args = s.extra as LoginStepDownArgs?;
        return FirstLoginScreen(
          stepDownFromFailedPin: args?.stepDownFromFailedPin ?? false,
          prefilledMobile: args?.prefilledMobile,
          successToast: args?.successToast,
          redirectAfterSuccess: args?.redirectAfterSuccess,
        );
      },
    ),
    GoRoute(path: '/lr-008', builder: (c, s) => CreatePinScreen(isUpgrade: s.extra == true)),
    GoRoute(path: '/lr-009', builder: (c, s) => const DailyLoginScreen()),
    GoRoute(path: '/lr-010', builder: (c, s) => const ForgotPasswordScreen()),
    GoRoute(path: '/lr-011', builder: (c, s) => const ForgotPinScreen()),
    GoRoute(path: '/lr-012', builder: (c, s) => const BusinessSelectorScreen()),
    GoRoute(path: '/lr-013', builder: (c, s) => const RoleSelectorScreen()),

    // --- Owner Workspace -----------------------------------------------
    // OW-000/001/002 are real, built screens. OW-003 onward are still
    // placeholders. businessId is passed via `extra` (set by LR-012/LR-013
    // selection or by OW-000's own "Start Business" completion) — falls
    // back to a stub id so each route is directly reachable during review.
    GoRoute(
      path: '/ow-000',
      builder: (c, s) => FirstBusinessSetupScreen(isAdditionalBusiness: s.extra == true),
    ),
    GoRoute(
      path: '/ow-001',
      builder: (c, s) => OwnerHomeDashboardScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ow-002',
      builder: (c, s) => WorkforceManagementScreen(
        businessId: _resolveBusinessId(s),
        initialAction: s.uri.queryParameters['open'],
      ),
    ),
    GoRoute(
      path: '/ow-003',
      builder: (c, s) => InvestorManagementScreen(
        businessId: _resolveBusinessId(s),
        initialAction: s.uri.queryParameters['open'],
        initialFilter: s.uri.queryParameters['filter'],
      ),
    ),
    GoRoute(
      path: '/ow-004',
      builder: (c, s) => CustomerManagementScreen(
        businessId: _resolveBusinessId(s),
        autoFocusSearch: s.uri.queryParameters['focus'] == 'search',
      ),
    ),
    GoRoute(
      path: '/ow-005',
      // BUG FIXED this pass: businessId here NEVER read `extra` — it
      // came from the session fallback unconditionally, while `extra`
      // was actually read as prefilledCustomerId. That was silently
      // harmless while prefilledCustomerId was itself dead code (see
      // ow_005's own fix note), but OW-001's Quick Actions "New Loan"
      // tile passes `extra: businessId` like every other tile this
      // session standardized on — which this route would have
      // misread as a customer id the moment prefilledCustomerId
      // actually started doing something. Aligned to the same
      // extra=businessId + query-param convention used everywhere else.
      builder: (c, s) => NewLoanWorkflowScreen(
        businessId: _resolveBusinessId(s),
        prefilledCustomerId: s.uri.queryParameters['customerId'],
        sourceRequestId: s.uri.queryParameters['requestId'],
      ),
    ),
    GoRoute(
      path: '/ow-006',
      builder: (c, s) => CollectionModeScreen(
        businessId: ManaSession.instance.lastBusinessId ?? 'stub-business-id',
        prefilledLoanId: s.extra as String?,
      ),
    ),
    GoRoute(
      path: '/ow-007',
      builder: (c, s) => LoanDetailsScreen(loanId: (s.extra as String?) ?? 'stub-loan-id'),
    ),
    GoRoute(
      path: '/ow-009',
      builder: (c, s) => DailyRecordBookScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ow-010',
      builder: (c, s) => ReportHubScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ow-011',
      builder: (c, s) => DayClosureScreen(
        businessId: _resolveBusinessId(s),
        businessDate: DateTime.now().toIso8601String().split('T').first,
      ),
    ),
    GoRoute(
      path: '/ow-012',
      builder: (c, s) => BusinessManagementScreen(
        initialBusinessId: s.extra as String?,
        initialTab: switch (s.uri.queryParameters['tab']) {
          'members' => BusinessDetailTab.members,
          'agreements' => BusinessDetailTab.agreements,
          'accountPeriods' => BusinessDetailTab.accountPeriods,
          'operatingAreas' => BusinessDetailTab.operatingAreas,
          _ => null,
        },
      ),
    ),
    GoRoute(
      path: '/ow-013',
      builder: (c, s) => AccountReviewScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ow-014',
      builder: (c, s) => GlobalWorkflowScreen(
        businessId: _resolveBusinessId(s),
        currentOwnerPersonId: ManaSession.instance.currentPersonId ?? 'stub-person-id',
      ),
    ),
    // OW-014's Profile Completion sub-flow. Separate route rather than a
    // fourth WizardStage: it is also the natural destination for any future
    // "incomplete profiles" list (fetchIncompleteProfiles), which carries a
    // personId/membershipId pair but no wizard state at all.
    GoRoute(
      path: '/ow-014-complete-profile',
      builder: (c, s) => ProfileCompletionScreen(
        personId: s.uri.queryParameters['personId'] ?? '',
        membershipId: s.uri.queryParameters['membershipId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/ow-015',
      builder: (c, s) => GroupLoanManagementScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(path: '/ow-016', builder: (c, s) => const OwnerProfileScreen()),
    GoRoute(
      path: '/ow-017',
      builder: (c, s) => TransactionHistoryScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(path: '/ow-settings', builder: (c, s) => SettingsScreen(homeRoute: '/ow-001', businessId: s.extra as String?)),
    // Not part of the original locked screen inventory (no OW-0xx number)
    // — added to close a real gap: loan_requests had a real INSERT path
    // from CW-003 but no Owner-side screen ever read it back.
    GoRoute(path: '/ow-loan-requests', builder: (c, s) => LoanRequestsScreen(businessId: _resolveBusinessId(s))),
    GoRoute(path: '/ow-withdrawal-requests', builder: (c, s) => WithdrawalRequestsScreen(businessId: _resolveBusinessId(s))),
    GoRoute(path: '/ag-settings', builder: (c, s) => SettingsScreen(homeRoute: '/ag-001', businessId: s.extra as String?)),
    GoRoute(path: '/cw-settings', builder: (c, s) => SettingsScreen(homeRoute: '/cw-001', businessId: s.extra as String?)),
    GoRoute(path: '/iw-settings', builder: (c, s) => SettingsScreen(homeRoute: '/iw-001', businessId: s.extra as String?)),

    // --- Agent Workspace -------------------------------------------------
    // AG-001 through AG-009 are real, built screens — full Agent Workspace
    // inventory complete (no AG-010 exists). agentId/businessId passed via
    // `extra` where relevant — falls back to stub ids so each route is
    // directly reachable during review.
    GoRoute(
      path: '/ag-001',
      builder: (c, s) => AgentHomeDashboardScreen(
        agentId: ManaSession.instance.lastAgentId ?? 'stub-agent-id',
        businessId: _resolveBusinessId(s),
        initialAnchor: s.uri.queryParameters['anchor'],
      ),
    ),
    GoRoute(
      path: '/ag-002',
      builder: (c, s) => AgentCollectionModeScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ag-003',
      builder: (c, s) => TodaysRouteScreen(
        businessId: _resolveBusinessId(s),
        agentMembershipId: ManaSession.instance.lastMembershipId ?? 'stub-agent-membership-id',
      ),
    ),
    GoRoute(
      path: '/ag-004',
      builder: (c, s) => AgentCustomerManagementScreen(
        businessId: _resolveBusinessId(s),
        agentMembershipId: ManaSession.instance.lastMembershipId ?? 'stub-agent-membership-id',
      ),
    ),
    GoRoute(
      path: '/ag-005',
      builder: (c, s) => DraftTransactionsScreen(
        businessId: _resolveBusinessId(s),
        membershipId: ManaSession.instance.lastMembershipId ?? 'stub-agent-membership-id',
      ),
    ),
    GoRoute(
      path: '/ag-006',
      builder: (c, s) {
        final now = DateTime.now();
        return OwnerSettlementScreen(
          businessId: _resolveBusinessId(s),
          agentId: ManaSession.instance.lastAgentId ?? 'stub-agent-id',
          periodStart: DateTime(now.year, now.month, now.day),
          periodEnd: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      },
    ),
    GoRoute(
      path: '/ag-007',
      builder: (c, s) => Ag007LoanDistributionScreen(
        agentId: ManaSession.instance.lastAgentId ?? 'stub-agent-id',
        businessId: _resolveBusinessId(s),
        prefilledCustomerId: null,
      ),
    ),
    GoRoute(
      path: '/ag-008',
      builder: (c, s) => Ag008NotificationsScreen(
        agentId: ManaSession.instance.lastAgentId ?? 'stub-agent-id',
        businessId: _resolveBusinessId(s),
      ),
    ),
    GoRoute(
      path: '/ag-009',
      builder: (c, s) => Ag009ProfileScreen(
        personId: ManaSession.instance.currentPersonId ?? 'stub-person-id',
        agentId: ManaSession.instance.lastAgentId ?? 'stub-agent-id',
        businessId: _resolveBusinessId(s),
      ),
    ),

    // --- Customer Workspace ----------------------------------------------
    // --- Customer Workspace ------------------------------------------------
    // CW-001 through CW-006 are real, built screens — full Customer
    // Workspace inventory complete. businessId/customerId/loanId passed via
    // `extra` where relevant — falls back to stub ids so each route is
    // directly reachable during review.
    GoRoute(
      path: '/cw-001',
      builder: (c, s) => CustomerHomeDashboardScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/cw-002',
      builder: (c, s) => cw002.FindABusinessScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/cw-003',
      builder: (c, s) => RequestNewLoanScreen(
        businessId: _resolveBusinessId(s),
        customerId: ManaSession.instance.lastCustomerId ?? 'stub-customer-id',
      ),
    ),
    GoRoute(
      path: '/cw-004',
      builder: (c, s) => MyLoansScreen(
        businessId: _resolveBusinessId(s),
        customerId: ManaSession.instance.lastCustomerId ?? 'stub-customer-id',
      ),
    ),
    GoRoute(
      path: '/cw-005',
      builder: (c, s) => MakeAPaymentScreen(loanId: (s.extra as String?) ?? 'stub-loan-id'),
    ),
    GoRoute(
      path: '/cw-006',
      builder: (c, s) => cw006.MyProfileMembershipsScreen(personId: (s.extra as String?) ?? ManaSession.instance.currentPersonId ?? 'stub-person-id'),
    ),

    // --- Investor Workspace ----------------------------------------------
    GoRoute(
      path: '/iw-001',
      builder: (c, s) => InvestorHomeDashboardScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/iw-002',
      builder: (c, s) => FindABusinessScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/iw-003',
      builder: (c, s) => MyInvestmentsScreen(
        businessId: _resolveBusinessId(s),
        investorId: ManaSession.instance.lastInvestorId ?? 'stub-investor-id',
      ),
    ),
    GoRoute(
      path: '/iw-004',
      builder: (c, s) => RequestWithdrawalScreen(investmentId: (s.extra as String?) ?? 'stub-investment-id'),
    ),
    GoRoute(
      path: '/iw-005',
      // NOTE: IW-001's Quick Actions currently pass businessId as `extra`
      // for every destination uniformly, but this screen needs personId,
      // not businessId — see integration summary. `extra` is therefore
      // ignored here entirely rather than misread as personId; the
      // logged-in person's own id is always the right value for "my
      // profile" regardless of which business launched it.
      builder: (c, s) => MyProfileMembershipsScreen(personId: ManaSession.instance.currentPersonId ?? 'stub-person-id'),
    ),

    // --- Support/Admin (SP-001) ---------------------------------------------
    // Deliberately isolated: no MLID login, no LR-013 role-selector entry,
    // no Quick Action anywhere links here — reachable only by direct URL,
    // per SP-001's own confirmed scope as a separate internal tool outside
    // the Owner/Agent/Investor/Customer app. Uses its own in-screen stub
    // staff-acknowledgment gate, not real Support auth (that's flagged
    // future work, not part of this route).
    GoRoute(
      path: '/sp-001',
      builder: (c, s) => const Sp001AadhaarDisputeResolutionScreen(),
    ),
    GoRoute(path: '/admin-panel', builder: (c, s) => const AdminPanelScreen()),
  ],
);

class _Placeholder extends StatelessWidget {
  final String label;
  const _Placeholder(this.label);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '$label\n\nNot yet built — placeholder proves the route exists\nand matches the locked screen inventory.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
