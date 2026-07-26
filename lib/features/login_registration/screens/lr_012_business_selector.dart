import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/widgets/language_selector.dart';
import '../state/auth_flow_state.dart';

class _BusinessGroup {
  final String businessId;
  final String businessName;
  final String businessStatus;
  final List<String> roles;
  _BusinessGroup({
    required this.businessId,
    required this.businessName,
    required this.businessStatus,
    required this.roles,
  });
}

/// LR-012 — Phase 4 Business Router. Per spec, the 0/1/>1 collapse rules
/// are applied BEFORE rendering — this screen either never shows (0 or 1
/// distinct Active business) or shows the full card list (>1). Reached
/// from LR-009/LR-008 (first login/daily login) via authFlowProvider's
/// memberships, already in hand from the login response — no separate
/// "list my businesses" call, per spec's DATA SOURCE section.
class BusinessSelectorScreen extends ConsumerStatefulWidget {
  const BusinessSelectorScreen({super.key});

  @override
  ConsumerState<BusinessSelectorScreen> createState() => _BusinessSelectorScreenState();
}

class _BusinessSelectorScreenState extends ConsumerState<BusinessSelectorScreen> {
  @override
  void initState() {
    super.initState();
    // Routing decision must happen before/at render, not on a button —
    // WidgetsBinding defers it one frame so context.go() during initState
    // doesn't fight the framework's own build-in-progress.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyRoutingRule());
  }

  List<_BusinessGroup> _activeBusinessGroups() {
    final memberships = ref.read(authFlowProvider).memberships;
    // Only 'Active' membership rows count toward routing/display (BR-192/203) —
    // Pending/Suspended/Removed are excluded entirely, not shown-then-blocked.
    final active = memberships.where((m) => m.membershipStatus == 'Active');

    final byBusinessId = <String, _BusinessGroup>{};
    for (final m in active) {
      final existing = byBusinessId[m.businessId];
      if (existing == null) {
        byBusinessId[m.businessId] = _BusinessGroup(
          businessId: m.businessId,
          businessName: m.businessName,
          businessStatus: m.businessStatus,
          roles: [m.role],
        );
      } else {
        existing.roles.add(m.role);
      }
    }
    return byBusinessId.values.toList();
  }

  void _applyRoutingRule() {
    final groups = _activeBusinessGroups();
    if (groups.length == 1) {
      // "Automatically Open Business" — LR-012 must never appear for a
      // single-business user.
      ref.read(authFlowProvider.notifier).selectBusiness(groups.first.businessId);
      context.go('/lr-013');
    }
    // 0 groups → render S0 below (build() handles this, no navigation).
    // >1 groups → render the card list below (build() handles this too).
  }

  void _selectBusiness(String businessId) {
    ref.read(authFlowProvider.notifier).selectBusiness(businessId);
    context.push('/lr-013');
  }

  @override
  Widget build(BuildContext context) {
    final groups = _activeBusinessGroups();
    final lang = ref.watch(authFlowProvider).language;

    if (groups.isEmpty) return _noBusinessLinked(context);
    if (groups.length == 1) {
      // Transient frame before the postFrameCallback above fires — avoid
      // flashing the card list for a single-business user.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const ManaText('select business')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            children: [
              Expanded(
                child: ListView.separated(
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: ManaSpacing.md),
                  itemBuilder: (context, i) => _businessCard(groups[i]),
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

  Widget _businessCard(_BusinessGroup g) {
    final suspended = g.businessStatus != 'Active';
    return Card(
      child: InkWell(
        onTap: () => _selectBusiness(g.businessId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: ManaColors.inkFaint,
                child: Icon(Icons.storefront, color: ManaColors.textSecondary),
              ),
              const SizedBox(width: ManaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: ManaText.raw(g.businessName,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        if (suspended) ...[
                          const SizedBox(width: ManaSpacing.sm),
                          ManaStatusPill(label: g.businessStatus, status: ManaStatus.bad),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    ManaText.raw(g.roles.join(', '),
                        style: const TextStyle(color: ManaColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: ManaColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noBusinessLinked(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.storefront_outlined, size: 48, color: ManaColors.textSecondary),
              const SizedBox(height: ManaSpacing.md),
              const ManaText('no business linked', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: ManaSpacing.sm),
              const ManaText.raw(
                'You\'re not yet linked to a business. Create a new one, or '
                'contact the Owner if you\'re expecting an existing invitation.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ManaSpacing.xl),
              ElevatedButton(
                // OW-000 First Business Setup — reached with
                // isAdditionalBusiness=false since this is the 0-business
                // path (per OW-000's own ENTRY POINT: "0 Businesses Linked").
                onPressed: () => context.push('/ow-000', extra: false),
                child: const ManaText('create new business'),
              ),
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton(
                // RESOLVED per spec: deep-links to the Pending membership's
                // business contact info if one exists; static fallback
                // otherwise. No Pending-membership signal available in
                // this stub (only Active rows are modeled), so this
                // always shows the static fallback for now.
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Support: support@manaline.app')),
                  );
                },
                child: const ManaText('contact owner'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
