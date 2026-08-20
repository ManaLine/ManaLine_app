import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/widgets/record_expense_sheet.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/day_closure_state.dart';
import '../state/owner_workspace_state.dart' show ownerApiServiceProvider;


/// OW-011 — Day Closure. Official closing of one business day. Owner only.
///
/// Entry: OW-001 Owner Home Dashboard → "Day Closure". Reopen entry: OW-010
/// Report Hub (past Closed day row) or OW-001, landing directly in S6.
class DayClosureScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String businessDate; // YYYY-MM-DD, defaults to "today" upstream
  /// If set, screen opens directly into the Reopen flow for this already-
  /// Closed date (per NAVIGATION: reached from OW-010's Daily Record Book
  /// row, or OW-001, and returns into this screen's S6 state).
  final bool openForReopen;

  const DayClosureScreen({
    super.key,
    required this.businessId,
    required this.businessDate,
    this.openForReopen = false,
  });

  @override
  ConsumerState<DayClosureScreen> createState() => _DayClosureScreenState();
}

class _DayClosureScreenState extends ConsumerState<DayClosureScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openForReopen) {
        ref.read(dayClosureProvider.notifier).loadForReopen(
            businessId: widget.businessId, businessDate: widget.businessDate);
      } else {
        ref.read(dayClosureProvider.notifier).runPrecheck(
            businessId: widget.businessId, businessDate: widget.businessDate);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dayClosureProvider);

    // An expense recorded after the day is Closed would move cash the
    // closing figures were already computed from, so the action is only
    // offered while the day is still open.
    final dayStillOpen = state.phase == DayClosurePhase.cashVerification ||
        state.phase == DayClosurePhase.differenceFound ||
        state.phase == DayClosurePhase.finalReview ||
        state.phase == DayClosurePhase.reopened;

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('day_closure')),
        actions: [
          if (dayStillOpen)
            TextButton.icon(
              onPressed: _recordExpense,
              icon: const Icon(Icons.receipt_long, size: 18),
              label: ManaText.raw(ref.t('expense')),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(context, state)),
    );
  }

  /// Owner-paid expense. Deducts from owner_bf_balance server-side, so the
  /// day's figures change underneath us — the precheck is re-run afterwards
  /// rather than patching the numbers on screen.
  Future<void> _recordExpense() async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) return;
    final api = ref.read(ownerApiServiceProvider);

    final recorded = await RecordExpenseSheet.show(
      context,
      payerNote: 'Paid from your own balance (Owner BF).',
      onSubmit: ({required category, required amount, remarks}) async {
        final membershipId = await api.ownerMembershipId(
            businessId: widget.businessId, personId: personId);
        await api.recordExpense(
          businessId: widget.businessId,
          category: category,
          amount: amount,
          membershipId: membershipId,
          businessDate: widget.businessDate,
          remarks: remarks,
        );
      },
    );

    if (!recorded || !mounted) return;
    await ref.read(dayClosureProvider.notifier).runPrecheck(
        businessId: widget.businessId, businessDate: widget.businessDate);
  }

  Widget _buildBody(BuildContext context, DayClosureState state) {
    switch (state.phase) {
      case DayClosurePhase.loadingPrecheck:
        return const Center(child: CircularProgressIndicator());
      case DayClosurePhase.blocked:
        return _PreCheckBlocked(state: state);
      case DayClosurePhase.cashVerification:
        return _CashVerification(businessId: widget.businessId);
      case DayClosurePhase.differenceFound:
        return _DifferenceAnalyzer(businessId: widget.businessId);
      case DayClosurePhase.finalReview:
        return _FinalReview(businessId: widget.businessId);
      case DayClosurePhase.closed:
        return _ClosedReceipt(businessId: widget.businessId);
      case DayClosurePhase.reopened:
        return _ReopenedAwaitingCloseAgain(businessId: widget.businessId);
    }
  }
}

// ============================================================================
// S1 — Pre-Check Blocked
// ============================================================================

class _PreCheckBlocked extends ConsumerWidget {
  final DayClosureState state;
  const _PreCheckBlocked({required this.state});

