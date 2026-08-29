import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_money_row.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/widgets/record_expense_sheet.dart';
import '../state/agent_settlement_state.dart';

final _dateFmt = DateFormat('dd-MM-yyyy');

/// AG-006 — Owner Settlement.
///
/// Entry: AG-001 Agent Dashboard → Settlement. Permission-gated by
/// `agent_permissions.can_perform_day_settlement` at the caller (AG-001
/// Quick Actions) — assumed already enforced before this screen is
/// reached, per AG-005's own pattern for its gates.
///
/// NOTE: Approve/Return itself belongs to the Owner Workspace, not this
/// screen (mirrors OW-013's pattern, but the action buttons live there).
/// This screen only renders whatever status/return_reason comes back.
class OwnerSettlementScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String agentId;
  final DateTime periodStart;
  final DateTime periodEnd;

  const OwnerSettlementScreen({
    super.key,
    required this.businessId,
    required this.agentId,
    required this.periodStart,
    required this.periodEnd,
  });

  @override
  ConsumerState<OwnerSettlementScreen> createState() => _OwnerSettlementScreenState();
}

class _OwnerSettlementScreenState extends ConsumerState<OwnerSettlementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentSettlementProvider.notifier).enter(
            businessId: widget.businessId,
            agentId: widget.agentId,
            periodStart: widget.periodStart,
            periodEnd: widget.periodEnd,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentSettlementProvider);

    return Scaffold(
      appBar: ManaAppBar(
        homeRoute: '/ag-001',
        title: ref.t('settlement'),
        actions: [
          // Only before submission. Once the settlement is Pending or
          // Approved, a new expense would move the float the submitted
          // figures were computed from.
          if (state.stage == SettlementScreenStage.draftEntry)
            TextButton.icon(
              onPressed: _recordExpense,
              icon: const Icon(Icons.receipt_long, size: 18),
              label: ManaText.raw(ref.t('expense')),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state.stage) {
          SettlementScreenStage.loading => const Center(child: CircularProgressIndicator()),
          SettlementScreenStage.pendingReview => _StatusOnlyView(
              state: state,
              icon: Icons.hourglass_top,
              color: ManaColors.statusWarn,
              title: 'Pending Owner Review',
              body: 'Your settlement has been submitted and is awaiting Owner action.',
            ),
          SettlementScreenStage.approved => _StatusOnlyView(
              state: state,
              icon: Icons.check_circle,
              color: ManaColors.statusGood,
              title: 'Approved',
              body: 'This settlement has been posted and locked.',
            ),
          SettlementScreenStage.returned => _ReturnedView(state: state),
          SettlementScreenStage.draftEntry => _DraftEntryView(
              businessId: widget.businessId,
              agentId: widget.agentId,
              periodStart: widget.periodStart,
              periodEnd: widget.periodEnd,
              state: state,
            ),
        },
      ),
    );
  }

  /// Agent-paid expense. Comes out of this agent's own float, which is
  /// exactly why it belongs here: it reduces what they hand over. The
  /// preview is reloaded afterwards rather than adjusted locally, so the
  /// Expenses line and the expected closing stay the server's numbers.
  ///
  /// No client-side permission gate: can_record_expenses is enforced inside
  /// record_expense, and a button hidden by a stale local copy of a
  /// permission is worse than one that returns the server's real refusal.
  Future<void> _recordExpense() async {
    final api = ref.read(agentSettlementApiServiceProvider);

    final recorded = await RecordExpenseSheet.show(
      context,
      payerNote: 'Paid from your own cash in hand. This reduces what you '
          'hand over at settlement.',
      onSubmit: ({required category, required amount, remarks}) async {
        await api.recordExpense(
          agentId: widget.agentId,
          businessId: widget.businessId,
          category: category,
          amount: amount,
          businessDate: manaBusinessDate(),
          remarks: remarks,
        );
      },
    );

    if (!recorded || !mounted) return;
    await ref.read(agentSettlementProvider.notifier).enter(
          businessId: widget.businessId,
          agentId: widget.agentId,
          periodStart: widget.periodStart,
          periodEnd: widget.periodEnd,
        );
  }
}

