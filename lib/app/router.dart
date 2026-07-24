import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'design_showcase_screen.dart';
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
import '../features/owner_workspace/screens/ow_013_account_review.dart';
import '../features/owner_workspace/screens/ow_014_global_workflow.dart';
import '../features/owner_workspace/screens/ow_015_group_loan_management.dart';
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
      builder: (c, s) => OtpVerificationScreen(purpose: (s.extra as OtpPurpose?) ?? OtpPurpose.registration),
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
        );
      },
    ),
    GoRoute(path: '/lr-008', builder: (c, s) => const CreatePinScreen()),
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
      builder: (c, s) => OwnerHomeDashboardScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/ow-002',
      builder: (c, s) => WorkforceManagementScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/ow-003',
      builder: (c, s) => InvestorManagementScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/ow-004',
      builder: (c, s) => CustomerManagementScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/ow-005',
      builder: (c, s) => NewLoanWorkflowScreen(
        businessId: 'stub-business-id',
        prefilledCustomerId: s.extra as String?,
      ),
    ),
    GoRoute(
      path: '/ow-006',
      builder: (c, s) => CollectionModeScreen(
        businessId: 'stub-business-id',
        prefilledLoanId: s.extra as String?,
      ),
    ),
    GoRoute(
      path: '/ow-007',
      builder: (c, s) => LoanDetailsScreen(loanId: (s.extra as String?) ?? 'stub-loan-id'),
    ),
    GoRoute(
      path: '/ow-009',
      builder: (c, s) => DailyRecordBookScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/ow-010',
      builder: (c, s) => ReportHubScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/ow-011',
      builder: (c, s) => DayClosureScreen(
        businessId: (s.extra as String?) ?? 'stub-business-id',
        businessDate: DateTime.now().toIso8601String().split('T').first,
      ),
    ),
    GoRoute(path: '/ow-012', builder: (c, s) => const BusinessManagementScreen()),
    GoRoute(
      path: '/ow-013',
      builder: (c, s) => AccountReviewScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/ow-014',
      builder: (c, s) => GlobalWorkflowScreen(
        businessId: (s.extra as String?) ?? 'stub-business-id',
        currentOwnerPersonId: 'stub-person-id',
      ),
    ),
    GoRoute(
      path: '/ow-015',
      builder: (c, s) => GroupLoanManagementScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),

    // --- Agent Workspace -------------------------------------------------
    // AG-001 through AG-009 are real, built screens — full Agent Workspace
    // inventory complete (no AG-010 exists). agentId/businessId passed via
    // `extra` where relevant — falls back to stub ids so each route is
    // directly reachable during review.
    GoRoute(
      path: '/ag-001',
      builder: (c, s) => AgentHomeDashboardScreen(
        agentId: 'stub-agent-id',
        businessId: (s.extra as String?) ?? 'stub-business-id',
        initialAnchor: s.uri.queryParameters['anchor'],
      ),
    ),
    GoRoute(
      path: '/ag-002',
      builder: (c, s) => AgentCollectionModeScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/ag-003',
      builder: (c, s) => TodaysRouteScreen(
        businessId: (s.extra as String?) ?? 'stub-business-id',
        agentMembershipId: 'stub-agent-membership-id',
      ),
    ),
    GoRoute(
      path: '/ag-004',
      builder: (c, s) => AgentCustomerManagementScreen(
        businessId: (s.extra as String?) ?? 'stub-business-id',
        agentMembershipId: 'stub-agent-membership-id',
      ),
    ),
    GoRoute(
      path: '/ag-005',
      builder: (c, s) => DraftTransactionsScreen(
        businessId: (s.extra as String?) ?? 'stub-business-id',
        membershipId: 'stub-agent-membership-id',
      ),
    ),
    GoRoute(
      path: '/ag-006',
      builder: (c, s) {
        final now = DateTime.now();
        return OwnerSettlementScreen(
          businessId: (s.extra as String?) ?? 'stub-business-id',
          agentId: 'stub-agent-id',
          periodStart: DateTime(now.year, now.month, now.day),
          periodEnd: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      },
    ),
    GoRoute(
      path: '/ag-007',
      builder: (c, s) => Ag007LoanDistributionScreen(
        agentId: 'stub-agent-id',
        businessId: (s.extra as String?) ?? 'stub-business-id',
        prefilledCustomerId: null,
      ),
    ),
    GoRoute(
      path: '/ag-008',
      builder: (c, s) => Ag008NotificationsScreen(
        agentId: 'stub-agent-id',
        businessId: (s.extra as String?) ?? 'stub-business-id',
      ),
    ),
    GoRoute(
      path: '/ag-009',
      builder: (c, s) => Ag009ProfileScreen(
        personId: 'stub-person-id',
        agentId: 'stub-agent-id',
        businessId: (s.extra as String?) ?? 'stub-business-id',
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
      builder: (c, s) => CustomerHomeDashboardScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/cw-002',
      builder: (c, s) => cw002.FindABusinessScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/cw-003',
      builder: (c, s) => RequestNewLoanScreen(
        businessId: (s.extra as String?) ?? 'stub-business-id',
        customerId: 'stub-customer-id',
      ),
    ),
    GoRoute(
      path: '/cw-004',
      builder: (c, s) => MyLoansScreen(
        businessId: (s.extra as String?) ?? 'stub-business-id',
        customerId: 'stub-customer-id',
      ),
    ),
    GoRoute(
      path: '/cw-005',
      builder: (c, s) => MakeAPaymentScreen(loanId: (s.extra as String?) ?? 'stub-loan-id'),
    ),
    GoRoute(
      path: '/cw-006',
      builder: (c, s) => cw006.MyProfileMembershipsScreen(personId: (s.extra as String?) ?? 'stub-person-id'),
    ),

    // --- Investor Workspace ----------------------------------------------
    GoRoute(
      path: '/iw-001',
      builder: (c, s) => InvestorHomeDashboardScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/iw-002',
      builder: (c, s) => FindABusinessScreen(businessId: (s.extra as String?) ?? 'stub-business-id'),
    ),
    GoRoute(
      path: '/iw-003',
      builder: (c, s) => MyInvestmentsScreen(
        businessId: (s.extra as String?) ?? 'stub-business-id',
        investorId: 'stub-investor-id',
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
      // not businessId — see integration summary.
      builder: (c, s) => MyProfileMembershipsScreen(personId: (s.extra as String?) ?? 'stub-person-id'),
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
