import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_stat_strip.dart';
import '../../../shared/network_error_handler.dart';
import '../../owner_workspace/state/collection_mode_state.dart' show collectionModeProvider, CollectionDueRow;
import '../../owner_workspace/screens/ow_006_collection_mode.dart' show CollectionEntryScreen;
import '../state/todays_route_state.dart';
import 'ag_004_customer_management.dart' show AgentCustomerProfileScreen;

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// AG-003 — Today's Route. Display-only ordered visit sequence for the
/// active Business Session's enabled Area(s) — grouped by village, ordered
/// by `route_locations.visit_order`. Agent cannot reorder or add/remove
/// customers here; only Owner assigns/reorders routes.
class TodaysRouteScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String agentMembershipId;
  const TodaysRouteScreen({super.key, required this.businessId, required this.agentMembershipId});

  @override
  ConsumerState<TodaysRouteScreen> createState() => _TodaysRouteScreenState();
}

class _TodaysRouteScreenState extends ConsumerState<TodaysRouteScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(todaysRouteProvider.notifier).load(
            businessId: widget.businessId,
            agentMembershipId: widget.agentMembershipId,
          );
    });
  }

  Future<void> _reload() => ref.read(todaysRouteProvider.notifier).load(
        businessId: widget.businessId,
        agentMembershipId: widget.agentMembershipId,
      );

  Future<void> _openVisitOutcome(RouteStop stop) async {
    final outcome = await showModalBottomSheet<VisitOutcome>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VisitOutcomeSheet(stop: stop),
    );
    if (outcome == null || !mounted) return;

    if (outcome == VisitOutcome.collected || outcome == VisitOutcome.partial) {
      // Collected/Partial → hand off into AG-002's exact CollectionEntryScreen
      // (reuse it directly; no second collection-entry form built here).
      final dueRow = CollectionDueRow(
        loanId: stop.loanId,
        customerName: stop.customerName,
        village: stop.village,
        loanNumber: stop.loanNumber,
        installmentDue: stop.todaysDue,
        outstandingBalance: stop.outstandingBalance,
        lineRepaymentIndex: stop.lineRepaymentIndex,
        collectionStatus: 'Pending',
        collectionAgent: widget.agentMembershipId,
      );
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CollectionEntryScreen(row: dueRow)),
      );
      if (!mounted) return;
      await _reload();
      return;
    }

    // All other outcomes → recordNoCollectionVisit on collectionModeProvider,
    // same mechanics AG-002 already uses. AG-003 is just a different entry
    // list into the same write path (every visit generates audit).
    final reason = outcome.reasonEnumValue;
    final ok = await NetworkErrorHandler.run(context, () async {
      final success = await ref
          .read(collectionModeProvider.notifier)
          .recordNoCollectionVisit(loanId: stop.loanId, reason: reason);
      if (!success) throw Exception('Visit outcome could not be saved.');
      return success;
    });
    if (ok != true || !mounted) return;
    ref.read(todaysRouteProvider.notifier).markNoCollectionVisit(loanId: stop.loanId, reasonEnumValue: reason);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todaysRouteProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ManaText("today's route"),
        actions: [
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: state.loading && state.stops.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.error != null && state.stops.isEmpty
                  ? _ErrorState(message: state.error!, onRetry: _reload)
                  : ListView(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      children: [
                        ManaText.raw(DateFormat('d MMM yyyy').format(DateTime.now()),
                            style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                        const SizedBox(height: ManaSpacing.sm),
                        _RouteSummaryCard(state: state),
                        const SizedBox(height: ManaSpacing.md),
                        _RouteProgress(state: state),
                        const SizedBox(height: ManaSpacing.xs),
                        const ManaText.raw(
                          'Village and customer order are set by your Owner — this route cannot be reordered.',
                          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                        ),
                        const SizedBox(height: ManaSpacing.md),
                        if (state.stops.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                            child: Center(
                              child: ManaText.raw('No route assigned for the enabled areas in this session.',
                                  style: TextStyle(color: ManaColors.textSecondary)),
                            ),
                          )
                        else ...[
                          for (final village in state.orderedVillages) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
                              child: ManaText(village, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                            ...state.byVillage[village]!.map((stop) => _RouteStopRow(
                                  stop: stop,
                                  onTap: () => _openVisitOutcome(stop),
                                  onOpenProfile: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AgentCustomerProfileScreen(
                                        businessId: widget.businessId,
                                        agentMembershipId: widget.agentMembershipId,
                                        customerId: stop.customerId,
                                        customerName: stop.customerName,
                                      ),
                                    ),
                                  ),
                                )),
                          ],
                          const SizedBox(height: ManaSpacing.lg),
                          _EndRouteBar(state: state),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ManaText.raw('Could not load today\'s route.\n$message', textAlign: TextAlign.center),
            const SizedBox(height: ManaSpacing.md),
            ElevatedButton(onPressed: onRetry, child: const ManaText('retry')),
          ],
        ),
      ),
    );
  }
}

/// ROUTE SUMMARY: Route Name, Villages, Customers Assigned, Customers
/// Completed, Customers Pending, Estimated Collection, Collected Amount.
class _RouteSummaryCard extends StatelessWidget {
  final TodaysRouteState state;
  const _RouteSummaryCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String, ManaStatus)>[
      ('Villages', '${state.orderedVillages.length}', ManaStatus.neutral),
      ('Assigned', '${state.customersAssigned}', ManaStatus.neutral),
      ('Completed', '${state.customersCompleted}', ManaStatus.good),
      ('Pending', '${state.customersPending}', ManaStatus.warn),
      ('Est. Collection', _currency.format(state.estimatedCollection), ManaStatus.neutral),
      ('Collected', _currency.format(state.collectedAmount), ManaStatus.good),
    ];
    return ManaStatStrip(
      valueFontSize: 16,
      stats: [
        for (final (label, value, status) in stats)
          ManaStat(value: value, label: label, status: status),
      ],
    );
  }
}