class _StatusOnlyView extends StatelessWidget {
  final AgentSettlementState state;
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _StatusOnlyView({
    required this.state,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final s = state.existingSettlement;
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const SizedBox(height: ManaSpacing.xxl),
        Icon(icon, size: 56, color: color),
        const SizedBox(height: ManaSpacing.md),
        Center(child: ManaText(title, style: Theme.of(context).textTheme.headlineMedium)),
        const SizedBox(height: ManaSpacing.sm),
        Center(
          child: ManaText.raw(body,
              textAlign: TextAlign.center, style: ManaType.secondary),
        ),
        if (s != null) ...[
          const SizedBox(height: ManaSpacing.xl),
          _SummaryCard(preview: s.summary, physicalCashDeclared: s.physicalCashDeclared, difference: s.difference),
        ],
      ],
    );
  }
}

class _ReturnedView extends ConsumerWidget {
  final AgentSettlementState state;
  const _ReturnedView({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state.existingSettlement;
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Card(
          color: ManaColors.statusBadFaint,
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.undo, color: ManaColors.statusBad),
                    const SizedBox(width: ManaSpacing.sm),
                    Expanded(
                      child: ManaText.raw(ref.t('returned_correction_required'),
                          style: ManaType.strong),
                    ),
                  ],
                ),
                if (s?.returnReason != null) ...[
                  const SizedBox(height: ManaSpacing.sm),
                  ManaText.raw(s!.returnReason!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton(
            onPressed: () => ref.read(agentSettlementProvider.notifier).beginResubmit(),
            child: ManaText.raw(ref.t('correct_and_resubmit')),
          ),
        ),
      ],
    );
  }
}

