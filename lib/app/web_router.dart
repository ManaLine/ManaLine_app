import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router.dart'
    show manaSessionRedirect, manaRootNavigatorKey, manaSelectableRoute;
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_text.dart';
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
import '../features/login_registration/state/auth_flow_state.dart' show ManaSession;
import '../shared/login_nav_args.dart';
import '../features/owner_workspace/screens/ow_013_account_review.dart';
import '../features/owner_workspace/screens/ow_016_profile.dart';
import '../features/owner_workspace/screens/ow_018_business_migration.dart';
import '../features/owner_workspace/screens/ow_bulk_onboarding_menu.dart';
import '../features/web/widgets/mana_web_shell.dart';
import '../features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart';
import '../features/owner_workspace/screens/import_screen.dart';
import '../features/owner_workspace/screens/subscription_screen.dart';
import '../features/agent_workspace/screens/ag_009_profile.dart';
import '../features/customer_workspace/screens/cw_004_my_loans.dart';
import '../features/customer_workspace/screens/cw_006_my_profile_memberships.dart' as cw006;
import '../features/investor_workspace/screens/iw_003_my_investments.dart';
import '../features/investor_workspace/screens/iw_005_my_profile_memberships.dart';
import '../shared/settings_screen.dart';
import '../shared/about_screen.dart';
import '../shared/appearance_screen.dart';
import '../shared/translation_service.dart';
import '../shared/mana_share_app.dart';
import '../features/web/screens/web_home_screen.dart';

/// THE SECOND ROUTER, AND WHY IT IS ALLOWED TO EXIST.
///
/// This project's core invariant, stated in CLAUDE.md, is one route per
/// screen ID in one router — `manaRouter` in `router.dart`. A second router
/// is a real crack in that invariant: two lists of the same routes, one
/// human away from disagreeing.
///
/// It exists anyway because Plan 3a's web build does not offer the whole
/// app — collections, loans, day closure and reports stay handset-only by
/// design — and the alternative (an allowlist *inside* `manaRouter`, gating
/// which routes resolve depending on `kIsWeb`) would scatter that decision
/// across 70+ GoRoute entries instead of stating it once, here, as a set.
/// The owner chose this trade deliberately, on the explicit condition that
/// drift between the two routers cannot go unnoticed — see
/// `test/web_router_guard_test.dart`, which is the entire mitigation for
/// having done this. It fails if this file's route set stops matching
/// [kManaWebAllowedRoutes], and it fails if either router gains a route
/// the other does not know about. Do not add a route here without adding
/// it to the constant below, and do not add either without running that
/// test.
///
/// Every screen widget below is the SAME class `manaRouter` builds — never
/// a reimplementation — so a bug fixed in one place is fixed everywhere it
/// is reachable.
const kManaWebAllowedRoutes = <String>{
  '/lr-001',
  '/lr-002',
  '/lr-004',
  '/lr-005',
  '/lr-006',
  '/lr-007',
  '/lr-008',
  '/lr-009',
  '/lr-010',
  '/lr-011',
  '/lr-012',
  '/lr-013',
  '/web-home',
  '/ow-013',
  '/ow-016',
  '/ow-018',
  '/ow-bulk-onboarding',
  '/ow-bulk-onboarding-menu',
  '/import',
  '/subscription',
  '/ag-009',
  '/cw-004',
  '/cw-006',
  '/iw-003',
  '/iw-005',
  '/profile',
  '/settings',
  '/ow-settings',
  '/ag-settings',
  '/cw-settings',
  '/iw-settings',
  '/appearance',
  '/about',
};

/// Every role lands on the web home rather than a dashboard, because none
/// of `/ow-001`, `/ag-001`, `/cw-001` or `/iw-001` are registered below —
/// this build has no workspace dashboards at all. Passed into
/// [RoleSelectorScreen] instead of its Android default.
const kWebRoleHomeRoutes = <String, String>{
  'Owner': '/web-home',
  'Investor': '/web-home',
  'Agent': '/web-home',
  'Customer': '/web-home',
};

