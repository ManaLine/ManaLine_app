import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/collection_mode_state.dart';
import 'package:go_router/go_router.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// OW-006 — Collection Mode. Dashboard (due list) is the default landing
/// state; tapping a customer opens Collection Entry for their due loan.
class CollectionModeScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String? prefilledLoanId;
  const CollectionModeScreen({super.key, required this.businessId, this.prefilledLoanId});

  @override
  ConsumerState<CollectionModeScreen> createState() => _CollectionModeScreenState();
}

class _CollectionModeScreenState extends ConsumerState<CollectionModeScreen> {
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
      appBar: AppBar(
leading: BackButton(onPressed: () => context.go('/ow-001', extra: widget.businessId)),
        title: const ManaText('collection mode'),
),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(collectionModeProvider.notifier).load(widget.businessId),
          child: state.loading && state.dueList.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    _SummaryStrip(state: state),
                    const SizedBox(height: ManaSpacing.xs),
                    const ManaText.raw(
                      'Sorted by: penalty → grace period → today\'s due → village → name',
                      style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                    ),
                    const SizedBox(height: ManaSpacing.md),
                    if (state.sorted.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw('Nobody due today.',
                              style: TextStyle(color: ManaColors.textSecondary)),
                        ),
                      )
                    else
                      ...state.sorted.map((row) => _DueRow(
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

class _SummaryStrip extends StatelessWidget {
  final CollectionModeState state;
  const _SummaryStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String, ManaStatus)>[
      ('Total Due', '${state.totalDue}', ManaStatus.neutral),
      ('Collected', '${state.collected}', ManaStatus.good),
      ('Pending', '${state.pending}', ManaStatus.warn),
      ('Skipped', '${state.skipped}', ManaStatus.neutral),
      ('Penalty', '${state.penaltyCount}', ManaStatus.bad),
      ('Grace Period', '${state.graceCount}', ManaStatus.warn),
      ('Live Collected', _currency.format(state.liveCollectionAmount), ManaStatus.good),
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
              width: 120,
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

class _DueRow extends StatelessWidget {
  final CollectionDueRow row;
  final VoidCallback onTap;
  const _DueRow({required this.row, required this.onTap});

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
        subtitle: ManaText.raw('${row.village} · ${row.loanNumber}',
            style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ManaText.raw(_currency.format(row.installmentDue),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ManaText.raw('LRI ${row.lineRepaymentIndex}',
                style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// --- Collection Entry -------------------------------------------------

enum _EntryAction { none, collect, noCollection, extension }

class CollectionEntryScreen extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  const CollectionEntryScreen({super.key, required this.row});

  @override
  ConsumerState<CollectionEntryScreen> createState() => _CollectionEntryScreenState();
}

class _CollectionEntryScreenState extends ConsumerState<CollectionEntryScreen> {
  _EntryAction _action = _EntryAction.none;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Scaffold(
      appBar: AppBar(title: ManaText.raw(row.customerName)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(ManaSpacing.md),
                child: Column(
                  children: [
                    _row('Loan Number', row.loanNumber),
                    _row('Installment Due', _currency.format(row.installmentDue)),
                    _row('Outstanding Balance', _currency.format(row.outstandingBalance)),
                    _row('Line Repayment Index', '${row.lineRepaymentIndex}'),
                    _row('Grace Status', row.gracePeriod ? 'In Grace Period' : 'Normal'),
                    _row('Penalty Status', row.penaltyEligible ? 'Penalty Eligible' : 'None'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: ManaSpacing.lg),
            if (_action == _EntryAction.none) ...[
              ElevatedButton(
                onPressed: () => setState(() => _action = _EntryAction.collect),
                child: const ManaText('enter collection'),
              ),
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton(
                onPressed: () => setState(() => _action = _EntryAction.noCollection),
                child: const ManaText('no collection (visit without payment)'),
              ),
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton(
                onPressed: () => setState(() => _action = _EntryAction.extension),
                child: const ManaText('request extension'),
              ),
            ],
            if (_action == _EntryAction.collect) _EnterCollectionForm(row: row, onCancel: () => setState(() => _action = _EntryAction.none)),
            if (_action == _EntryAction.noCollection)
              _NoCollectionForm(row: row, onCancel: () => setState(() => _action = _EntryAction.none)),
            if (_action == _EntryAction.extension)
              _ExtensionForm(row: row, onCancel: () => setState(() => _action = _EntryAction.none)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: ManaText(label, style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}

// --- Action A: Enter Collection ------------------------------------------

class _EnterCollectionForm extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final VoidCallback onCancel;
  const _EnterCollectionForm({required this.row, required this.onCancel});

  @override
  ConsumerState<_EnterCollectionForm> createState() => _EnterCollectionFormState();
}

class _EnterCollectionFormState extends ConsumerState<_EnterCollectionForm> {
  final _amount = TextEditingController();
  String _payerType = 'Customer';
  bool _mixed = false;
  final _cashAmount = TextEditingController();
  final _upiAmount = TextEditingController();
  String? _excessDisposition;
  bool _submitting = false;

  double get _collected => double.tryParse(_amount.text) ?? 0;
  double get _splitSum => (double.tryParse(_cashAmount.text) ?? 0) + (double.tryParse(_upiAmount.text) ?? 0);

  String get _resultType {
    if (_collected == widget.row.installmentDue) return 'Full';
    if (_collected < widget.row.installmentDue) return 'Partial';
    return 'Excess';
  }

  bool get _canSubmit {
    if (_collected <= 0) return false;
    if (_mixed && (_splitSum - _collected).abs() > 0.01) return false;
    if (_resultType == 'Excess' && _excessDisposition == null) return false;
    return true;
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final splits = _mixed
        ? [
            PaymentSplit(paymentMode: 'Cash', amount: double.tryParse(_cashAmount.text) ?? 0),
            PaymentSplit(paymentMode: 'UPI', amount: double.tryParse(_upiAmount.text) ?? 0),
          ]
        : [PaymentSplit(paymentMode: 'Cash', amount: _collected)];

    final result = await NetworkErrorHandler.run(context, () async {
      final r = await ref.read(collectionModeProvider.notifier).recordCollection(
            loanId: widget.row.loanId,
            collectedAmount: _collected,
            payerType: _payerType,
            paymentSplits: splits,
            excessDisposition: _excessDisposition,
          );
      if (r == null) throw Exception('Collection could not be saved.');
      return r;
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) return;
    if (!mounted) return;
    _showReceiptAndNavigate(result);
  }

  void _showReceiptAndNavigate(CollectionResult result) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const ManaText('receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw('Receipt #${result.receiptNumber}'),
            ManaText.raw('${result.resultType} · ${_currency.format(result.collectedAmount)}'),
            ManaText.raw('New Balance: ${_currency.format(result.newOutstandingBalance)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pop(); // entry screen → back to dashboard
            },
            child: const ManaText('done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Collected Amount *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _payerType,
          decoration: const InputDecoration(labelText: 'Payer'),
          items: const [
            DropdownMenuItem(value: 'Customer', child: Text('Customer')),
            DropdownMenuItem(value: 'Guarantor', child: Text('Guarantor')),
          ],
          onChanged: (v) => setState(() => _payerType = v ?? 'Customer'),
        ),
        const SizedBox(height: ManaSpacing.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const ManaText('mixed payment'),
          value: _mixed,
          onChanged: (v) => setState(() => _mixed = v),
        ),
        if (_mixed) ...[
          TextField(
            controller: _cashAmount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cash'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.sm),
          TextField(
            controller: _upiAmount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'UPI'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw('Split sum: ${_currency.format(_splitSum)} (must equal collected amount)',
              style: TextStyle(
                fontSize: 16,
                color: (_splitSum - _collected).abs() > 0.01 ? ManaColors.statusBad : ManaColors.statusGood,
              )),
        ],
        if (_collected > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
            child: ManaStatusPill(
              label: _resultType,
              status: _resultType == 'Full'
                  ? ManaStatus.good
                  : _resultType == 'Partial'
                      ? ManaStatus.warn
                      : ManaStatus.neutral,
            ),
          ),
        if (_resultType == 'Excess' && _collected > 0) ...[
          const SizedBox(height: ManaSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _excessDisposition,
            decoration: const InputDecoration(labelText: 'Excess Disposition *'),
            items: const [
              DropdownMenuItem(value: 'Advance', child: Text('Advance')),
              DropdownMenuItem(value: 'Refund', child: Text('Refund')),
              DropdownMenuItem(value: 'Next Installment', child: Text('Next Installment')),
            ],
            onChanged: (v) => setState(() => _excessDisposition = v),
          ),
        ],
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: _submitting ? null : widget.onCancel, child: const ManaText('cancel')),
            ),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: (_canSubmit && !_submitting) ? _submit : null,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const ManaText('save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Action B: No Collection ------------------------------------------

class _NoCollectionForm extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final VoidCallback onCancel;
  const _NoCollectionForm({required this.row, required this.onCancel});

  @override
  ConsumerState<_NoCollectionForm> createState() => _NoCollectionFormState();
}

class _NoCollectionFormState extends ConsumerState<_NoCollectionForm> {
  String? _reason;
  bool _submitting = false;

  static const _reasons = ['Customer Not Available', 'Customer Refused', 'Requested Later Visit', 'Other'];

  Future<void> _submit() async {
    if (_reason == null) return;
    setState(() => _submitting = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(collectionModeProvider.notifier).recordNoCollectionVisit(loanId: widget.row.loanId, reason: _reason!);
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _reason,
          decoration: const InputDecoration(labelText: 'Visit Reason *'),
          items: _reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) => setState(() => _reason = v),
        ),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: _submitting ? null : widget.onCancel, child: const ManaText('cancel')),
            ),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: (_reason != null && !_submitting) ? _submit : null,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const ManaText('save visit'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Action C: Request Extension ------------------------------------------

class _ExtensionForm extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final VoidCallback onCancel;
  const _ExtensionForm({required this.row, required this.onCancel});

  @override
  ConsumerState<_ExtensionForm> createState() => _ExtensionFormState();
}

class _ExtensionFormState extends ConsumerState<_ExtensionForm> {
  bool _submitting = false;

  Future<void> _decide(bool approve) async {
    setState(() => _submitting = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref
          .read(collectionModeProvider.notifier)
          .requestAndDecideExtension(loanId: widget.row.loanId, approve: approve);
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'Extension approved.' : 'Extension rejected.')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ManaText.raw(
          'Customer is requesting more time on this loan. Approving updates Grace '
          'Status and writes an audit entry; rejecting makes no change and is not audited.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => _decide(false),
                child: const ManaText('reject'),
              ),
            ),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              child: ElevatedButton(
                onPressed: _submitting ? null : () => _decide(true),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const ManaText('approve'),
              ),
            ),
          ],
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextButton(onPressed: _submitting ? null : widget.onCancel, child: const ManaText('cancel')),
      ],
    );
  }
}