/// How the figure being handed over was arrived at, and then the figure.
///
/// Money in is green, money out is red, and the lines add up to the total
/// exactly -- which is the whole reason to show them. A breakdown that does
/// not reach its own total teaches somebody to stop reading it. When this was
/// first written the lines came to Rs 5,08,860 against a float of Rs
/// 5,08,930: BF the Owner had granted mid-round was missing, and seventy
/// rupees is precisely the size of gap that gets shrugged at.
///
/// Interest and processing fee sit BELOW the total, apart from the sum.
/// They are earned rather than moved: both are withheld at disbursement, so
/// they never pass through the Agent's hands as cash, and the interest a
/// customer repays is already inside the collection figure. Adding them
/// would count them twice and the total would stop matching the tin.
class _HandOverBreakdown extends ConsumerWidget {
  final SettlementPreview preview;
  const _HandOverBreakdown({required this.preview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = preview.expectedClosingBalance ?? 0;
    final earnings = preview.interestEarned + preview.processingFees;

    return Card(
      color: ManaColors.brandFaint,
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // In.
            _line(ref, 'opening_bf', preview.openingBalance, positive: true),
            _line(ref, 'bf_received', preview.bfReceived, positive: true),
            _line(ref, 'cash', preview.cashCollected, positive: true),
            _line(ref, 'upi', preview.upiCollected, positive: true),
            _line(ref, 'bank', preview.bankCollected, positive: true),
            _line(ref, 'cheque', preview.chequeCollected, positive: true),
            _line(ref, 'transfers_in', preview.transfersIn, positive: true),
            // Out.
            _line(ref, 'loans_issued', preview.loanDistribution, positive: false),
            _line(ref, 'expenses', preview.expenses, positive: false),
            _line(ref, 'transfers_out', preview.transfersOut, positive: false),

            const Divider(height: ManaSpacing.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ManaText.raw(ref.t('total_amount'), style: ManaType.strong),
                ),
                const SizedBox(width: ManaSpacing.sm),
                Flexible(child: ManaAmount(total, size: ManaAmountSize.hero)),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(ref.t('total_amount_note'), style: ManaType.note),

            if (earnings > 0) ...[
              const SizedBox(height: ManaSpacing.md),
              ManaText.raw(
                ref
                    .t('earned_not_held_note')
                    .replaceAll('{interest}', manaRupees(preview.interestEarned))
                    .replaceAll('{fees}', manaRupees(preview.processingFees)),
                style: ManaType.note,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A zero line is dropped: ten rows of nothing is not a breakdown, it is a
  /// form. Label and figure both flexible, and the figures right-aligned so
  /// they read as a column.
  Widget _line(WidgetRef ref, String key, int amount, {required bool positive}) {
    if (amount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: ManaText.raw(ref.t(key), maxLines: 2, style: ManaType.note)),
          const SizedBox(width: ManaSpacing.sm),
          Flexible(
            child: ManaText.raw(
              '${positive ? '+' : '−'}${manaRupees(amount)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: positive ? ManaColors.statusGood : ManaColors.statusBad,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  final SettlementPreview preview;
  final int physicalCashDeclared;

  /// Null until the server has computed it. Before submission the card
  /// shows the component figures only — see SettlementPreview.
  final int? difference;
  const _SummaryCard({required this.preview, required this.physicalCashDeclared, this.difference});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('settlement_summary'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: ManaSpacing.sm),
            ManaMoneyRow(label: ref.t('opening_balance_bf'), amount: preview.openingBalance),
            ManaMoneyRow(label: ref.t('cash_collected'), amount: preview.cashCollected),
            ManaMoneyRow(label: ref.t('upi_collected'), amount: preview.upiCollected),
            ManaMoneyRow(label: ref.t('bank_collection'), amount: preview.bankCollected),
            ManaMoneyRow(label: ref.t('cheque_collection'), amount: preview.chequeCollected),
            ManaMoneyRow(label: ref.t('loan_distribution'), amount: preview.loanDistribution),
            ManaMoneyRow(label: ref.t('expenses'), amount: preview.expenses),
            const Divider(),
            // Expected Closing and Difference exist only once the server
            // has computed them. Rendering a locally-derived stand-in here
            // is what this change removed.
            if (preview.expectedClosingBalance != null)
              ManaMoneyRow(label: ref.t('expected_closing_balance'), amount: preview.expectedClosingBalance!,
                  emphasize: true),
            ManaMoneyRow(label: ref.t('physical_cash_declared'), amount: physicalCashDeclared, emphasize: true),
            if (difference != null) ...[
              const Divider(),
              ManaMoneyRow(label: ref.t('difference'), amount: difference!,
                  emphasize: true,
                  color: difference == 0
                      ? ManaColors.statusGood
                      : ManaColors.statusBad),
            ],
          ],
        ),
      ),
    );
  }

}


class _DraftEntryView extends ConsumerStatefulWidget {
  final String businessId;
  final String agentId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final AgentSettlementState state;
  const _DraftEntryView({
    required this.businessId,
    required this.agentId,
    required this.periodStart,
    required this.periodEnd,
    required this.state,
  });

  @override
  ConsumerState<_DraftEntryView> createState() => _DraftEntryViewState();
}

class _DraftEntryViewState extends ConsumerState<_DraftEntryView> {
  late final TextEditingController _cashController;
  late final TextEditingController _chequeCountController;
  late final TextEditingController _remarksController;

  @override
  void initState() {
    super.initState();
    _cashController = TextEditingController(
        text: widget.state.physicalCashDeclared > 0 ? '${widget.state.physicalCashDeclared}' : '');
    _chequeCountController =
        TextEditingController(text: widget.state.chequeCountTally > 0 ? '${widget.state.chequeCountTally}' : '');
    _remarksController = TextEditingController(text: widget.state.remarks);
  }

  @override
  void dispose() {
    _cashController.dispose();
    _chequeCountController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.preview == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: ManaText.raw(ref.t('unable_to_load_settlement'), style: ManaType.secondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ManaText.raw('${_dateFmt.format(widget.periodStart)} – ${_dateFmt.format(widget.periodEnd)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ManaType.note),
            ),
            const SizedBox(width: ManaSpacing.xs),
            // cycle_type is Business-level/Owner-set (OW-012 Account Cycle
            // config) — read-only display here, never an Agent choice per
            // submission.
            Flexible(
              child: ManaStatusPill(
                  label: ref.t('cycle_account_note').replaceAll('{cycle}', state.cycleType),
                  status: ManaStatus.neutral),
            ),
          ],
        ),
        const SizedBox(height: ManaSpacing.md),
        // One figure, and it is the only one that matters here: everything
        // this Agent is holding, in whatever form it arrived.
        //
        // What was here before: a breakdown card, a box asking the Agent to
        // count their physical cash, a cheque tally, a remarks field, and a
        // note explaining what would happen if the counted figure disagreed
        // with the expected one. Five inputs and a reconciliation, for a
        // number the app already knows -- and the Submit button stayed
        // disabled until the arithmetic agreed, which is why "Submit
        // settlement" so often did nothing at all.
        _HandOverBreakdown(preview: state.preview!),
        const SizedBox(height: ManaSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: state.submitting ? null : () => _submit(context),
            child: state.submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : ManaText.raw(ref.t('submit_settlement')),
          ),
        ),
      ],
    );
  }

  Future<void> _submit(BuildContext context) async {
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(agentSettlementProvider.notifier).submit(
            agentId: widget.agentId,
          );
    });
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(ref.t('settlement_submitted_note'))),
    );
  }
}

/// Replaces the old difference banner, which announced "settlement ready —
/// difference is zero" off a figure the phone derived with a different
/// formula from the server's. Telling an agent their cash balances is a
/// claim only the server can make, and it makes it at submit.