final manaWebRouter = GoRouter(
  navigatorKey: manaRootNavigatorKey,
  initialLocation: '/lr-001',
  // Reused as-is, not reimplemented: it already sends a signed-out visitor
  // to /lr-001 and a signed-in one with no business to /lr-012, both of
  // which are in the allowlist above, and it never names a dashboard route
  // that is missing here.
  redirect: manaSessionRedirect,
  routes: <RouteBase>[
    GoRoute(path: '/lr-001', builder: (c, s) => const SystemStartupScreen()),
    GoRoute(path: '/lr-002', builder: (c, s) => const WorkspaceChoiceScreen()),
    GoRoute(path: '/lr-004', builder: (c, s) => const RegistrationFormScreen()),
    GoRoute(
      path: '/lr-005',
      builder: (c, s) {
        final extra = s.extra;
        if (extra is OtpEntryArgs) {
          return OtpVerificationScreen(purpose: extra.purpose, membershipId: extra.membershipId);
        }
        return OtpVerificationScreen(purpose: (extra as OtpPurpose?) ?? OtpPurpose.registration);
      },
    ),
    GoRoute(path: '/lr-006', builder: (c, s) => const RegistrationResultScreen()),
    GoRoute(
      path: '/lr-007',
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
    GoRoute(
      path: '/lr-012',
      builder: (c, s) => BusinessSelectorScreen(alwaysPick: s.uri.queryParameters['pick'] == '1'),
    ),
    // The one place this router disagrees with manaRouter's DEFAULT, not
    // its route set — LR-013 is still LR-013, but it is handed
    // kWebRoleHomeRoutes so "one role, straight in" lands on /web-home
    // instead of a dashboard this build does not have.
    GoRoute(
      path: '/lr-013',
      builder: (c, s) => const RoleSelectorScreen(roleHomeRoutes: kWebRoleHomeRoutes),
    ),

    // EVERY SIGNED-IN PAGE GETS THE SITE'S NAVIGATION, and it is a ShellRoute
    // that puts it there rather than twenty-one edited builders.
    //
    // Not just to save the edits -- to make forgetting one impossible. A
    // route added inside this list is wrapped by construction; a route added
    // to a list of hand-wrapped builders is wrapped only if somebody
    // remembers, and `web_navigation_test.dart` would then be the only thing
    // between that and a page with no way off it.
    //
    // AND `state.uri.path` HERE IS POPULATED. That is the whole reason this
    // is not done further up: ManaWebFrame reads the route from
    // MaterialApp.builder, ABOVE the Navigator, where the configuration has
    // no matches -- it read the empty string for months and silently matched
    // nothing. A ShellRoute's builder runs BELOW the match, so the path is
    // the thing that selected it.
    //
    // The /lr-* routes stay outside on purpose. Every destination in the rail
    // needs a session, so a rail on the login screen would be a list of links
    // that bounce you back to the login screen.
    ShellRoute(
      builder: (context, state, child) => ManaWebShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/web-home', builder: (c, s) => const ManaWebHomeScreen()),

        GoRoute(
          path: '/ow-013',
          builder: (c, s) => AccountReviewScreen(businessId: _resolveBusinessId(s)),
        ),
        GoRoute(path: '/ow-016', builder: (c, s) => const OwnerProfileScreen()),
        GoRoute(
          path: '/ow-018',
          builder: (c, s) => BusinessMigrationScreen(businessId: _resolveBusinessId(s)),
        ),
        // The website's front page for bulk onboarding, and the one thing the
        // handset signpost promises by name: download the sheets, then bring
        // them back a step at a time. Registered on both routers building the
        // same class, per the web/Android agreement above.
        GoRoute(
          path: '/ow-bulk-onboarding-menu',
          builder: (c, s) => BulkOnboardingMenuScreen(businessId: _resolveBusinessId(s)),
        ),
        GoRoute(
          path: '/ow-bulk-onboarding',
          builder: (c, s) => BulkOnboardingWizardScreen(businessId: _resolveBusinessId(s)),
        ),
        GoRoute(
          path: '/import',
          builder: (c, s) => ImportScreen(businessId: _resolveBusinessId(s)),
        ),
        GoRoute(
          path: '/subscription',
          builder: (c, s) => SubscriptionScreen(businessId: _resolveBusinessId(s)),
        ),

        GoRoute(
          path: '/ag-009',
          builder: (c, s) => Ag009ProfileScreen(
            personId: ManaSession.instance.currentPersonId ?? '',
            agentId: ManaSession.instance.lastAgentId ?? '',
            businessId: _resolveBusinessId(s),
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
          path: '/cw-006',
          builder: (c, s) => cw006.MyProfileMembershipsScreen(
              personId: (s.extra as String?) ?? ManaSession.instance.currentPersonId ?? ''),
        ),

        GoRoute(
          path: '/profile',
          builder: (c, s) => cw006.MyProfileMembershipsScreen(
            personId: (s.extra as String?) ?? ManaSession.instance.currentPersonId ?? '',
            homeRoute: '/lr-012',
          ),
        ),

        GoRoute(
          path: '/iw-003',
          builder: (c, s) => MyInvestmentsScreen(
            businessId: _resolveBusinessId(s),
            investorId: ManaSession.instance.lastInvestorId ?? '',
          ),
        ),
        GoRoute(
          path: '/iw-005',
          builder: (c, s) =>
              MyProfileMembershipsScreen(personId: ManaSession.instance.currentPersonId ?? ''),
        ),

        GoRoute(path: '/about', builder: (c, s) => const AboutScreen()),
        GoRoute(path: '/appearance', builder: (c, s) => const AppearanceScreen()),
        GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen(homeRoute: '/lr-012')),
        GoRoute(
            path: '/ow-settings',
            builder: (c, s) =>
                SettingsScreen(homeRoute: '/ow-001', businessId: s.extra as String?)),
        GoRoute(
            path: '/ag-settings',
            builder: (c, s) =>
                SettingsScreen(homeRoute: '/ag-001', businessId: s.extra as String?)),
        GoRoute(
            path: '/cw-settings',
            builder: (c, s) =>
                SettingsScreen(homeRoute: '/cw-001', businessId: s.extra as String?)),
        GoRoute(
            path: '/iw-settings',
            builder: (c, s) =>
                SettingsScreen(homeRoute: '/iw-001', businessId: s.extra as String?)),
      ],
    ),
  ].map(manaSelectableRoute).toList(),
  // A bookmarked or hand-typed /ow-006 (or any of the ~50 app-only routes)
  // must not read as a broken site — it is a real screen, just not one this
  // build carries. Named, explained, and given a way back rather than a
  // raw "page not found".
  errorBuilder: (context, state) => _WebRouteUnavailableScreen(path: state.uri.path),
);