  /// Maps a blocking-issue type to the screen it should route the Owner
  /// back to (spec: "a Pending Collection routes back to OW-006"). Route
  /// names left as strings here — master chat wires these through the app
  /// router per the integration note at the end of this build.
  String? _routeFor(String type) {
    switch (type) {
      case 'Pending Collections':
        return '/ow-006'; // Collection Mode
      case 'Pending Loan Processing':
        return '/ow-005'; // New Loan Workflow
      case 'Pending Cash Settlement':
        return '/ow-014'; // Global Workflow — Account Settlement review (OW-014 per spec)
      case 'Pending Approvals':
        return '/ow-014'; // Global Workflow — approvals queue
      case 'Pending Drafts':
        return '/ow-006'; // Drafts surface inside Collection Mode / AG-005 pattern
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Icon(Icons.block, color: ManaColors.statusBad, size: 40),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(ref.t('day_closure_cannot_start'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('items_must_be_resolved_note'),
          style: ManaType.secondary,
        ),
        const SizedBox(height: ManaSpacing.lg),
        // A ListTile's trailing slot has a hard width assertion — a
        // translated "Resolve" button plus a translated subtitle at large
        // scale exceeded it outright (not just a visual overflow, a thrown
        // layout error). Built from a plain Row instead, same reasoning
        // OW-009's entry tiles already applied to this exact shape.
        ...state.blockingIssues.map((issue) => Card(
              child: Padding(
                padding: const EdgeInsets.all(ManaSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: ManaColors.statusBad),
                    const SizedBox(width: ManaSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ManaText.raw(issue.type),
                          ManaText.raw(
                              ref.t('items_outstanding_note').replaceAll('{count}', '${issue.count}'),
                              style: ManaType.note),
                        ],
                      ),
                    ),
                    if (_routeFor(issue.type) != null) ...[
                      const SizedBox(width: ManaSpacing.sm),
                      Flexible(
                        child: FilledButton(
                          onPressed: () => context.push(_routeFor(issue.type)!),
                          child: ManaText.raw(ref.t('resolve')),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )),
        if (state.warnings.isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw(ref.t('warnings_may_proceed'),
              style: ManaType.strong),
          const SizedBox(height: ManaSpacing.xs),
          ...state.warnings.map((w) => Card(
                color: ManaColors.statusWarnFaint,
                child: ListTile(
                  leading: Icon(Icons.warning_amber,
                      color: ManaColors.statusWarn),
                  title: ManaText.raw(w.type),
                  subtitle: ManaText.raw(
                      ref.t('items_count_note').replaceAll('{count}', '${w.count}')),
                ),
              )),
        ],
      ],
    );
  }
}

// ============================================================================
// S2 — Cash Verification
// ============================================================================

class _CashVerification extends ConsumerStatefulWidget {
  final String businessId;
  const _CashVerification({required this.businessId});

  @override
  ConsumerState<_CashVerification> createState() => _CashVerificationState();
}

class _CashVerificationState extends ConsumerState<_CashVerification> {
  final _cash = TextEditingController(text: '0');
  final _upi = TextEditingController(text: '0');
  final _bank = TextEditingController(text: '0');
  final _cheque = TextEditingController(text: '0');

  int _parse(String s) => int.tryParse(s.trim()) ?? 0;

  void _onChanged() {
    ref.read(dayClosureProvider.notifier).setActualFigures(
          physicalCash: _parse(_cash.text),
          upiBalance: _parse(_upi.text),
          bankBalance: _parse(_bank.text),
          chequeBalance: _parse(_cheque.text),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dayClosureProvider);
    final expected = state.expected;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('cash_verification'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('enter_physical_count_note'),
          style: ManaType.secondary,
        ),
        const SizedBox(height: ManaSpacing.lg),
        _AmountField(
            label: ref.t('physical_cash'), controller: _cash, onChanged: _onChanged),
        _AmountField(
            label: ref.t('upi_balance'), controller: _upi, onChanged: _onChanged),
        _AmountField(
            label: ref.t('bank_balance'), controller: _bank, onChanged: _onChanged),
        _AmountField(
            label: ref.t('cheque_balance'),
            controller: _cheque,
            onChanged: _onChanged),
        const SizedBox(height: ManaSpacing.lg),
        if (expected != null) ...[
          ManaText.raw(ref.t('system_expected_computed'),
              style: ManaType.strong),
          const SizedBox(height: ManaSpacing.sm),
          _ExpectedRow(label: ref.t('expected_cash'), value: expected.expectedCash),
          _ExpectedRow(label: ref.t('expected_upi'), value: expected.expectedUpi),
          _ExpectedRow(label: ref.t('expected_bank'), value: expected.expectedBank),
          _ExpectedRow(
              label: ref.t('expected_cheque'), value: expected.expectedCheque),
        ],
        const SizedBox(height: ManaSpacing.xxl),
        FilledButton(
          onPressed: () => ref.read(dayClosureProvider.notifier).recalculate(),
          child: ManaText.raw(ref.t('recalculate')),
        ),
      ],
    );
  }
}

