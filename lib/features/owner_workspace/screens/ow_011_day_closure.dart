import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/day_closure_state.dart';

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

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

    return Scaffold(
      appBar: AppBar(title: const ManaText('day closure')),
      body: SafeArea(child: _buildBody(context, state)),
    );
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

class _PreCheckBlocked extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const Icon(Icons.block, color: ManaColors.statusBad, size: 40),
        const SizedBox(height: ManaSpacing.sm),
        Text('Day Closure Cannot Start',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        const ManaText.raw(
          'The following items must be resolved before Cash Verification can open.',
          style: TextStyle(color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ...state.blockingIssues.map((issue) => Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline,
                    color: ManaColors.statusBad),
                title: ManaText.raw(issue.type),
                subtitle: ManaText.raw('${issue.count} item(s) outstanding'),
                trailing: _routeFor(issue.type) != null
                    ? FilledButton(
                        onPressed: () => context.push(_routeFor(issue.type)!),
                        child: const ManaText('resolve'),
                      )
                    : null,
              ),
            )),
        if (state.warnings.isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.lg),
          const ManaText('warnings (may proceed)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.xs),
          ...state.warnings.map((w) => Card(
                color: ManaColors.statusWarnFaint,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber,
                      color: ManaColors.statusWarn),
                  title: ManaText.raw(w.type),
                  subtitle: ManaText.raw('${w.count} item(s)'),
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
        Text('Cash Verification',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        const ManaText.raw(
          'Enter the physical count — actual on-hand — for each payment method.',
          style: TextStyle(color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        _AmountField(
            label: 'Physical Cash', controller: _cash, onChanged: _onChanged),
        _AmountField(
            label: 'UPI Balance', controller: _upi, onChanged: _onChanged),
        _AmountField(
            label: 'Bank Balance', controller: _bank, onChanged: _onChanged),
        _AmountField(
            label: 'Cheque Balance',
            controller: _cheque,
            onChanged: _onChanged),
        const SizedBox(height: ManaSpacing.lg),
        if (expected != null) ...[
          const ManaText('system expected (computed)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.sm),
          _ExpectedRow(label: 'Expected Cash', value: expected.expectedCash),
          _ExpectedRow(label: 'Expected UPI', value: expected.expectedUpi),
          _ExpectedRow(label: 'Expected Bank', value: expected.expectedBank),
          _ExpectedRow(
              label: 'Expected Cheque', value: expected.expectedCheque),
        ],
        const SizedBox(height: ManaSpacing.xxl),
        FilledButton(
          onPressed: () => ref.read(dayClosureProvider.notifier).recalculate(),
          child: const ManaText('recalculate'),
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
          ManaText.raw(label,
              style: const TextStyle(color: ManaColors.textSecondary)),
          Text(_currency.format(value),
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
        const Icon(Icons.sync_problem, color: ManaColors.statusWarn, size: 36),
        const SizedBox(height: ManaSpacing.sm),
        Text('Difference Found',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        Text(
          'Overall Difference: ${_currency.format(state.difference)}',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: ManaColors.statusBad),
        ),
        const SizedBox(height: ManaSpacing.lg),
        const ManaText('difference details',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        ...state.differenceLines.map((l) => Card(
              child: ListTile(
                title: ManaText.raw(l.method),
                subtitle: Text(
                    'Expected ${_currency.format(l.expected)} · Actual ${_currency.format(l.actual)}'),
                trailing: Text(
                  _currency.format(l.delta),
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
        const ManaText.raw(
          'Owner must resolve — correct a mis-entered Actual figure above, or '
          'record a Short/Excess adjustment, then Recalculate.',
          style: TextStyle(color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        if (state.recordedAdjustments.isNotEmpty) ...[
          const ManaText('adjustments recorded this session',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ...state.recordedAdjustments.map((a) => ListTile(
                leading: Icon(
                  a.adjustmentType == 'Short'
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  color: a.adjustmentType == 'Short'
                      ? ManaColors.statusBad
                      : ManaColors.statusWarn,
                ),
                title:
                    Text('${a.adjustmentType} · ${_currency.format(a.amount)}'),
                subtitle: ManaText.raw(a.appliedTo),
              )),
        ],
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _openAdjustmentDialog,
                child: const ManaText('record short / excess'),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: () =>
                    ref.read(dayClosureProvider.notifier).recalculate(),
                child: const ManaText('recalculate'),
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

class _RecordAdjustmentDialog extends StatefulWidget {
  const _RecordAdjustmentDialog();

  @override
  State<_RecordAdjustmentDialog> createState() =>
      _RecordAdjustmentDialogState();
}

class _RecordAdjustmentDialogState extends State<_RecordAdjustmentDialog> {
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

  @override
  Widget build(BuildContext context) {
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final needsCustomer = _appliedTo == 'Customer Pending Settlement';
    final valid = amount > 0 &&
        (!needsCustomer || _targetCustomerId.text.trim().isNotEmpty);

    return AlertDialog(
      title: const ManaText('record short / excess'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Short', label: ManaText.raw('Short')),
                ButtonSegment(value: 'Excess', label: ManaText.raw('Excess')),
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
                  const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _appliedTo,
              decoration: const InputDecoration(labelText: 'Applied To'),
              items: _appliedToOptions
                  .map(
                      (o) => DropdownMenuItem(value: o, child: ManaText.raw(o)))
                  .toList(),
              onChanged: (v) => setState(() => _appliedTo = v ?? _appliedTo),
            ),
            if (needsCustomer) ...[
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _targetCustomerId,
                decoration:
                    const InputDecoration(labelText: 'Target Customer ID'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const ManaText('cancel')),
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
          child: const ManaText('save'),
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
        title: const ManaText('close business day?'),
        content: const ManaText.raw(
          'This locks the Business Date, generates the Daily Summary, and '
          'prepares the next Business Date. This action cannot be undone '
          'without an Owner Reopen.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const ManaText('cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const ManaText('confirm close')),
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
        const SnackBar(
            content: Text('Difference is no longer zero — recheck required.')),
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
        Text('Final Review', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.lg),
        const _SummaryRow(
            label: 'Opening Balance',
            value: 0), // TODO: from day_ledger, deferred to API pass
        if (expected != null)
          _SummaryRow(label: 'Collections', value: expected.expectedCash),
        _SummaryRow(
            label: 'Adjustments',
            value: state.recordedAdjustments.fold(0, (a, b) => a + b.amount)),
        const Divider(),
        _SummaryRow(
            label: 'Closing Balance', value: state.actualTotal, bold: true),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ManaText('Difference',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ManaStatusPill(label: '₹0.00 — Balanced', status: ManaStatus.good),
          ],
        ),
        const SizedBox(height: ManaSpacing.lg),
        TextField(
          controller: _remarks,
          decoration: const InputDecoration(labelText: 'Remarks (optional)'),
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
              : const ManaText('confirm — close business day'),
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
          ManaText(label,
              style:
                  bold ? const TextStyle(fontWeight: FontWeight.bold) : null),
          Text(_currency.format(value),
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
        const Icon(Icons.lock, color: ManaColors.statusGood, size: 36),
        const SizedBox(height: ManaSpacing.sm),
        Text('Business Day Closed',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
            '${detail.businessDate} · Closed by ${detail.closedByName}',
            style: const TextStyle(color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.lg),
        _SummaryRow(label: 'Opening Balance', value: detail.openingBalance),
        _SummaryRow(label: 'Collections', value: detail.collections),
        _SummaryRow(label: 'Loans Issued', value: detail.loansIssued),
        _SummaryRow(label: 'Expenses', value: detail.expenses),
        _SummaryRow(
            label: 'Deposits (Investor)', value: detail.depositsInvestor),
        _SummaryRow(
            label: 'Withdrawals (Investor)', value: detail.withdrawalsInvestor),
        _SummaryRow(label: 'Adjustments', value: detail.adjustments),
        const Divider(),
        _SummaryRow(
            label: 'Closing Balance', value: detail.closingBalance, bold: true),
        if (detail.remarks != null) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw('Remarks: ${detail.remarks}',
              style: const TextStyle(color: ManaColors.textSecondary)),
        ],
        if (detail.isReopened) ...[
          const SizedBox(height: ManaSpacing.md),
          Card(
            color: ManaColors.statusWarnFaint,
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.md),
              child: ManaText.raw(
                'Reopened ${detail.reopenedAt} — Reason: ${detail.reopenReason}',
                style: const TextStyle(color: ManaColors.statusWarn),
              ),
            ),
          ),
        ],
        const SizedBox(height: ManaSpacing.xxl),
        OutlinedButton(
          onPressed: () => _openReopenDialog(context, ref),
          child: const ManaText('reopen closed day'),
        ),
      ],
    );
  }

  Future<void> _openReopenDialog(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const ManaText('reopen closed day'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText.raw(
              'Reason is mandatory and this action always writes an audit entry. '
              'Reopening unlocks new adjustment entries only — existing entries '
              'for this date cannot be edited.',
              style: TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason *'),
              maxLines: 2,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const ManaText('cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(reasonController.text.trim()),
            child: const ManaText('reopen'),
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
        const Icon(Icons.lock_open, color: ManaColors.statusWarn, size: 36),
        const SizedBox(height: ManaSpacing.sm),
        Text('Day Reopened', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        const ManaText.raw(
          'Only new adjustment entries dated to this business day are permitted. '
          'Existing Collections, Loans, and Expenses for this date cannot be '
          'edited. Once adjustments are entered, run Close Again to re-close.',
          style: TextStyle(color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.xxl),
        FilledButton(
          onPressed: () => ref
              .read(dayClosureProvider.notifier)
              .closeAgain(businessId: businessId),
          child: const ManaText('close again'),
        ),
      ],
    );
  }
}
