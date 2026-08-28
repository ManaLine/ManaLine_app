import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'design_showcase_screen.dart';
import '../features/login_registration/state/auth_flow_state.dart';
import '../features/login_registration/screens/lr_001_system_startup.dart';
import '../features/login_registration/screens/lr_002_workspace_choice.dart';
import '../features/login_registration/screens/lr_004_registration_form.dart';
import '../features/login_registration/screens/lr_005_otp_verification.dart';
import '../features/login_registration/screens/lr_006_registration_result.dart';
import '../features/login_registration/screens/lr_008_create_pin.dart';
import '../features/login_registration/screens/lr_009_daily_login.dart';
import '../features/login_registration/screens/lr_010_forgot_password.dart';
import '../features/login_registration/screens/lr_011_forgot_pin.dart';
import '../features/login_registration/screens/lr_012_business_selector.dart';
import '../features/login_registration/screens/lr_013_role_selector.dart';
import '../shared/business_suspension_gate.dart' show BusinessSuspendedScreen;
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
import '../features/owner_workspace/state/global_workflow_state.dart' show MemberType;
import '../features/owner_workspace/screens/ow_014_profile_completion.dart';
import '../features/owner_workspace/screens/ow_015_group_loan_management.dart';
import '../features/owner_workspace/screens/ow_016_profile.dart';
import '../features/owner_workspace/screens/ow_017_statement_screen.dart';
import '../features/owner_workspace/screens/ow_017_transaction_history.dart';
import '../features/owner_workspace/screens/ow_trash_screen.dart';
import '../features/owner_workspace/screens/ow_018_business_migration.dart';
import '../features/owner_workspace/screens/ow_019_cheti_management.dart';
import '../features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart';
import '../features/owner_workspace/screens/backup_screen.dart';
import '../features/owner_workspace/screens/import_screen.dart';
import '../features/owner_workspace/screens/subscription_screen.dart';
import '../features/owner_workspace/screens/business_transfer_screen.dart';
import '../features/owner_workspace/screens/loan_requests_screen.dart';
import '../features/owner_workspace/screens/withdrawal_requests_screen.dart';
import '../shared/notifications_screen.dart';
import '../shared/settings_screen.dart';
import '../shared/account_closure_screen.dart';
import '../shared/about_screen.dart';
import '../shared/appearance_screen.dart';
import '../features/agent_workspace/screens/ag_001_agent_home_dashboard.dart';
import '../features/agent_workspace/screens/ag_002_collection_mode.dart';
import '../features/agent_workspace/screens/ag_004_customer_management.dart';
import '../features/agent_workspace/screens/ag_005_draft_transactions.dart';
import '../features/agent_workspace/screens/ag_006_owner_settlement.dart';
import '../features/agent_workspace/screens/ag_007_loan_distribution.dart';
import '../features/agent_workspace/screens/ag_008_notifications.dart';
import '../features/agent_workspace/screens/ag_009_profile.dart';
import '../features/agent_workspace/screens/ag_010_transaction_history.dart';
import '../features/customer_workspace/screens/cw_001_customer_home_dashboard.dart';
import '../features/customer_workspace/screens/cw_002_find_a_business.dart' as cw002;
import '../features/customer_workspace/screens/cw_003_request_new_loan.dart';
import '../features/customer_workspace/screens/cw_004_my_loans.dart';
import '../features/customer_workspace/screens/cw_005_make_a_payment.dart';
import '../features/customer_workspace/screens/cw_006_my_profile_memberships.dart' as cw006;
import '../features/investor_workspace/screens/iw_001_investor_home_dashboard.dart';
import '../features/support_admin/screens/sp_001_aadhaar_dispute_resolution.dart';
import '../features/admin/admin_panel_screen.dart';
import '../features/admin/screens/admin_login_screen.dart';
import '../features/admin/screens/admin_forgot_password_screen.dart';
import '../features/investor_workspace/screens/iw_002_find_a_business.dart';
import '../features/investor_workspace/screens/iw_003_my_investments.dart';
import '../features/investor_workspace/screens/iw_004_request_withdrawal.dart';
import '../features/investor_workspace/screens/iw_005_my_profile_memberships.dart';
import '../shared/mana_time.dart';
import '../shared/widgets/recent_deletes_screen.dart';

