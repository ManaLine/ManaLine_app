import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/widgets/language_selector.dart';
import '../state/auth_flow_state.dart';
import 'lr_005_otp_verification.dart';

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
class RoleSelectorScreen extends ConsumerStatefulWidget {
  const RoleSelectorScreen({super.key});

  @override
  ConsumerState<RoleSelectorScreen> createState() => _RoleSelectorScreenState();
}

class _RoleSelectorScreenState extends ConsumerState<RoleSelectorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyRoutingRule());
  }

  ({String businessName, List<String> roles}) _eligibleRoles() {
    final auth = ref.read(authFlowProvider);
    final businessId = auth.selectedBusinessId;
    final atBusiness = auth.memberships.where((m) =>
        m.businessId == businessId &&
        m.membershipStatus == 'Active' &&
        (m.verificationStatus == 'Verified' || m.verificationStatus == 'Not Required'));

    final roles = atBusiness.map((m) => m.role).toSet().toList()
      ..sort((a, b) => _roleOrder.indexOf(a).compareTo(_roleOrder.indexOf(b)));

    final businessName = auth.memberships
        .firstWhere((m) => m.businessId == businessId, orElse: () => atBusiness.isNotEmpty ? atBusiness.first : auth.memberships.first)
        .businessName;

    return (businessName: businessName, roles: roles);
  }

  void _applyRoutingRule() {
    final result = _eligibleRoles();

    if (result.roles.isEmpty) {
      // Per spec: "should not be reachable if LR-012 already confirmed
      // an Active membership exists" — but if the person's ONLY role at
      // this business is still Pending Verification, fall back to OTP
      // Role Escalation rather than showing an empty screen (BR-191).
      context.push('/lr-005', extra: OtpPurpose.roleEscalation);
      return;
    }

    if (result.roles.length == 1) {
      // Direct analogue of LR-012's single-business collapse, at the role level.
      ref.read(authFlowProvider.notifier).selectRole(result.roles.first);
      context.go(_roleHomeRoutes[result.roles.first] ?? '/ow-001');
    }
    // >1 → render tile list below, no navigation yet.
  }

  void _selectRole(String role) {
    ref.read(authFlowProvider.notifier).selectRole(role);
    context.go(_roleHomeRoutes[role] ?? '/ow-001');
  }

  @override
  Widget build(BuildContext context) {
    final result = _eligibleRoles();
    final lang = ref.watch(authFlowProvider).language;

    if (result.roles.length <= 1) {
      // Transient frame before the postFrameCallback's navigation fires.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('select role'),
        leading: BackButton(onPressed: () => context.go('/lr-012')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: ManaColors.inkFaint,
                    child: Icon(Icons.storefront, size: 16, color: ManaColors.textSecondary),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  ManaText.raw(result.businessName,
                      style: const TextStyle(color: ManaColors.textSecondary)),
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
              ManaLanguageSelector(
                current: lang,
                onChanged: (l) => ref.read(authFlowProvider.notifier).setLanguage(l),
              ),
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
              Icon(icon, color: ManaColors.brass),
              const SizedBox(width: ManaSpacing.md),
              Expanded(child: ManaText(role)),
              const Icon(Icons.chevron_right, color: ManaColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
