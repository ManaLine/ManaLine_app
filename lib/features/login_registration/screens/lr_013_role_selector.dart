import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/business_suspension_gate.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';
import '../../../shared/network_error_handler.dart';
import 'lr_005_otp_verification.dart';
import '../../../shared/translation_service.dart';

// Fixed display order per spec — matches Phase 5 workflow text order.
const _roleOrder = ['Owner', 'Investor', 'Agent', 'Customer'];

const _roleHomeRoutes = {
  'Owner': '/ow-001',
  'Investor': '/iw-001',
  'Agent': '/ag-001',
  'Customer': '/cw-001',
};

/// LR-013 — Phase 5 Role Engine. Filters to Active + (Verified OR Not
/// Required) roles at the business selected on LR-012 (BR-188/190/191 —
/// Pending Verification roles are hidden entirely, not shown-then-
/// blocked). Applies its own 0/1/>1 collapse before rendering, same
/// pattern as LR-012.
///
/// FIXED this batch: _eligibleRoles() used to fall back to
/// `auth.memberships.first` when nothing matched, which threw "Bad
/// state: No element" whenever memberships was genuinely empty at build
/// time (e.g. reached via direct URL navigation, or a state-timing gap).
/// Now returns null in that case, and every call site bounces back to
/// LR-012 instead of crashing.
class RoleSelectorScreen extends ConsumerStatefulWidget {
  const RoleSelectorScreen({super.key, this.roleHomeRoutes = _roleHomeRoutes});

  /// Where each role lands once chosen. Defaults to the four Android
  /// dashboards; the web entrypoint passes a map sending every role to
  /// `/web-home` instead, because none of `/ow-001`, `/ag-001`, `/cw-001`
  /// or `/iw-001` exist in `manaWebRouter` — Plan 3a's web build has no
  /// workspace dashboards. Optional and defaulted so `manaRouter` (which
  /// constructs this with no arguments) is untouched.
  final Map<String, String> roleHomeRoutes;

  @override
  ConsumerState<RoleSelectorScreen> createState() => _RoleSelectorScreenState();
}

class _RoleSelectorScreenState extends ConsumerState<RoleSelectorScreen> {
  /// One OTP escalation per visit to this screen.
  ///
  /// Coming back from the OTP with the membership still unverified would
  /// otherwise send a second OTP and push the same screen again -- a loop
  /// with a blank spinner between each lap.
  bool _escalated = false;

  /// Re-reads memberships from the server.
  ///
  /// Lifted out of initState because it is needed TWICE: once on arrival,
  /// and again after the OTP screen pops back, which is the whole of this
  /// screen's defect. `memberships` is a snapshot, and the row that Role
  /// Escalation just verified is stale in it by definition.
  ///
  /// Non-fatal: on failure the cached snapshot stands, which is what this
  /// screen used before.
  Future<void> _refreshMemberships() async {
    final auth = ref.read(authFlowProvider);
    if (auth.personId == null) return;
    try {
      final fresh =
          await ref.read(authApiServiceProvider).fetchMemberships(auth.personId!);
      if (!mounted) return;
      if (fresh.isNotEmpty) ref.read(authFlowProvider.notifier).setMemberships(fresh);
    } catch (_) {
      // keep the cached list
    }
  }