/// Route map mirrors the locked screen inventory 1:1 — file/screen
/// numbers double as route names, so anyone cross-referencing this
/// router against the UI spec finds a direct match, not a renamed
/// abstraction layer.
///
/// Every screen in the inventory is built (no more `_ScaffoldPlaceholder`);
/// remaining stubs are the deliberate deep-link fallbacks below.
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
  // Empty, not a fake uuid.
  //
  // This returned 'stub-business-id' when the session had nothing, and every
  // screen took it as real. Postgres then refused it -- invalid input syntax
  // for type uuid -- and the person got "Something went wrong" on a screen
  // that never had a chance. See manaSessionRedirect below: a route that needs
  // an id it does not have is now sent somewhere it can recover, rather than
  // opening onto a guaranteed failure.
  return ManaSession.instance.lastBusinessId ?? '';
}

/// Screen-ID prefixes that cannot render without a business.
const _needsBusiness = ['/ow-', '/ag-'];

/// Where an unusable route goes instead of opening.
///
/// Nineteen routes fell back to a fabricated id -- 'stub-business-id',
/// '', '' and the rest -- whenever the session had
/// lost the real one. The screens opened, queried with a string Postgres
/// cannot cast, and reported a generic failure. The session had simply
/// expired, which the app knew and did not say.
///
/// Sent to the business selector when there is a person but no business, and
/// to the start when there is no person at all. Login and registration are
/// left alone: they are how somebody gets a session in the first place.
String? manaSessionRedirect(BuildContext context, GoRouterState state) =>
    manaSessionRedirectFor(state.uri.path);

/// The decision itself, free of a BuildContext so it can be tested directly.
String? manaSessionRedirectFor(String path) {
  // Login, registration and admin are how a session is obtained. Redirecting
  // them for want of a session would loop forever, and admin identities live
  // in admin_accounts, so currentPersonId is null for them and always will be.
  if (path.startsWith('/lr-') || path.startsWith('/admin') || path == '/_design') {
    return null;
  }
  if (ManaSession.instance.currentPersonId == null) return '/lr-001';
  if (_needsBusiness.any(path.startsWith) &&
      (ManaSession.instance.lastBusinessId ?? '').isEmpty) {
    return '/lr-012';
  }
  return null;
}

/// The root navigator, so the app shell can ask whether there is anything to
/// go back to. GoRouter's own canPop() only knows about routes it matched --
/// a screen opened with Navigator.push (the collection entry screen, the
/// business detail screen) is invisible to it, and treating those as "nothing
/// to pop" is how Back would close the app from inside a form.
final manaRootNavigatorKey = GlobalKey<NavigatorState>();

