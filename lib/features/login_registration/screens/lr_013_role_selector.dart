import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
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
  const RoleSelectorScreen({super.key});

  @override
  ConsumerState<RoleSelectorScreen> createState() => _RoleSelectorScreenState();
}

class _RoleSelectorScreenState extends ConsumerState<RoleSelectorScreen> {
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
      final auth = ref.read(authFlowProvider);
      if (auth.personId != null) {
        try {
          final fresh =
              await ref.read(authApiServiceProvider).fetchMemberships(auth.personId!);
          if (!mounted) return;
          if (fresh.isNotEmpty) ref.read(authFlowProvider.notifier).setMemberships(fresh);
        } catch (_) {
          // keep the cached list
        }
      }
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
      final businessId = ref.read(authFlowProvider).selectedBusinessId;
      context.go(_roleHomeRoutes[result.roles.first] ?? '/ow-001', extra: businessId);
    }
    // >1 → render tile list below, no navigation yet.
  }

  Future<void> _startRoleEscalation() async {
    final auth = ref.read(authFlowProvider);
    final businessId = auth.selectedBusinessId;
    final personId = auth.personId;
    if (personId == null || businessId == null) return; // defensive

    // The specific membership row that's blocking this person from
    // reaching any eligible role at this business — the one _eligibleRoles
    // filtered OUT for being Pending Verification.
    final pending = auth.memberships.where((m) =>
        m.businessId == businessId &&
        m.membershipStatus == 'Active' &&
        m.verificationStatus == 'Pending Verification');
    if (pending.isEmpty) return; // defensive — nothing to escalate
    final membershipId = pending.first.membershipId;

    final otpId = await NetworkErrorHandler.run(context, () async {
      return ref.read(authApiServiceProvider).sendOtp(
            personId: personId,
            purpose: 'Role Escalation',
            membershipId: membershipId,
          );
    });
    if (!mounted || otpId == null) return; // network failure — SnackBar already shown

    ref.read(authFlowProvider.notifier).setPendingOtpId(otpId);
    context.push(
      '/lr-005',
      extra: OtpEntryArgs(purpose: OtpPurpose.roleEscalation, membershipId: membershipId),
    );
  }

  Future<void> _selectRole(String role) async {
    ref.read(authFlowProvider.notifier).selectRole(role);
    await ref.read(authFlowProvider.notifier).resolveSelectedMembershipEntity();
    if (!mounted) return;
    final businessId = ref.read(authFlowProvider).selectedBusinessId;
    context.go(_roleHomeRoutes[role] ?? '/ow-001', extra: businessId);
  }

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
      appBar: AppBar(
        title: ManaText.raw(ref.t('select_role')),
        leading: BackButton(onPressed: () => context.go('/lr-012')),
      ),
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
                        style: TextStyle(color: ManaColors.textSecondary)),
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
