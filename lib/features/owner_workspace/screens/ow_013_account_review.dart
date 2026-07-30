import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/account_review_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('dd-MM-yyyy');

/// OW-013 — Account Review. CARD-based DISPLAY per 2026-07-19 mobile
/// scenario-testing rewrite (supersedes the old row/table layout).
class AccountReviewScreen extends ConsumerStatefulWidget {
  final String businessId;
  const AccountReviewScreen({super.key, required this.businessId});

  @override
  ConsumerState<AccountReviewScreen> createState() => _AccountReviewScreenState();
}

class _AccountReviewScreenState extends ConsumerState<AccountReviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(accountReviewProvider.notifier).load(widget.businessId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountReviewProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/ow-001', extra: widget.businessId)),
          title: const ManaText('account review'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Account Review'),
            Tab(text: 'Daily Allowance'),
          ]),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _AccountReviewTab(businessId: widget.businessId, state: state),
              _DailyAllowanceTab(businessId: widget.businessId, state: state),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.xl),
      children: [
        const Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
        const SizedBox(height: ManaSpacing.md),
        const Center(child: ManaText('could not load data')),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: ManaColors.statusBad)),
        const SizedBox(height: ManaSpacing.sm),
        Center(child: ElevatedButton(onPressed: onRetry, child: const ManaText('retry'))),
      ],
    );
  }
}

class _AccountReviewTab extends ConsumerWidget {
  final String businessId;
  final AccountReviewState state;
  const _AccountReviewTab({required this.businessId, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(accountReviewProvider.notifier).load(businessId),
      child: state.loading && state.settlements.isEmpty
          ? const Center(child: CircularProgressIndicator())
          // A failed load previously left this looking exactly like a
          // business with nothing to review — state.error was set and never
          // rendered anywhere on the screen. Same fix OW-012 already has.
          : state.error != null && state.settlements.isEmpty
              ? _ErrorBanner(
                  message: state.error!,
                  onRetry: () => ref.read(accountReviewProvider.notifier).load(businessId),
                )
          : ListView(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              children: [
                if (state.bfPanel != null) _OwnerBfPanel(data: state.bfPanel!),
                const SizedBox(height: ManaSpacing.md),
                if (state.settlements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                    child: Center(
                      child: ManaText.raw('No accounts pending review.',
                          style: TextStyle(color: ManaColors.textSecondary)),
                    ),
                  )
                else
                  ...state.settlements.map((s) => _SettlementCard(businessId: businessId, settlement: s)),
              ],
            ),
    );
  }
}

class _OwnerBfPanel extends StatelessWidget {
  final OwnerBfPanelData data;
  const _OwnerBfPanel({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: ManaColors.inkFaint,
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText('owner bf', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: ManaSpacing.sm),
            _bfRow('Balance before today', data.balanceBeforeToday),
            _bfRow('Assigned out this session', data.totalAssignedThisSession),
            _bfRow('Returning this session', data.totalReturningThisSession),
            const Divider(),
            _bfRow('Owner BF, current', data.ownerBfCurrent, emphasize: true),
            const SizedBox(height: 4),
            const ManaText.raw(
              'Provisional until each pending account is Approved.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bfRow(String label, double amount, {bool emphasize = false}) {
    final style = TextStyle(
      fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
      fontSize: emphasize ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ManaText(label, style: style),
          ManaText.raw(_currency.format(amount), style: style),
        ],
      ),
    );
  }
}

class _SettlementCard extends ConsumerWidget {
  final String businessId;
  final AccountSettlementSummary settlement;
  const _SettlementCard({required this.businessId, required this.settlement});