final manaRouter = GoRouter(
  navigatorKey: manaRootNavigatorKey,
  initialLocation: '/lr-001',
  // Checked before any route builds, so a screen that cannot work never
  // renders and then fails.
  redirect: manaSessionRedirect,
  routes: [
    // Deep-link to the app's home URL lands here rather than throwing a
    // "no match" — the app has no root screen, only the LR-001 startup flow.
    GoRoute(
      path: '/',
      redirect: (context, state) => '/lr-001',
    ),
    // Temporary — remove once you're done reviewing the design system.
    // Reach it manually by navigating to /_design.
    GoRoute(path: '/_design', builder: (c, s) => const DesignShowcaseScreen()),

    // --- Login & Registration (Module) --------------------------------
    // LR-001 through LR-008 are real, built screens. LR-009 through
    // LR-013 are still placeholders — next batch.
    GoRoute(path: '/lr-001', builder: (c, s) => const SystemStartupScreen()),
    GoRoute(path: '/lr-002', builder: (c, s) => const WorkspaceChoiceScreen()),
    // /lr-003 (Login-or-Register choice) is deliberately gone. It asked
    // "already registered?" — a question LR-009 answers by itself, showing
    // the PIN pad when the device has a PIN and the password form (with a
    // Register button) when it does not. Logout now lands on /lr-009.
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
      // PIN and password are one screen now (see DailyLoginScreen's own
      // note). This ID is kept and still carries every argument it did
      // before — it just opens that screen already on the password form,
      // so nothing that pushes here had to change.
      builder: (c, s) {
        final args = s.extra as LoginStepDownArgs?;
        return DailyLoginScreen(
          startInPasswordMode: true,
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
        focusAgentId: s.uri.queryParameters['agent'],
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
        initialAction: s.uri.queryParameters['action'],
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
      // The loan to open on is a QUERY PARAM, not `extra`.
      //
      // It read `s.extra as String?` while every nav-bar tap arrives here as
      // `go('/ow-006', extra: businessId)` -- so the footer handed this screen
      // a business id and it went looking for a loan with that id. It found
      // none and did nothing, which is why nobody noticed; one `extra` cannot
      // mean two things.
      builder: (c, s) => CollectionModeScreen(
        businessId: _resolveBusinessId(s),
        prefilledLoanId: s.uri.queryParameters['loan'],
      ),
    ),
    // Universal Search has a route because every Owner screen's header opens
    // it. It was reachable only from OW-001, pushed as a MaterialPageRoute --
    // which would put it above the router's pages on every screen that now
    // offers it, the same shape that broke the Agent's back button.
    GoRoute(
      path: '/ow-search',
      builder: (c, s) => UniversalSearchScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ow-007',
      builder: (c, s) => LoanDetailsScreen(loanId: (s.extra as String?) ?? ''),
    ),
    GoRoute(
      path: '/ow-009',
      builder: (c, s) => DailyRecordBookScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ow-010',
      builder: (c, s) => ReportHubScreen(businessId: _resolveBusinessId(s)),
    ),
    // Not a screen-id route: Recent Deletes is not a spec screen, so it has
    // no locked id. Giving it one would put a route in the id namespace that
    // no spec screen answers to and break the 1:1 cross-reference; a named
    // path keeps that contract intact.
    // The Owner's Trash: the whole bin, with restore and delete-forever.
    // /recent-deletes stays as the Daily Record Book's read-only view of the
    // same rows -- it is reached mid-task and should not offer to destroy
    // anything.
    GoRoute(
      path: '/ow-trash',
      builder: (c, s) => OwnerTrashScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/recent-deletes',
      builder: (c, s) => RecentDeletesScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ow-011',
      builder: (c, s) => DayClosureScreen(
        businessId: _resolveBusinessId(s),
        businessDate: manaBusinessDate(),
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
        currentOwnerPersonId: ManaSession.instance.currentPersonId ?? '',
        // Each entry point already knows which kind of member it is
        // creating, so Step 1 is pre-filled rather than asked again.
        preSelectedType: switch (s.uri.queryParameters['type']) {
          'customer' => MemberType.customer,
          'agent' => MemberType.agent,
          'investor' => MemberType.investor,
          _ => null,
        },
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
    // One inbox for every workspace. Not under a workspace prefix on
    // purpose: notifications are per PERSON, and someone who is an Agent in
    // one business and a Customer in another should not have to switch
    // workspace to see what is waiting.
    GoRoute(path: '/notifications', builder: (c, s) => const NotificationsScreen()),
    GoRoute(path: '/ow-016', builder: (c, s) => const OwnerProfileScreen()),
    GoRoute(
      path: '/ow-017',
      builder: (c, s) => TransactionHistoryScreen(businessId: _resolveBusinessId(s)),
    ),
    // My Statements — the export flow off OW-017's header, not a separate
    // spec screen, so it hangs off OW-017's own id rather than claiming one.
    GoRoute(
      path: '/ow-017-statement',
      builder: (c, s) => StatementScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ow-018',
      builder: (c, s) => BusinessMigrationScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/ow-019',
      builder: (c, s) => ChetiManagementScreen(businessId: _resolveBusinessId(s)),
    ),
    // Not a spec screen ID: reached from OW-018 (Business Migration) the same
    // way /import is reached from Settings.
    GoRoute(
      path: '/ow-bulk-onboarding',
      builder: (c, s) => BulkOnboardingWizardScreen(businessId: _resolveBusinessId(s)),
    ),
    // Not a spec screen ID: Backup is reached from Settings, which is itself
    // shared across all four workspaces, so it has no OW-nnn of its own.
    GoRoute(
      path: '/backup',
      builder: (c, s) => BackupScreen(businessId: _resolveBusinessId(s)),
    ),
    // Import lives beside Backup for the same reason: it is reached from
    // Settings, which is shared across workspaces, so it has no OW-nnn.
    GoRoute(
      path: '/import',
      builder: (c, s) => ImportScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(
      path: '/subscription',
      builder: (c, s) => SubscriptionScreen(businessId: _resolveBusinessId(s)),
    ),
    // No businessId: switching off or deleting an account is a person-level
    // act, not a business-level one, and it is reachable from every workspace.
    GoRoute(
      path: '/account-closure',
      builder: (c, s) => const AccountClosureScreen(),
    ),
    GoRoute(
      path: '/business-transfer',
      builder: (c, s) =>
          BusinessTransferScreen(businessId: _resolveBusinessId(s)),
    ),
    GoRoute(path: '/about', builder: (c, s) => const AboutScreen()),
    GoRoute(path: '/appearance', builder: (c, s) => const AppearanceScreen()),
    // Reached from LR-012, before any workspace has been chosen — so it goes
    // back to the business selector and shows no workspace-specific Profile.
    GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen(homeRoute: '/lr-012')),
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
    // AG-001 through AG-010 are real, built screens, and all ten are
    // registered. AG-010 used to be the exception — it was pushed by AG-001
    // with the agent's membershipId "which no deep link can supply", so it
    // had no route. It has one now, resolved the same way AG-004 and AG-005
    // already resolve theirs: from ManaSession. That was not a cosmetic
    // change. The Agent's footer pushed its tabs with Navigator.push because
    // History had nowhere to go(), and a pushed page sits ABOVE the router's
    // pages — so AG-002's `context.go('/ag-001')` back button rewrote the
    // stack underneath a page that stayed on screen, and Back looked dead.
    // agentId/businessId passed via `extra` where relevant — falls back to
    // stub ids so each route is directly reachable during review.
    GoRoute(
      path: '/ag-001',
      builder: (c, s) => AgentHomeDashboardScreen(
        agentId: ManaSession.instance.lastAgentId ?? '',
        businessId: _resolveBusinessId(s),
        initialAnchor: s.uri.queryParameters['anchor'],
      ),
    ),
    GoRoute(
      path: '/ag-002',
      builder: (c, s) => AgentCollectionModeScreen(
        businessId: _resolveBusinessId(s),
        focusLoanId: s.uri.queryParameters['loan'],
      ),
    ),
    // AG-003 was Today's Route / Area Work Session. It listed the same loans
    // as Collection Mode, off its own query, and offered a subset of what
    // Collection Mode does -- two screens for one job, and only one of them
    // was maintained. Merged into Collection Mode.
    //
    // The route stays registered because a screen ID is the routing contract:
    // the ID is locked even though the screen is gone, and a deep link or a
    // stored destination pointing here must still land somewhere real rather
    // than on a 404.
    GoRoute(
      path: '/ag-003',
      builder: (c, s) => AgentCollectionModeScreen(
        businessId: _resolveBusinessId(s),
        focusLoanId: s.uri.queryParameters['loan'],
      ),
    ),
    GoRoute(
      path: '/ag-004',
      builder: (c, s) => AgentCustomerManagementScreen(
        businessId: _resolveBusinessId(s),
        agentMembershipId: ManaSession.instance.lastMembershipId ?? '',
      ),
    ),
    GoRoute(
      path: '/ag-005',
      builder: (c, s) => DraftTransactionsScreen(
        businessId: _resolveBusinessId(s),
        membershipId: ManaSession.instance.lastMembershipId ?? '',
      ),
    ),
    GoRoute(
      path: '/ag-006',
      builder: (c, s) {
        final now = DateTime.now();
        return OwnerSettlementScreen(
          businessId: _resolveBusinessId(s),
          agentId: ManaSession.instance.lastAgentId ?? '',
          periodStart: DateTime(now.year, now.month, now.day),
          periodEnd: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      },
    ),
    GoRoute(
      path: '/ag-007',
      builder: (c, s) => Ag007LoanDistributionScreen(
        agentId: ManaSession.instance.lastAgentId ?? '',
        businessId: _resolveBusinessId(s),
        prefilledCustomerId: null,
      ),
    ),
    GoRoute(
      path: '/ag-010',
      builder: (c, s) => Ag010TransactionHistoryScreen(
        businessId: _resolveBusinessId(s),
        agentMembershipId: ManaSession.instance.lastMembershipId ?? '',
      ),
    ),
    GoRoute(
      path: '/ag-008',
      builder: (c, s) => Ag008NotificationsScreen(
        agentId: ManaSession.instance.lastAgentId ?? '',
        businessId: _resolveBusinessId(s),
      ),
    ),
    GoRoute(
      path: '/ag-009',
      builder: (c, s) => Ag009ProfileScreen(
        personId: ManaSession.instance.currentPersonId ?? '',
        agentId: ManaSession.instance.lastAgentId ?? '',
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
        customerId: ManaSession.instance.lastCustomerId ?? '',
      ),
    ),
    GoRoute(
      path: '/cw-004',
      builder: (c, s) => MyLoansScreen(
        businessId: _resolveBusinessId(s),
        customerId: ManaSession.instance.lastCustomerId ?? '',
      ),
    ),
    GoRoute(
      path: '/cw-005',
      builder: (c, s) => MakeAPaymentScreen(loanId: (s.extra as String?) ?? ''),
    ),
    GoRoute(
      path: '/cw-006',
      builder: (c, s) => cw006.MyProfileMembershipsScreen(personId: (s.extra as String?) ?? ManaSession.instance.currentPersonId ?? ''),
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
        investorId: ManaSession.instance.lastInvestorId ?? '',
      ),
    ),
    GoRoute(
      path: '/iw-004',
      builder: (c, s) => RequestWithdrawalScreen(investmentId: (s.extra as String?) ?? ''),
    ),
    GoRoute(
      path: '/iw-005',
      // NOTE: IW-001's Quick Actions currently pass businessId as `extra`
      // for every destination uniformly, but this screen needs personId,
      // not businessId — see integration summary. `extra` is therefore
      // ignored here entirely rather than misread as personId; the
      // logged-in person's own id is always the right value for "my
      // profile" regardless of which business launched it.
      builder: (c, s) => MyProfileMembershipsScreen(personId: ManaSession.instance.currentPersonId ?? ''),
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
    // Platform Admin's own login — separate identity system from every
    // other route above (admin_accounts, not persons). Not linked from any
    // regular Owner/Agent/Customer/Investor screen.
    GoRoute(path: '/admin-login', builder: (c, s) => const AdminLoginScreen()),
    GoRoute(path: '/admin-forgot-password', builder: (c, s) => const AdminForgotPasswordScreen()),
    GoRoute(path: '/business-suspended', builder: (c, s) => const BusinessSuspendedScreen()),
  ].map(manaSelectable).toList(),
);

/// Makes every screen's text selectable, and therefore copyable.
///
/// Nothing in the app was. An MLID, a loan number, a mobile number or an
/// amount could be read off the glass and retyped, but never copied into a
/// message or a search box -- and retyping a 12-digit MLID is exactly where a
/// wrong customer comes from.
///
/// Wrapped HERE, around each route's own builder, and NOT in
/// MaterialApp.builder. SelectableRegion requires an Overlay ancestor; the
/// app builder sits above the Navigator that provides one, so putting it there
/// threw during build and replaced every screen with an ErrorWidget. A route's
/// builder runs inside the Navigator, where the Overlay exists.
///
/// Doing it once here rather than per screen is what keeps it true for the
/// screens nobody revisits.
GoRoute manaSelectable(GoRoute r) => GoRoute(
      path: r.path,
      name: r.name,
      redirect: r.redirect,
      builder: r.builder == null
          ? null
          : (context, state) => SelectionArea(child: r.builder!(context, state)),
      routes: [
        for (final child in r.routes)
          if (child is GoRoute) manaSelectable(child) else child,
      ],
    );
