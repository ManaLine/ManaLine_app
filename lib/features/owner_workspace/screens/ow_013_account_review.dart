import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/account_review_state.dart';

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
          title: ManaText.raw(ref.t('account_review')),
          bottom: TabBar(tabs: [
            Tab(text: ref.t('account_review')),
            Tab(text: ref.t('daily_allowance')),
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

class _ErrorBanner extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.xl),
      children: [
        Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
        const SizedBox(height: ManaSpacing.md),
        Center(child: ManaText.raw(ref.t('could_not_load_data'))),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(message,
            textAlign: TextAlign.center,
            style: ManaType.noteBad),
        const SizedBox(height: ManaSpacing.sm),
        Center(child: ElevatedButton(onPressed: onRetry, child: ManaText.raw(ref.t('retry')))),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                    child: Center(
                      child: ManaText.raw(ref.t('no_accounts_pending_review'),
                          style: ManaType.secondary),
                    ),
                  )
                else
                  ...state.settlements.map((s) => _SettlementCard(businessId: businessId, settlement: s)),
              ],
            ),
    );
  }
}

class _OwnerBfPanel extends ConsumerWidget {
  final OwnerBfPanelData data;
  const _OwnerBfPanel({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: ManaColors.inkFaint,
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('owner_bf'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: ManaSpacing.sm),
            _bfRow(ref.t('balance_before_today'), data.balanceBeforeToday),
            _bfRow(ref.t('assigned_out_this_session'), data.totalAssignedThisSession),
            _bfRow(ref.t('returning_this_session'), data.totalReturningThisSession),
            const Divider(),
            _bfRow(ref.t('owner_bf_current'), data.ownerBfCurrent, emphasize: true),
            const SizedBox(height: 4),
            ManaText.raw(
              ref.t('provisional_until_approved_note'),
              style: ManaType.note,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bfRow(String label, int amount, {bool emphasize = false}) {
    final style = TextStyle(
      fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
      fontSize: emphasize ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: ManaText.raw(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          const SizedBox(width: ManaSpacing.xs),
          ManaText.raw(manaRupees(amount), style: style),
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
      if (settlement.handOverCash > 0) 'Cash ${manaRupees(settlement.handOverCash)}',
      if (settlement.handOverUpi > 0) 'UPI ${manaRupees(settlement.handOverUpi)}',
      if (settlement.handOverCheque > 0) 'Cheque ${manaRupees(settlement.handOverCheque)}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ManaText.raw(_dateFmt.format(settlement.businessDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ManaType.note),
                ),
                const SizedBox(width: ManaSpacing.xs),
                Flexible(child: ManaStatusPill(label: settlement.status, status: _statusKind)),
              ],
            ),
            const SizedBox(height: 4),
            ManaText.raw(settlement.agentName, style: ManaType.cardTitle),
            const SizedBox(height: ManaSpacing.sm),
            _fieldRow(ref.t('total_collections'), settlement.totalCollections),
            _fieldRow(ref.t('total_loans_issued'), settlement.totalLoansIssued),
            _fieldRow(ref.t('total_interest'), settlement.totalInterest),
            _fieldRow(ref.t('total_processing_fee'), settlement.totalProcessingFee),
            if (settlement.expenses > 0) _fieldRow(ref.t('expenses'), settlement.expenses),
            if (settlement.short > 0) _fieldRow(ref.t('short'), settlement.short, color: ManaColors.statusBad),
            if (settlement.excess > 0) _fieldRow(ref.t('excess'), settlement.excess, color: ManaColors.statusWarn),
            if (settlement.difference > 0) _fieldRow(ref.t('difference'), settlement.difference, color: ManaColors.statusBad),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: ManaText.raw(ref.t('hand_over_balance'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: ManaSpacing.xs),
                ManaText.raw(manaRupees(settlement.handOverTotal),
                    style: ManaType.strong),
              ],
            ),
            if (breakdown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ManaText.raw(breakdown.join(' / '),
                    style: ManaType.note),
              ),
            const SizedBox(height: ManaSpacing.md),
            Wrap(
              spacing: ManaSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: () => _viewDetail(context, ref),
                  child: ManaText.raw(ref.t('view')),
                ),
                if (settlement.status == 'Pending Owner Review') ...[
                  ElevatedButton(
                    onPressed: () => _approve(context, ref),
                    child: ManaText.raw(ref.t('approve')),
                  ),
                  OutlinedButton(
                    onPressed: () => _showReturnDialog(context, ref),
                    style: OutlinedButton.styleFrom(foregroundColor: ManaColors.statusBad),
                    child: ManaText.raw(ref.t('return_label')),
                  ),
                ],
                if (settlement.status == 'Approved')
                  ElevatedButton(
                    onPressed: () => _lock(context, ref),
                    child: ManaText.raw(ref.t('lock_account')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow(String label, int amount, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: ManaText.raw(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: color))),
          const SizedBox(width: ManaSpacing.xs),
          ManaText.raw(manaRupees(amount), style: TextStyle(fontSize: 16, color: color)),
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
            title: ManaText.raw(ref.t('return_account')),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: ref.t('reason_required_field'),
                hintText: ref.t('reason_required_hint'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: ManaText.raw(ref.t('cancel'))),
              ElevatedButton(
                onPressed: controller.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, controller.text.trim()),
                child: ManaText.raw(ref.t('save')),
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

class _SettlementDetailSheet extends ConsumerWidget {
  final AccountSettlementDetail detail;
  const _SettlementDetailSheet({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(detail.summary.agentName, style: ManaType.sheetTitle),
          const SizedBox(height: ManaSpacing.md),
          if (detail.adjustments.isEmpty)
            ManaText.raw(ref.t('no_short_excess_adjustments'), style: ManaType.secondary)
          else
            ...detail.adjustments.map((a) => ListTile(
                  dense: true,
                  title: ManaText.raw('${a.type} — ${manaRupees(a.amount)}'),
                  subtitle: ManaText.raw(ref.t('applied_to_note').replaceAll('{target}', a.appliedTo)),
                )),
          if (detail.agentRemarks != null) ...[
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('agent_remarks')),
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
        ManaText.raw(
          ref.t('daily_allowance_tracking_note'),
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.md),
        if (state.accessDays.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
            child: Center(
              child: ManaText.raw(ref.t('no_access_days_granted'),
                  style: ManaType.secondary),
            ),
          )
        else
          ...state.accessDays.map((a) => Card(
                child: ListTile(
                  title: ManaText.raw(a.agentName),
                  subtitle: ManaText.raw(ref.t('allowance_note').replaceAll('{amount}', manaRupees(a.allowanceAmount))),
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
