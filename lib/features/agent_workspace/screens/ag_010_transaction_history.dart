import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../state/agent_history_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateTimeFmt = DateFormat('dd-MM-yyyy, hh:mm a');

/// AG-010 — Transaction History (new this batch). 4th footer nav
/// destination, added for parity with the Owner workspace's own footer
/// nav (Home/Customers/Collections/History). Shows this Agent's own
/// recorded collections on this specific business only — see
/// agent_history_state.dart's doc comment for the exact RLS/filter
/// reasoning behind "own" here.
class Ag010TransactionHistoryScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String agentMembershipId;
  const Ag010TransactionHistoryScreen({
    super.key,
    required this.businessId,
    required this.agentMembershipId,
  });

  @override
  ConsumerState<Ag010TransactionHistoryScreen> createState() => _Ag010TransactionHistoryScreenState();
}

class _Ag010TransactionHistoryScreenState extends ConsumerState<Ag010TransactionHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentHistoryProvider.notifier).load(
            businessId: widget.businessId,
            agentMembershipId: widget.agentMembershipId,
          );
    });
  }

  Future<void> _refresh() => ref.read(agentHistoryProvider.notifier).load(
        businessId: widget.businessId,
        agentMembershipId: widget.agentMembershipId,
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: ManaText.raw(ref.t('transaction_history'))),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: state.loading && state.entries.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.error != null && state.entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(ManaSpacing.lg),
                        child: ManaText.raw(
                          state.error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: ManaColors.statusBad, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      itemCount: 2 + (state.entries.isEmpty ? 1 : state.entries.length),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(ManaSpacing.md),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: ManaText.raw(ref.t('total_collected_last_100'),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                                  ),
                                  const SizedBox(width: ManaSpacing.xs),
                                  ManaText.raw(_currency.format(state.totalCollected),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                            ),
                          );
                        }
                        if (i == 1) return const SizedBox(height: ManaSpacing.md);
                        if (state.entries.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                            child: Center(
                              child: ManaText.raw(ref.t('no_transactions_recorded_yet'),
                                  style: TextStyle(color: ManaColors.textSecondary)),
                            ),
                          );
                        }
                        return _HistoryRow(entry: state.entries[i - 2]);
                      },
                    ),
        ),
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  final AgentTransactionEntry entry;
  const _HistoryRow({required this.entry});

  ManaStatus get _statusKind => switch (entry.resultType) {
        'Full' => ManaStatus.good,
        'Partial' => ManaStatus.warn,
        'Excess' => ManaStatus.good,
        'No Collection' => ManaStatus.neutral,
        _ => ManaStatus.neutral,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ManaText.raw(entry.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: ManaSpacing.xs),
                Flexible(child: ManaStatusPill(label: entry.resultType, status: _statusKind)),
              ],
            ),
            const SizedBox(height: 2),
            ManaText.raw(ref.t('loan_number_note').replaceAll('{number}', entry.loanNumber),
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            const SizedBox(height: 2),
            ManaText.raw(_dateTimeFmt.format(entry.entryTimestamp),
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            if (entry.receiptNumber != null) ...[
              const SizedBox(height: 2),
              ManaText.raw(ref.t('receipt_note').replaceAll('{number}', entry.receiptNumber!),
                  style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            ],
            const SizedBox(height: ManaSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: ManaText.raw(_currency.format(entry.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
