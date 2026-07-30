import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../owner_workspace/state/collection_mode_state.dart';
import '../../owner_workspace/screens/ow_006_collection_mode.dart' show CollectionEntryScreen;

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// AG-002 — Collection Mode (Agent Workspace). Per spec's own PURPOSE/API
/// BINDING: this is the Agent-side entry point into the same Collection
/// workflow already fully locked at OW-006 — same `collectionModeProvider`,
/// same `CollectionEntryScreen` (Full/Partial/Excess/No-Collection, mixed
/// payment, validations). This file adds only the Agent-specific dashboard/
/// list framing (Customers Due/Collected/Pending/Skipped, Penalty, Grace,
/// Today's Collection Total) around that shared workflow — it does not
/// redefine or duplicate the collection mechanics.
class AgentCollectionModeScreen extends ConsumerStatefulWidget {
  final String businessId;
  const AgentCollectionModeScreen({super.key, required this.businessId});

  @override
  ConsumerState<AgentCollectionModeScreen> createState() => _AgentCollectionModeScreenState();
}

class _AgentCollectionModeScreenState extends ConsumerState<AgentCollectionModeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(collectionModeProvider.notifier).load(widget.businessId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectionModeProvider);

    return Scaffold(
      appBar: AppBar(title: const ManaText('collection mode')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(collectionModeProvider.notifier).load(widget.businessId),
          child: state.loading && state.dueList.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    ManaText.raw(DateFormat('d MMM yyyy').format(DateTime.now()),
                        style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                    const SizedBox(height: ManaSpacing.sm),
                    _AgentSummaryStrip(state: state),
                    const SizedBox(height: ManaSpacing.xs),
                    const ManaText.raw(
                      'Sorted by: penalty → grace period → today\'s due → village',
                      style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                    ),
                    const SizedBox(height: ManaSpacing.md),
                    if (state.sorted.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw('No customers due right now.',
                              style: TextStyle(color: ManaColors.textSecondary)),
                        ),
                      )
                    else
                      ...state.sorted.map((row) => _CustomerDueRow(
                            row: row,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => CollectionEntryScreen(row: row)),
                            ),
                          )),
                  ],
                ),
        ),
      ),
    );
  }
}

/// AG-002's own dashboard strip: Customers Due, Collected, Pending, Skipped,
/// Penalty, Grace, Today's Collection Total — per spec's COLLECTION
/// DASHBOARD section (distinct labels from OW-006's strip, same underlying
/// CollectionModeState fields).
class _AgentSummaryStrip extends StatelessWidget {
  final CollectionModeState state;
  const _AgentSummaryStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String, ManaStatus)>[
      ('Customers Due', '${state.totalDue}', ManaStatus.neutral),
      ('Collected', '${state.collected}', ManaStatus.good),
      ('Pending', '${state.pending}', ManaStatus.warn),
      ('Skipped', '${state.skipped}', ManaStatus.neutral),
      ('Penalty', '${state.penaltyCount}', ManaStatus.bad),
      ('Grace', '${state.graceCount}', ManaStatus.warn),
      ("Today's Collection Total", _currency.format(state.liveCollectionAmount), ManaStatus.good),
    ];
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stats.length,
        separatorBuilder: (_, __) => const SizedBox(width: ManaSpacing.sm),
        itemBuilder: (context, i) {
          final (label, value, status) = stats[i];
          return Card(
            child: Container(
              width: 128,
              padding: const EdgeInsets.all(ManaSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ManaStatusPill(label: label, status: status),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CustomerDueRow extends StatelessWidget {
  final CollectionDueRow row;
  final VoidCallback onTap;
  const _CustomerDueRow({required this.row, required this.onTap});

  ({IconData icon, Color color}) get _statusIcon => switch (row.collectionStatus) {
        'Collected' => (icon: Icons.check_circle, color: ManaColors.statusGood),
        'Partial' => (icon: Icons.adjust, color: ManaColors.statusWarn),
        'Skipped' => (icon: Icons.remove_circle_outline, color: ManaColors.textSecondary),
        'Closed' => (icon: Icons.lock_outline, color: ManaColors.textSecondary),
        _ => (icon: Icons.radio_button_unchecked, color: ManaColors.textSecondary),
      };

  @override
  Widget build(BuildContext context) {
    final s = _statusIcon;
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        leading: Icon(s.icon, color: s.color),
        title: Row(
          children: [
            Flexible(child: ManaText.raw(row.customerName, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (row.penaltyEligible) ...[
              const SizedBox(width: ManaSpacing.xs),
              const ManaStatusPill(label: 'Penalty', status: ManaStatus.bad),
            ] else if (row.gracePeriod) ...[
              const SizedBox(width: ManaSpacing.xs),
              const ManaStatusPill(label: 'Grace', status: ManaStatus.warn),
            ],
          ],
        ),
        subtitle: ManaText.raw('${row.village} · ${row.loanNumber} · LRI ${row.lineRepaymentIndex}',
            style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
        trailing: ManaText.raw(_currency.format(row.installmentDue),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        onTap: onTap,
      ),
    );
  }
}