  /// Somewhere usable, for every path that cannot resolve a role here.
  ///
  /// EVERY early return in this screen used to land on build()'s bare
  /// spinner, which has no app bar, no message and no way out -- an Investor
  /// accepting an invitation by OTP watched it turn until they killed the
  /// app. A screen that can neither route nor explain is worse than one that
  /// admits it is lost, so these go back to the business list.
  void _leaveToBusinessList() => context.go('/lr-012');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Refresh memberships before deciding what to show.
      //
      // `memberships` is a snapshot taken at login, and this screen's whole
      // job is listing roles from it. A role granted (or a verification
      // status corrected) after that login was invisible until the person
      // fully logged out and back in — which reads as "switch role is
      // broken", because the role genuinely is not in the list.
      //
      // Non-fatal: on failure we fall through to the cached snapshot,
      // which is what this screen used before.
      await _refreshMemberships();
      if (!mounted) return;
      _applyRoutingRule();
    });
  }

  ({String businessName, List<String> roles})? _eligibleRoles() {
    final auth = ref.read(authFlowProvider);
    final businessId = auth.selectedBusinessId;
    if (businessId == null || auth.memberships.isEmpty) return null;

    final atBusiness = auth.memberships.where((m) =>
        m.businessId == businessId &&
        m.membershipStatus == 'Active' &&
        (m.verificationStatus == 'Verified' || m.verificationStatus == 'Not Required'));

    final roles = atBusiness.map((m) => m.role).toSet().toList()
      ..sort((a, b) => _roleOrder.indexOf(a).compareTo(_roleOrder.indexOf(b)));

    final matchAtBusiness = auth.memberships.where((m) => m.businessId == businessId);
    if (matchAtBusiness.isEmpty) return null;
    final businessName = matchAtBusiness.first.businessName;

    return (businessName: businessName, roles: roles);
  }

  Future<void> _applyRoutingRule() async {
    final result = _eligibleRoles();

    if (result == null) {
      // Nothing usable in state — bounce back safely instead of crashing.
      context.go('/lr-012');
      return;
    }

    if (result.roles.isEmpty) {
      // Per spec: "should not be reachable if LR-012 already confirmed
      // an Active membership exists" — but if the person's ONLY role at
      // this business is still Pending Verification, fall back to OTP
      // Role Escalation rather than showing an empty screen (BR-191).
      _startRoleEscalation();
      return;
    }

    if (result.roles.length == 1) {
      // Direct analogue of LR-012's single-business collapse, at the role level.
      ref.read(authFlowProvider.notifier).selectRole(result.roles.first);
      await ref.read(authFlowProvider.notifier).resolveSelectedMembershipEntity();
      if (!mounted) return;
      _enterWorkspace(result.roles.first);
    }
    // >1 → render tile list below, no navigation yet.
  }

  Future<void> _startRoleEscalation() async {
    // One per visit. Without this, a membership that is still unverified
    // when the OTP screen pops back sends another OTP and pushes it again.
    if (_escalated) {
      _leaveToBusinessList();
      return;
    }
    _escalated = true;

    final auth = ref.read(authFlowProvider);
    final businessId = auth.selectedBusinessId;
    final personId = auth.personId;
    if (personId == null || businessId == null) {
      _leaveToBusinessList(); // defensive
      return;
    }

    // The specific membership row that's blocking this person from
    // reaching any eligible role at this business — the one _eligibleRoles
    // filtered OUT for being Pending Verification.
    final pending = auth.memberships.where((m) =>
        m.businessId == businessId &&
        m.membershipStatus == 'Active' &&
        m.verificationStatus == 'Pending Verification');
    if (pending.isEmpty) {
      _leaveToBusinessList(); // nothing to escalate
      return;
    }
    final membershipId = pending.first.membershipId;

    final otpId = await NetworkErrorHandler.run(context, () async {
      return ref.read(authApiServiceProvider).sendOtp(
            personId: personId,
            purpose: 'Role Escalation',
            membershipId: membershipId,
          );
    });
    if (!mounted) return;
    if (otpId == null) {
      // Network failure — the SnackBar is already up. Leaving for the
      // business list beats sitting on a spinner that will never move.
      _leaveToBusinessList();
      return;
    }

    ref.read(authFlowProvider.notifier).setPendingOtpId(otpId);
    // AWAITED. LR-005 ends Role Escalation with context.pop(), and this
    // screen's postFrameCallback has long since run -- so without this the
    // pop returned to a build() reading the SAME stale snapshot, which still
    // said Pending Verification, which rendered the spinner again with
    // nothing left alive to move it. That is the hang: not a request that
    // failed, but a screen that had already finished thinking.
    await context.push(
      '/lr-005',
      extra: OtpEntryArgs(purpose: OtpPurpose.roleEscalation, membershipId: membershipId),
    );
    if (!mounted) return;

    // The row that was Pending Verification is the row the OTP just verified.
    await _refreshMemberships();
    if (!mounted) return;
    await _applyRoutingRule();
  }

  Future<void> _selectRole(String role) async {
    ref.read(authFlowProvider.notifier).selectRole(role);
    await ref.read(authFlowProvider.notifier).resolveSelectedMembershipEntity();
    if (!mounted) return;
    _enterWorkspace(role);
  }

  /// The single door into every workspace from this screen, and therefore the
  /// one place the SP-001 check has to be.
  ///
  /// Both dispatch paths -- the single-role collapse in [_resolveRoles] and an
  /// explicit tile tap -- came through here separately before, each with its
  /// own `context.go(_homeRouteFor(...))`. Two copies of a navigation is two
  /// places to forget a gate, and the gate had already been forgotten in four
  /// others.
  ///
  /// Status and roles come from the memberships already in hand, so this adds
  /// no round trip. Owner is exempt: SP-001 aims at non-Owners, and the Owner
  /// is the person who has to reach the business to lift the suspension.
  void _enterWorkspace(String role) {
    final auth = ref.read(authFlowProvider);
    final businessId = auth.selectedBusinessId;
    final here = auth.memberships.where((m) => m.businessId == businessId);
    if (BusinessSuspensionGate.blockIfSuspended(
      context,
      businessStatus: here.isEmpty ? '' : here.first.businessStatus,
      roles: here.map((m) => m.role).toList(),
    )) {
      return;
    }
    context.go(_homeRouteFor(role), extra: businessId);
  }

  /// [role] is missing from [widget.roleHomeRoutes] only if a fifth role is
  /// ever added without also adding its entry to both the Android map here
  /// and `kWebRoleHomeRoutes` in web_router.dart. `'/ow-001'` was hardcoded
  /// here before — safe today only because every current role IS in the
  /// map, and a trap the moment that stops being true: on the web build it
  /// would send the missing role to a dashboard `manaWebRouter` never
  /// registers. Falling back to the map's own 'Owner' entry keeps the
  /// fallback platform-aware the same way the rest of the map already is;
  /// '/lr-012' (the business selector, on both routers) is the last resort
  /// if even that is absent.
  String _homeRouteFor(String role) =>
      widget.roleHomeRoutes[role] ?? widget.roleHomeRoutes['Owner'] ?? '/lr-012';

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    final result = _eligibleRoles();

    if (result == null || result.roles.length <= 1) {
      // Transient frame before the postFrameCallback's navigation fires
      // (or a genuinely empty/invalid state being bounced back to LR-012).
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('select_role'), homeRoute: '/lr-012'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: ManaColors.inkFaint,
                    child: Icon(Icons.storefront, size: 16, color: ManaColors.textSecondary),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  // Expanded, not bare: a business name is DATA and this Row
                  // has no other flexible child, so the text took its full
                  // intrinsic width and overflowed to the right. It fit in
                  // English at 1.0x and broke at 1.3x in every language —
                  // "sri satyanarayana business" alone is enough. The role
                  // tiles below already constrain their label this way.
                  Expanded(
                    child: ManaText.raw(result.businessName,
                        style: ManaType.secondary),
                  ),
                ],
              ),
              const SizedBox(height: ManaSpacing.xl),
              Expanded(
                child: ListView.separated(
                  itemCount: result.roles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: ManaSpacing.md),
                  itemBuilder: (context, i) => _roleTile(result.roles[i]),
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleTile(String role) {
    final icon = switch (role) {
      'Owner' => Icons.storefront,
      'Investor' => Icons.savings_outlined,
      'Agent' => Icons.badge_outlined,
      'Customer' => Icons.person_outline,
      _ => Icons.person_outline,
    };
    return Card(
      child: InkWell(
        onTap: () => _selectRole(role),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Row(
            children: [
              Icon(icon, color: ManaColors.brand),
              const SizedBox(width: ManaSpacing.md),
              Expanded(child: ManaText(role)),
              Icon(Icons.chevron_right, color: ManaColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