  ManaStatus get _statusKind => switch (settlement.status) {
        'Approved' => ManaStatus.good,
        'Returned' => ManaStatus.bad,
        _ => ManaStatus.warn,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = <String>[
      if (settlement.handOverCash > 0) 'Cash ${_currency.format(settlement.handOverCash)}',
      if (settlement.handOverUpi > 0) 'UPI ${_currency.format(settlement.handOverUpi)}',
      if (settlement.handOverCheque > 0) 'Cheque ${_currency.format(settlement.handOverCheque)}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ManaText.raw(_dateFmt.format(settlement.businessDate),
                    style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
                ManaStatusPill(label: settlement.status, status: _statusKind),
              ],
            ),
            const SizedBox(height: 4),
            ManaText.raw(settlement.agentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            _fieldRow('Total Collections', settlement.totalCollections),
            _fieldRow('Total Loans Issued', settlement.totalLoansIssued),
            _fieldRow('Total Interest', settlement.totalInterest),
            _fieldRow('Total Processing Fee', settlement.totalProcessingFee),
            if (settlement.expenses > 0) _fieldRow('Expenses', settlement.expenses),
            if (settlement.short > 0) _fieldRow('Short', settlement.short, color: ManaColors.statusBad),
            if (settlement.excess > 0) _fieldRow('Excess', settlement.excess, color: ManaColors.statusWarn),
            if (settlement.difference > 0) _fieldRow('Difference', settlement.difference, color: ManaColors.statusBad),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const ManaText('hand over balance'),
                ManaText.raw(_currency.format(settlement.handOverTotal),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (breakdown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ManaText.raw(breakdown.join(' / '),
                    style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
              ),
            const SizedBox(height: ManaSpacing.md),
            Wrap(
              spacing: ManaSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: () => _viewDetail(context, ref),
                  child: const ManaText('view'),
                ),
                if (settlement.status == 'Pending Owner Review') ...[
                  ElevatedButton(
                    onPressed: () => _approve(context, ref),
                    child: const ManaText('approve'),
                  ),
                  OutlinedButton(
                    onPressed: () => _showReturnDialog(context, ref),
                    style: OutlinedButton.styleFrom(foregroundColor: ManaColors.statusBad),
                    child: const ManaText('return'),
                  ),
                ],
                if (settlement.status == 'Approved')
                  ElevatedButton(
                    onPressed: () => _lock(context, ref),
                    child: const ManaText('lock account'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow(String label, double amount, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ManaText(label, style: TextStyle(fontSize: 13, color: color)),
          ManaText.raw(_currency.format(amount), style: TextStyle(fontSize: 16, color: color)),
        ],
      ),
    );
  }

  Future<void> _viewDetail(BuildContext context, WidgetRef ref) async {
    final detail = await ref.read(accountReviewProvider.notifier).viewDetail(settlement.settlementId);
    if (detail == null || !context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SettlementDetailSheet(detail: detail),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    await NetworkErrorHandler.run(context, () async {
      return ref.read(accountReviewProvider.notifier).approve(
            businessId: businessId,
            settlementId: settlement.settlementId,
          );
    });
  }

  Future<void> _lock(BuildContext context, WidgetRef ref) async {
    await NetworkErrorHandler.run(context, () async {
      return ref.read(accountReviewProvider.notifier).lockAccountPeriod(
            businessId: businessId,
            accountPeriodId: settlement.accountPeriodId,
          );
    });
  }

  // Return requires a mandatory reason — same unconditional-reason
  // pattern as OW-011's Reopen Closed Day. Save disabled until non-empty.
  Future<void> _showReturnDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: const ManaText('return account'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                hintText: 'Explain what the Agent needs to correct',
              ),
              onChanged: (_) => setState(() {}),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const ManaText('cancel')),
              ElevatedButton(
                onPressed: controller.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, controller.text.trim()),
                child: const ManaText('save'),
              ),
            ],
          );
        },
      ),
    );
    if (reason == null || reason.isEmpty || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(accountReviewProvider.notifier).returnAccount(
            businessId: businessId,
            settlementId: settlement.settlementId,
            reason: reason,
          );
    });
  }
}

class _SettlementDetailSheet extends StatelessWidget {
  final AccountSettlementDetail detail;
  const _SettlementDetailSheet({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(detail.summary.agentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: ManaSpacing.md),
          if (detail.adjustments.isEmpty)
            const ManaText.raw('No Short/Excess adjustments.', style: TextStyle(color: ManaColors.textSecondary))
          else
            ...detail.adjustments.map((a) => ListTile(
                  dense: true,
                  title: ManaText.raw('${a.type} — ${_currency.format(a.amount)}'),
                  subtitle: ManaText.raw('Applied to: ${a.appliedTo}'),
                )),
          if (detail.agentRemarks != null) ...[
            const SizedBox(height: ManaSpacing.md),
            const ManaText('agent remarks'),
            ManaText.raw(detail.agentRemarks!),
          ],
        ],
      ),
    );
  }
}

class _DailyAllowanceTab extends ConsumerWidget {
  final String businessId;
  final AccountReviewState state;
  const _DailyAllowanceTab({required this.businessId, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const ManaText.raw(
          'Tracking/visibility only — no linkage to Payable Salary or any figure elsewhere on this screen.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        if (state.accessDays.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
            child: Center(
              child: ManaText.raw('No access days granted this session.',
                  style: TextStyle(color: ManaColors.textSecondary)),
            ),
          )
        else
          ...state.accessDays.map((a) => Card(
                child: ListTile(
                  title: ManaText.raw(a.agentName),
                  subtitle: ManaText.raw('Allowance: ${_currency.format(a.allowanceAmount)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        ref.read(accountReviewProvider.notifier).removeAccessDay(
                              businessId: businessId,
                              accessDayId: a.accessDayId,
                            ),
                  ),
                ),
              )),
      ],
    );
  }
}