/// Same fallback `router.dart` uses for a lost/never-carried businessId:
/// prefer `extra`, else whatever ManaSession last remembered, else empty
/// (never a fabricated id — see `_resolveBusinessId`'s own note in
/// router.dart for why a stub uuid was worse than a blank one).
String _resolveBusinessId(GoRouterState s) {
  final extra = s.extra as String?;
  if (extra != null) {
    ManaSession.instance.rememberBusinessId(extra);
    return extra;
  }
  return ManaSession.instance.lastBusinessId ?? '';
}

/// Shown by [manaWebRouter]'s errorBuilder for any path outside
/// [kManaWebAllowedRoutes] — everything from a stale bookmark to someone
/// typing an OW-006 URL they remember from a screenshot. Explains why nothing
/// loaded and offers a way forward instead of a dead end: back to the web
/// home, or the same "get the app" share used on that screen (see
/// [shareManaLineApp]'s own note — MANA LINE has no published store listing
/// yet, so a literal download link would 404 exactly like this route did).
///
/// Translation keys `web_route_unavailable_title/body/action/back` are
/// seeded by migration `20260908141736_web_home_and_route_unavailable_translation_keys.sql`.
class _WebRouteUnavailableScreen extends ConsumerWidget {
  const _WebRouteUnavailableScreen({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(translationLoaderProvider);
    return Scaffold(
      backgroundColor: ManaColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ManaSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smartphone_outlined, size: 48, color: ManaColors.brand),
                const SizedBox(height: ManaSpacing.md),
                ManaText(ref.t('web_route_unavailable_title')),
                const SizedBox(height: ManaSpacing.sm),
                Text(
                  ref.t('web_route_unavailable_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ManaColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: ManaSpacing.md),
                ManaText.raw(path, style: TextStyle(color: ManaColors.textDisabled, fontSize: 12)),
                const SizedBox(height: ManaSpacing.xl),
                FilledButton(
                  onPressed: shareManaLineApp,
                  child: ManaText(ref.t('web_route_unavailable_action')),
                ),
                const SizedBox(height: ManaSpacing.sm),
                TextButton(
                  onPressed: () => context.go('/web-home'),
                  child: ManaText(ref.t('web_route_unavailable_back')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
