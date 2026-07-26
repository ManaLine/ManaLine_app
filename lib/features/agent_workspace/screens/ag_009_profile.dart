import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../state/agent_dashboard_state.dart' show AgentAreaAssignment;
import '../state/agent_profile_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _date = DateFormat('d MMM yyyy');

/// AG-009 — Profile. Final screen in the Agent Workspace inventory
/// (AG-001–AG-009, no AG-010 per AG-001's own closing note). Pure view
/// screen — no self-edit of identity, status, route, or compensation
/// anywhere; all of that is Owner-controlled via OW-002 Workforce
/// Management (not this chat's scope).
class Ag009ProfileScreen extends ConsumerStatefulWidget {
  final String personId;
  final String agentId;
  final String businessId;
  const Ag009ProfileScreen({
    super.key,
    required this.personId,
    required this.agentId,
    required this.businessId,
  });

  @override
  ConsumerState<Ag009ProfileScreen> createState() => _Ag009ProfileScreenState();
}

class _Ag009ProfileScreenState extends ConsumerState<Ag009ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentProfileProvider.notifier).load(
            personId: widget.personId,
            agentId: widget.agentId,
            businessId: widget.businessId,
          );
    });
  }

  Future<void> _reload() => ref.read(agentProfileProvider.notifier).load(
        personId: widget.personId,
        agentId: widget.agentId,
        businessId: widget.businessId,
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const ManaText('profile')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: state.loading && state.profile == null
              ? const Center(child: CircularProgressIndicator())
              : state.profile == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(ManaSpacing.lg),
                        child: ManaText.raw(
                          state.error ?? 'Could not load profile.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: ManaColors.statusBad),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      children: [
                        _BasicProfileCard(profile: state.profile!),
                        const SizedBox(height: ManaSpacing.xl),
                        ManaText('route / area assignment', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: ManaSpacing.sm),
                        _RouteAreaSummary(assignments: state.areaAssignments),
                        const SizedBox(height: ManaSpacing.xl),
                        ManaText('my compensation', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: ManaSpacing.sm),
                        _CompensationLinkOutRow(
                          summary: state.compensationSummary,
                          businessId: widget.businessId,
                        ),
                        if (state.memberships.length > 1) ...[
                          const SizedBox(height: ManaSpacing.xl),
                          ManaText('other business memberships', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: ManaSpacing.xs),
                          const ManaText.raw(
                            'Each Owner sees only their own tenancy\'s data for you — nothing here is shared or blended across businesses.',
                            style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
                          ),
                          const SizedBox(height: ManaSpacing.sm),
                          ...state.memberships.map((m) => _MembershipTile(membership: m)),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }
}

/// BASIC PROFILE (read-only): Photo, Name, MLID/Agent ID, Phone, Joined
/// Date, Current Status. Identity editing is not allowed by the Agent —
/// same locked pattern as AG-004 — so no edit affordance anywhere here,
/// not even a disabled one.
class _BasicProfileCard extends StatelessWidget {
  final AgentProfileSummary profile;
  const _BasicProfileCard({required this.profile});

  ManaStatus get _statusPillStatus => switch (profile.currentStatus) {
        'Active' => ManaStatus.good,
        'Suspended' || 'Removed' => ManaStatus.bad,
        _ => ManaStatus.warn,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ManaVerificationRing(
                  isVerified: true,
                  photo: profile.profilePhotoUrl != null ? NetworkImage(profile.profilePhotoUrl!) : null,
                  size: 56,
                ),
                const SizedBox(width: ManaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(profile.fullName, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 2),
                      ManaText.raw(profile.mlid, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                ManaStatusPill(label: profile.currentStatus, status: _statusPillStatus),
              ],
            ),
            const Divider(height: ManaSpacing.xl),
            _FieldRow(label: 'phone', value: profile.phoneNumber ?? '—'),
            const SizedBox(height: ManaSpacing.sm),
            _FieldRow(label: 'joined date', value: _date.format(profile.joinedDate)),
          ],
        ),
      ),
    );
  }
}

/// A locked, view-only field row — deliberately has no `onEdit` affordance
/// of any kind (not even disabled), since identity editing is not allowed
/// by the Agent anywhere on this screen.
class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  const _FieldRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              ManaText.raw(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.lock_outline, size: 16, color: ManaColors.textDisabled),
        ),
      ],
    );
  }
}

/// ROUTE / AREA ASSIGNMENT (read-only) — sourced from
/// `agent_area_assignments`, the same backing table AG-003 already reads.
/// Shown here as a summary only: no reordering, no selection state, not
/// re-implemented.
class _RouteAreaSummary extends StatelessWidget {
  final List<AgentAreaAssignment> assignments;
  const _RouteAreaSummary({required this.assignments});

  @override
  Widget build(BuildContext context) {
    final enabled = assignments.where((a) => a.enabled).toList();
    if (enabled.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(ManaSpacing.lg),
          child: ManaText.raw('No Operating Areas currently assigned.', style: TextStyle(color: ManaColors.textSecondary)),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
        child: Column(
          children: enabled
              .map((a) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.route_outlined, color: ManaColors.brass),
                    title: ManaText.raw(a.areaName),
                    trailing: a.selectedInSession
                        ? const ManaStatusPill(label: 'In Session', status: ManaStatus.good)
                        : null,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

/// MY COMPENSATION (link out, not duplicated). Per spec: same pattern
/// already locked at IW-005 → IW-003 — a single summary row (Fixed
/// Salary + Salary Cycle status at a glance) that opens the full panel
/// already locked at AG-001, rather than re-rendering Advances Deducted /
/// Shorts Deducted / Pending Salary / Salary History here.
class _CompensationLinkOutRow extends StatelessWidget {
  final AgentCompensationSummary? summary;
  final String businessId;
  const _CompensationLinkOutRow({required this.summary, required this.businessId});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined, color: ManaColors.brass),
        title: ManaText.raw(s != null ? _currency.format(s.fixedSalary) : '—',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: ManaText.raw(s?.salaryCycleStatus ?? 'Compensation not yet available',
            style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
        trailing: const Icon(Icons.chevron_right),
        // Opens AG-001, scrolled/anchored to its "MY COMPENSATION
        // (Read-Only, Set By Owner)" panel — see END RESULT integration
        // note for the exact anchor mechanism this assumes (a `?anchor=
        // compensation` query param on /ag-001 that AG-001 does not yet
        // read; flagged for master chat to wire).
        onTap: () => context.push('/ag-001?anchor=compensation', extra: businessId),
      ),
    );
  }
}

/// Multi-Owner tenancy (BR-202/BR-203) — same tap-to-switch pattern
/// IW-005 already established for its Business Memberships list. One
/// Agent identity may work under N Owners; each Owner's panel is fully
/// isolated, never blended here.
class _MembershipTile extends StatelessWidget {
  final AgentBusinessMembership membership;
  const _MembershipTile({required this.membership});

  ManaStatus get _pillStatus => switch (membership.membershipStatus) {
        'Active' => ManaStatus.good,
        'Suspended' || 'Removed' => ManaStatus.bad,
        _ => ManaStatus.warn,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        title: ManaText.raw(membership.businessName),
        subtitle: const ManaText('agent'),
        trailing: ManaStatusPill(label: membership.membershipStatus, status: _pillStatus),
        onTap: () => context.push('/ag-001', extra: membership.businessId),
      ),
    );
  }
}