class _AmountField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _AmountField(
      {required this.label, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, prefixText: '₹ '),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _ExpectedRow extends StatelessWidget {
  final String label;
  final int value;
  const _ExpectedRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: ManaText.raw(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ManaType.secondary),
          ),
          const SizedBox(width: ManaSpacing.xs),
          ManaText.raw(manaRupees(value),
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ============================================================================
// S3 — Difference Analyzer
// ============================================================================

class _DifferenceAnalyzer extends ConsumerStatefulWidget {
  final String businessId;
  const _DifferenceAnalyzer({required this.businessId});

  @override
  ConsumerState<_DifferenceAnalyzer> createState() =>
      _DifferenceAnalyzerState();
}

class _DifferenceAnalyzerState extends ConsumerState<_DifferenceAnalyzer> {
  Future<void> _openAdjustmentDialog() async {
    final result = await showDialog<_AdjustmentInput>(
      context: context,
      builder: (_) => const _RecordAdjustmentDialog(),
    );
    if (result == null || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(dayClosureProvider.notifier).recordAdjustment(
            businessId: widget.businessId,
            adjustmentType: result.type,
            amount: result.amount,
            appliedTo: result.appliedTo,
            targetCustomerId: result.targetCustomerId,
            note: result.note,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dayClosureProvider);

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Icon(Icons.sync_problem, color: ManaColors.statusWarn, size: 36),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(ref.t('difference_found'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('overall_difference_note').replaceAll('{amount}', manaRupees(state.difference)),
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: ManaColors.statusBad),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(ref.t('difference_details'),
            style: ManaType.strong),
        const SizedBox(height: ManaSpacing.sm),
        ...state.differenceLines.map((l) => Card(
              child: ListTile(
                title: ManaText.raw(l.method),
                subtitle: ManaText.raw(ref
                    .t('expected_actual_note')
                    .replaceAll('{expected}', manaRupees(l.expected))
                    .replaceAll('{actual}', manaRupees(l.actual))),
                trailing: ManaText.raw(
                  manaRupees(l.delta),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: l.delta == 0
                        ? ManaColors.statusGood
                        : ManaColors.statusBad,
                  ),
                ),
              ),
            )),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(
          ref.t('owner_must_resolve_note'),
          style: ManaType.secondary,
        ),
        const SizedBox(height: ManaSpacing.md),
        if (state.recordedAdjustments.isNotEmpty) ...[
          ManaText.raw(ref.t('adjustments_recorded_session'),
              style: ManaType.strong),
          ...state.recordedAdjustments.map((a) => ListTile(
                leading: Icon(
                  a.adjustmentType == 'Short'
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  color: a.adjustmentType == 'Short'
                      ? ManaColors.statusBad
                      : ManaColors.statusWarn,
                ),
                title: ManaText.raw(
                    '${a.adjustmentType} · ${manaRupees(a.amount)}'),
                subtitle: ManaText.raw(a.appliedTo),
              )),
        ],
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _openAdjustmentDialog,
                child: ManaText.raw(ref.t('record_short_excess')),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: () =>
                    ref.read(dayClosureProvider.notifier).recalculate(),
                child: ManaText.raw(ref.t('recalculate')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdjustmentInput {
  final String type;
  final int amount;
  final String appliedTo;
  final String? targetCustomerId;
  final String? note;
  _AdjustmentInput({
    required this.type,
    required this.amount,
    required this.appliedTo,
    this.targetCustomerId,
    this.note,
  });
}

class _RecordAdjustmentDialog extends ConsumerStatefulWidget {
  const _RecordAdjustmentDialog();

  @override
  ConsumerState<_RecordAdjustmentDialog> createState() =>
      _RecordAdjustmentDialogState();
}

class _RecordAdjustmentDialogState extends ConsumerState<_RecordAdjustmentDialog> {
  String _type = 'Short';
  String _appliedTo = 'Agent Salary Deduction';
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _targetCustomerId = TextEditingController();

  static const _appliedToOptions = [
    'Agent Salary Deduction',
    'Customer Pending Settlement',
    'Excess Ledger-Unresolved',
  ];

  static const _appliedToKeys = {
    'Agent Salary Deduction': 'agent_salary_deduction',
    'Customer Pending Settlement': 'customer_pending_settlement',
    'Excess Ledger-Unresolved': 'excess_ledger_unresolved',
  };

  @override
  Widget build(BuildContext context) {
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final needsCustomer = _appliedTo == 'Customer Pending Settlement';
    final valid = amount > 0 &&
        (!needsCustomer || _targetCustomerId.text.trim().isNotEmpty);

    return AlertDialog(
      title: ManaText.raw(ref.t('record_short_excess')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'Short', label: ManaText.raw(ref.t('short'))),
                ButtonSegment(value: 'Excess', label: ManaText.raw(ref.t('excess'))),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  InputDecoration(labelText: ref.t('amount'), prefixText: '₹ '),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _appliedTo,
              decoration: InputDecoration(labelText: ref.t('applied_to')),
              items: _appliedToOptions
                  .map((o) => DropdownMenuItem(
                      value: o, child: ManaText.raw(ref.t(_appliedToKeys[o]!))))
                  .toList(),
              onChanged: (v) => setState(() => _appliedTo = v ?? _appliedTo),
            ),
            if (needsCustomer) ...[
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _targetCustomerId,
                decoration:
                    InputDecoration(labelText: ref.t('target_customer_id')),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: ref.t('note_optional')),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: ManaText.raw(ref.t('cancel'))),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(_AdjustmentInput(
                    type: _type,
                    amount: amount,
                    appliedTo: _appliedTo,
                    targetCustomerId:
                        needsCustomer ? _targetCustomerId.text.trim() : null,
                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                  ))
              : null,
          child: ManaText.raw(ref.t('save')),
        ),
      ],
    );
  }
}

// ============================================================================
// S4 — Final Review
// ============================================================================

class _FinalReview extends ConsumerStatefulWidget {
  final String businessId;
  const _FinalReview({required this.businessId});

  @override
  ConsumerState<_FinalReview> createState() => _FinalReviewState();
}

class _FinalReviewState extends ConsumerState<_FinalReview> {
  final _remarks = TextEditingController();

  Future<void> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('close_business_day_question')),
        content: ManaText.raw(ref.t('close_business_day_note')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: ManaText.raw(ref.t('confirm_close'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(dayClosureProvider.notifier).confirmClose(
            businessId: widget.businessId,
            remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
          );
    });
    if (ok != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: ManaText.raw(ref.t('difference_no_longer_zero_note'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dayClosureProvider);
    final expected = state.expected;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('final_review'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.lg),
        // day_ledger.opening_balance. Omitted rather than shown as 0 when the
        // ledger did not supply it — a stand-in zero beside the real figures
        // below reads as a day that opened with no cash.
        if (state.openingBalance != null)
          _SummaryRow(label: ref.t('opening_balance'), value: state.openingBalance!),
        if (expected != null)
          _SummaryRow(label: ref.t('collections'), value: expected.expectedCash),
        _SummaryRow(
            label: ref.t('adjustments'),
            value: state.recordedAdjustments.fold(0, (a, b) => a + b.amount)),
        const Divider(),
        _SummaryRow(
            label: ref.t('closing_balance_label'), value: state.actualTotal, bold: true),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ManaText.raw(ref.t('difference'),
                style: ManaType.strong),
            const SizedBox(width: ManaSpacing.xs),
            Flexible(
              child: ManaStatusPill(label: '₹0.00 — ${ref.t('balanced')}', status: ManaStatus.good),
            ),
          ],
        ),
        const SizedBox(height: ManaSpacing.lg),
        TextField(
          controller: _remarks,
          decoration: InputDecoration(labelText: ref.t('remarks_optional')),
          maxLines: 3,
        ),
        const SizedBox(height: ManaSpacing.xxl),
        FilledButton(
          onPressed: state.submitting ? null : _confirm,
          child: state.submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : ManaText.raw(ref.t('confirm_close_business_day')),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int value;
  final bool bold;
  const _SummaryRow(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: ManaText.raw(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bold ? ManaType.strong : null),
          ),
          const SizedBox(width: ManaSpacing.xs),
          ManaText.raw(manaRupees(value),
              style: bold
                  ? Theme.of(context).textTheme.titleMedium
                  : Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ============================================================================
// S5 — Closed (receipt view, also reached via OW-010 "past Closed day")
// ============================================================================

class _ClosedReceipt extends ConsumerWidget {
  final String businessId;
  const _ClosedReceipt({required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(dayClosureProvider).closureDetail;
    if (detail == null) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Icon(Icons.lock, color: ManaColors.statusGood, size: 36),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(ref.t('business_day_closed'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
            ref
                .t('closed_by_note')
                .replaceAll('{date}', detail.businessDate)
                .replaceAll('{name}', detail.closedByName),
            style: ManaType.secondary),
        const SizedBox(height: ManaSpacing.lg),
        _SummaryRow(label: ref.t('opening_balance'), value: detail.openingBalance),
        _SummaryRow(label: ref.t('collections'), value: detail.collections),
        _SummaryRow(label: ref.t('loans_issued'), value: detail.loansIssued),
        _SummaryRow(label: ref.t('expenses'), value: detail.expenses),
        _SummaryRow(
            label: ref.t('deposits_investor'), value: detail.depositsInvestor),
        _SummaryRow(
            label: ref.t('withdrawals_investor'), value: detail.withdrawalsInvestor),
        _SummaryRow(label: ref.t('adjustments'), value: detail.adjustments),
        const Divider(),
        _SummaryRow(
            label: ref.t('closing_balance_label'), value: detail.closingBalance, bold: true),
        if (detail.remarks != null) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(ref.t('remarks_colon_note').replaceAll('{remarks}', detail.remarks!),
              style: ManaType.secondary),
        ],
        if (detail.isReopened) ...[
          const SizedBox(height: ManaSpacing.md),
          Card(
            color: ManaColors.statusWarnFaint,
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.md),
              child: ManaText.raw(
                ref
                    .t('reopened_reason_note')
                    .replaceAll('{at}', '${detail.reopenedAt}')
                    .replaceAll('{reason}', '${detail.reopenReason}'),
                style: TextStyle(color: ManaColors.statusWarn),
              ),
            ),
          ),
        ],
        const SizedBox(height: ManaSpacing.xxl),
        OutlinedButton(
          onPressed: () => _openReopenDialog(context, ref),
          child: ManaText.raw(ref.t('reopen_closed_day')),
        ),
      ],
    );
  }

  Future<void> _openReopenDialog(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('reopen_closed_day')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(
              ref.t('reopen_note'),
              style: ManaType.secondary,
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(labelText: ref.t('reason_required')),
              maxLines: 2,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(reasonController.text.trim()),
            child: ManaText.raw(ref.t('reopen')),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !context.mounted) return;

    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(dayClosureProvider.notifier)
          .reopenClosedDay(reason: reason);
    });
  }
}

// ============================================================================
// S6 — Reopened, awaiting Close Again
// ============================================================================

class _ReopenedAwaitingCloseAgain extends ConsumerWidget {
  final String businessId;
  const _ReopenedAwaitingCloseAgain({required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Icon(Icons.lock_open, color: ManaColors.statusWarn, size: 36),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(ref.t('day_reopened'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('reopened_awaiting_note'),
          style: ManaType.secondary,
        ),
        const SizedBox(height: ManaSpacing.xxl),
        FilledButton(
          onPressed: () => ref
              .read(dayClosureProvider.notifier)
              .closeAgain(businessId: businessId),
          child: ManaText.raw(ref.t('close_again')),
        ),
      ],
    );
  }
}
