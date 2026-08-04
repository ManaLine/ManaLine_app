import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/widgets/record_expense_sheet.dart';
import '../state/agent_settlement_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
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
      appBar: AppBar(
        title: const ManaText('settlement'),
        actions: [
          // Only before submission. Once the settlement is Pending or
          // Approved, a new expense would move the float the submitted
          // figures were computed from.
          if (state.stage == SettlementScreenStage.draftEntry)
            TextButton.icon(
              onPressed: _recordExpense,
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const ManaText('expense'),
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
              textAlign: TextAlign.center, style: const TextStyle(color: ManaColors.textSecondary)),
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
                const Row(
                  children: [
                    Icon(Icons.undo, color: ManaColors.statusBad),
                    SizedBox(width: ManaSpacing.sm),
                    ManaText('returned — correction required', style: TextStyle(fontWeight: FontWeight.bold)),
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
            child: const ManaText('correct and resubmit'),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final SettlementPreview preview;
  final int physicalCashDeclared;

  /// Null until the server has computed it. Before submission the card
  /// shows the component figures only — see SettlementPreview.
  final int? difference;
  const _SummaryCard({required this.preview, required this.physicalCashDeclared, this.difference});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText('settlement summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: ManaSpacing.sm),
            _row('Opening Balance (BF)', preview.openingBalance),
            _row('Cash Collected', preview.cashCollected),
            _row('UPI Collected', preview.upiCollected),
            _row('Bank Collection', preview.bankCollected),
            _row('Cheque Collection', preview.chequeCollected),
            _row('Loan Distribution', preview.loanDistribution),
            _row('Expenses', preview.expenses),
            const Divider(),
            // Expected Closing and Difference exist only once the server
            // has computed them. Rendering a locally-derived stand-in here
            // is what this change removed.
            if (preview.expectedClosingBalance != null)
              _row('Expected Closing Balance', preview.expectedClosingBalance!,
                  emphasize: true),
            _row('Physical Cash Declared', physicalCashDeclared, emphasize: true),
            if (difference != null) ...[
              const Divider(),
              _row('Difference', difference!,
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

  Widget _row(String label, int amount, {bool emphasize = false, Color? color}) {
    final style = TextStyle(
      fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
      fontSize: emphasize ? 15 : 13,
      color: color,
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(ManaSpacing.lg),
          child: ManaText.raw('Unable to load settlement figures.', style: TextStyle(color: ManaColors.textSecondary)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ManaText.raw('${_dateFmt.format(widget.periodStart)} – ${_dateFmt.format(widget.periodEnd)}',
                style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
            // cycle_type is Business-level/Owner-set (OW-012 Account Cycle
            // config) — read-only display here, never an Agent choice per
            // submission.
            ManaStatusPill(label: '${state.cycleType} Account', status: ManaStatus.neutral),
          ],
        ),
        const SizedBox(height: ManaSpacing.md),
        _SummaryCard(
          preview: state.preview!,
          physicalCashDeclared: state.physicalCashDeclared,
          difference: state.difference,
        ),
        const SizedBox(height: ManaSpacing.lg),
        ManaText('settlement details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _cashController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Physical Cash (₹)'),
          onChanged: (v) => ref.read(agentSettlementProvider.notifier).setPhysicalCash(int.tryParse(v) ?? 0),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _chequeCountController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Cheque Count (tally, not persisted)',
            helperText: 'Sits alongside Cheque Collection ${_currency.format(state.preview!.chequeCollected)} for your own reconciliation.',
          ),
          onChanged: (v) => ref.read(agentSettlementProvider.notifier).setChequeCountTally(int.tryParse(v) ?? 0),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _remarksController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Supporting Remarks',
            hintText: 'Optional — note anything the Owner should know',
          ),
          onChanged: (v) => ref.read(agentSettlementProvider.notifier).setRemarks(v),
        ),
        const SizedBox(height: ManaSpacing.md),
        const _DifferencePendingNote(),
        const SizedBox(height: ManaSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: state.canSubmit && !state.submitting ? () => _submit(context) : null,
            child: state.submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const ManaText('submit settlement'),
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
      const SnackBar(content: Text('Settlement submitted for Owner review.')),
    );
  }
}

/// Replaces the old difference banner, which announced "settlement ready —
/// difference is zero" off a figure the phone derived with a different
/// formula from the server's. Telling an agent their cash balances is a
/// claim only the server can make, and it makes it at submit.
class _DifferencePendingNote extends StatelessWidget {
  const _DifferencePendingNote();

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: ManaColors.statusWarnFaint,
      child: Padding(
        padding: EdgeInsets.all(ManaSpacing.md),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: ManaColors.statusWarn),
            SizedBox(width: ManaSpacing.sm),
            Expanded(
              child: ManaText(
                  'count your cash and declare it. the difference is worked out when you submit.'),
            ),
          ],
        ),
      ),
    );
  }
}