/// ROUTE PROGRESS: Progress Bar, Completed %, Remaining %, Collection %,
/// Visit % — all computed client-side from Route Summary counts.
class _RouteProgress extends StatelessWidget {
  final TodaysRouteState state;
  const _RouteProgress({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(ManaRadius.sm),
              child: LinearProgressIndicator(
                value: state.completedPercent,
                minHeight: 8,
                backgroundColor: ManaColors.surfaceSunken,
                valueColor: const AlwaysStoppedAnimation(ManaColors.statusGood),
              ),
            ),
            const SizedBox(height: ManaSpacing.sm),
            Wrap(
              spacing: ManaSpacing.md,
              runSpacing: ManaSpacing.xs,
              children: [
                ManaText.raw('Visit ${(state.visitPercent * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                ManaText.raw('Collection ${(state.collectionPercent * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                ManaText.raw('Remaining ${(state.remainingPercent * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteStopRow extends StatelessWidget {
  final RouteStop stop;
  final VoidCallback onTap;
  final VoidCallback onOpenProfile;
  const _RouteStopRow({required this.stop, required this.onTap, required this.onOpenProfile});

  ({IconData icon, Color color, ManaStatus pillStatus, String label}) get _visual => switch (stop.derivedStatus) {
        CustomerVisitStatus.collected => (
            icon: Icons.check_circle,
            color: ManaColors.statusGood,
            pillStatus: ManaStatus.good,
            label: 'Collected',
          ),
        CustomerVisitStatus.partial => (
            icon: Icons.adjust,
            color: ManaColors.statusWarn,
            pillStatus: ManaStatus.warn,
            label: 'Partial',
          ),
        CustomerVisitStatus.skipped => (
            icon: Icons.remove_circle_outline,
            color: ManaColors.textSecondary,
            pillStatus: ManaStatus.neutral,
            label: 'Skipped',
          ),
        CustomerVisitStatus.houseLocked => (
            icon: Icons.lock_outline,
            color: ManaColors.textSecondary,
            pillStatus: ManaStatus.neutral,
            label: 'House Locked',
          ),
        CustomerVisitStatus.shiftedVillage => (
            icon: Icons.directions_walk_outlined,
            color: ManaColors.textSecondary,
            pillStatus: ManaStatus.neutral,
            label: 'Shifted Village',
          ),
        CustomerVisitStatus.extensionRequested => (
            icon: Icons.event_available_outlined,
            color: ManaColors.statusWarn,
            pillStatus: ManaStatus.warn,
            label: 'Extension Requested',
          ),
        CustomerVisitStatus.closed => (
            icon: Icons.lock_clock_outlined,
            color: ManaColors.textSecondary,
            pillStatus: ManaStatus.neutral,
            label: 'Closed',
          ),
        CustomerVisitStatus.pending => (
            icon: Icons.radio_button_unchecked,
            color: ManaColors.textSecondary,
            pillStatus: ManaStatus.neutral,
            label: 'Pending',
          ),
      };

  @override
  Widget build(BuildContext context) {
    final v = _visual;
    final tappable = stop.derivedStatus == CustomerVisitStatus.pending;
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        leading: Icon(v.icon, color: v.color),
        title: ManaText.raw(stop.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: ManaText.raw(
          '${stop.loanNumber} · LRI ${stop.lineRepaymentIndex}',
          style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ManaText.raw(_currency.format(stop.todaysDue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 2),
            ManaStatusPill(label: v.label, status: v.pillStatus),
          ],
        ),
        onTap: tappable ? onTap : onOpenProfile,
        onLongPress: onOpenProfile,
      ),
    );
  }
}

/// VISIT OUTCOME picker — the full spec vocabulary. Not built with
/// Radio/RadioListTile per convention; a plain tappable list instead.
class _VisitOutcomeSheet extends StatelessWidget {
  final RouteStop stop;
  const _VisitOutcomeSheet({required this.stop});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(stop.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const ManaText('visit outcome', style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
            const SizedBox(height: ManaSpacing.md),
            for (final outcome in VisitOutcome.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  outcome == VisitOutcome.collected || outcome == VisitOutcome.partial
                      ? Icons.payments_outlined
                      : Icons.event_note_outlined,
                  color: outcome.isNoCollectionOutcome ? ManaColors.textSecondary : ManaColors.brand,
                ),
                // "Customer Not Home" — exact canonical label, matching the
                // schema ENUM literally.
                title: ManaText.raw(outcome.displayLabel),
                onTap: () => Navigator.of(context).pop(outcome),
              ),
          ],
        ),
      ),
    );
  }
}

/// END ROUTE: All Customers Visited? YES → Route Complete (back to AG-001,
/// Today Summary refreshed). NO → Continue Visits (stay on AG-003).
class _EndRouteBar extends StatelessWidget {
  final TodaysRouteState state;
  const _EndRouteBar({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.isRouteComplete) {
      return Center(
        child: ManaText.raw(
          '${state.customersPending} customer${state.customersPending == 1 ? '' : 's'} left to visit.',
          style: const TextStyle(color: ManaColors.textSecondary),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.check_circle_outline),
        label: const ManaText('route complete — return to dashboard'),
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    );
  }
}
