import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/idempotency.dart';
import '../../../shared/widgets/address_check_banner.dart';
import '../../../shared/translation_service.dart';
import '../state/collection_mode_state.dart';
import '../../../shared/collection_round_view.dart';
import 'package:go_router/go_router.dart';


/// OW-006 — Collection Mode. Dashboard (due list) is the default landing
/// state; tapping a customer opens Collection Entry for their due loan.
/// OW-006 — Collection Mode (Owner).
///
/// The round itself is ManaCollectionRound, shared with AG-002. Both screens
/// rendered the same provider through two hand-maintained lists and drifted:
/// this one gained village filters, a sort picker and a Pay button while the
/// Agent -- who actually walks the round -- kept the old one.
///
/// Sharing the list cannot merge the two workspaces' entries. record_collection
/// attributes a payment from the caller's own membership and checks
/// `own_active_agent_membership_permits`, so who is credited is decided by the
/// database, not by which screen was on screen.
class CollectionModeScreen extends ConsumerWidget {
  final String businessId;

  /// Passed by the router from `extra`. See ManaCollectionRound.focusLoanId --
  /// it was declared here and never read, so every "open this loan's
  /// collection" link landed on the plain round.
  final String? prefilledLoanId;

  const CollectionModeScreen(
      {super.key, required this.businessId, this.prefilledLoanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaCollectionRound(
      businessId: businessId,
      focusLoanId: prefilledLoanId,
      onBack: () => context.go('/ow-001', extra: businessId),
      onOpenRow: (context, row) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CollectionEntryScreen(row: row, businessId: businessId),
        ),
      ),
    );
  }
}

// --- Collection Entry -------------------------------------------------

enum _EntryAction { none, collect, noCollection, extension }

class CollectionEntryScreen extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final String businessId; // needed to resolve the collector's membership
  const CollectionEntryScreen({super.key, required this.row, required this.businessId});

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
            // Whether this is the customer's registered address. Purely
            // informational — it never blocks a collection, because collecting
            // at a shop or a relative's house is ordinary and a customer who
            // moved has done nothing wrong.
            AddressCheckBanner(customerId: row.customerId),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(ManaSpacing.md),
                child: Column(
                  children: [
                    _row(ref.t('loan_number'), row.loanNumber),
                    _row(ref.t('installment_due'), manaRupees(row.installmentDue)),
                    _row(ref.t('outstanding_balance'), manaRupees(row.outstandingBalance)),
                    _row(ref.t('line_repayment_index'), '${row.lineRepaymentIndex}'),
                    _row(ref.t('grace_status'), row.gracePeriod ? ref.t('in_grace_period') : ref.t('normal')),
                    _row(ref.t('penalty_status'), row.penaltyEligible ? ref.t('penalty_eligible') : ref.t('none')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: ManaSpacing.lg),
            if (_action == _EntryAction.none) ...[
              ElevatedButton(
                onPressed: () => setState(() => _action = _EntryAction.collect),
                child: ManaText.raw(ref.t('enter_collection')),
              ),
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton(
                onPressed: () => setState(() => _action = _EntryAction.noCollection),
                child: ManaText.raw(ref.t('no_collection_visit_without_payment')),
              ),
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton(
                onPressed: () => setState(() => _action = _EntryAction.extension),
                child: ManaText.raw(ref.t('request_extension')),
              ),
            ],
            if (_action == _EntryAction.collect)
              _EnterCollectionForm(row: row, businessId: widget.businessId, onCancel: () => setState(() => _action = _EntryAction.none)),
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
            Expanded(child: ManaText.raw(label, style: ManaType.note)),
            ManaText.raw(value, style: ManaType.smallStrong),
          ],
        ),
      );
}

// --- Action A: Enter Collection ------------------------------------------

class _EnterCollectionForm extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final String businessId;
  final VoidCallback onCancel;
  const _EnterCollectionForm({required this.row, required this.businessId, required this.onCancel});

  @override
  ConsumerState<_EnterCollectionForm> createState() => _EnterCollectionFormState();
}

class _EnterCollectionFormState extends ConsumerState<_EnterCollectionForm> {
  final _amount = TextEditingController();
  // Customer unless the Agent says otherwise. Asking who paid on every single
  // collection is a decision on the overwhelmingly common case, made standing
  // at a doorstep — so the question only appears when it is answered.
  String _payerType = 'Customer';
  final _payerName = TextEditingController();
  bool _mixed = false;
  final _cashAmount = TextEditingController();
  final _upiAmount = TextEditingController();
  String? _excessDisposition;
  bool _submitting = false;
  // Becomes true after the user taps "Continue" on the duplicate warning,
  // so the retry tells the server to record the payment anyway.
  bool _confirmDuplicate = false;

  /// Minted once per save the person commits to, and reused by every retry of
  /// it — including NetworkErrorHandler's Retry button and the "Continue"
  /// path out of the duplicate warning, which both re-enter _submit(). On a
  /// dropped 2G reply that is what stops the same collection being recorded
  /// twice. Cleared after a save lands so the next one is a new action.
  String? _idempotencyKey;

  // Whole rupees (M8) — money is never a double in this app.
  int get _collected => int.tryParse(_amount.text) ?? 0;
  int get _splitSum => (int.tryParse(_cashAmount.text) ?? 0) + (int.tryParse(_upiAmount.text) ?? 0);

  String get _resultType {
    if (_collected == widget.row.installmentDue) return 'Full';
    if (_collected < widget.row.installmentDue) return 'Partial';
    return 'Excess';
  }

  bool get _canSubmit {
    if (_collected <= 0) return false;
    if (_mixed && (_splitSum - _collected) != 0) return false;
    if (_resultType == 'Excess' && _excessDisposition == null) return false;
    return true;
  }

  Future<void> _submit() async {
    // Minted here, on the first attempt only: a key created inside the retry
    // closure would be new every time, which is the same as having none.
    _idempotencyKey ??= manaIdempotencyKey();
    setState(() => _submitting = true);
    final splits = _mixed
        ? [
            PaymentSplit(paymentMode: 'Cash', amount: int.tryParse(_cashAmount.text) ?? 0),
            PaymentSplit(paymentMode: 'UPI', amount: int.tryParse(_upiAmount.text) ?? 0),
          ]
        : [PaymentSplit(paymentMode: 'Cash', amount: _collected)];

    final outcome = await NetworkErrorHandler.run(context, () async {
      final o = await ref.read(collectionModeProvider.notifier).recordCollection(
            loanId: widget.row.loanId,
            customerId: widget.row.customerId,
            collectedAmount: _collected,
            payerType: _payerType,
            payerName: _payerName.text.trim().isEmpty ? null : _payerName.text.trim(),
            paymentSplits: splits,
            businessDate: manaBusinessDate(),
            businessId: widget.businessId,
            excessDisposition: _excessDisposition,
            confirmDuplicate: _confirmDuplicate,
            idempotencyKey: _idempotencyKey,
          );
      if (o == null) throw Exception('Collection could not be saved.');
      return o;
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (outcome == null) return;

    // Another member already collected this loan today — warn and ask.
    if (outcome.duplicateWarning) {
      await _showDuplicateDialog(outcome.existing);
      return;
    }
    if (!mounted) return;
    // Landed. The next save is a new action, not a replay of this one.
    _idempotencyKey = null;
    _showReceiptAndNavigate(outcome.saved!);
  }

  /// Warns that this loan already has a payment recorded today by someone
  /// else. "Close" aborts; "Continue" re-saves with the confirmation flag.
  Future<void> _showDuplicateDialog(List<Map<String, dynamic>> existing) async {
    final first = existing.isNotEmpty ? existing.first : const <String, dynamic>{};
    final amount = (first['collected_amount'] as num?)?.toDouble() ?? 0;
    final by = first['recorded_by'] as String? ?? 'another agent';
    final action = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('already_collected_today')),
        content: ManaText.raw(
          ref
              .t('already_collected_note')
              .replaceAll('{by}', by)
              .replaceAll('{amount}', manaRupees(amount)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: ManaText.raw(ref.t('close'))),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: ManaText.raw(ref.t('continue_button'))),
        ],
      ),
    );
    if (!mounted) return;
    if (action == true) {
      setState(() => _confirmDuplicate = true);
      await _submit(); // retry — this time the server records it
    } else {
      setState(() => _confirmDuplicate = false); // close — nothing recorded
    }
  }

  void _showReceiptAndNavigate(CollectionResult result) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('receipt')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('receipt_number').replaceAll('{number}', result.receiptNumber)),
            ManaText.raw('${result.resultType} · ${manaRupees(result.collectedAmount)}'),
            ManaText.raw(ref.t('new_balance').replaceAll('{amount}', manaRupees(result.newOutstandingBalance))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pop(); // entry screen → back to dashboard
            },
            child: ManaText.raw(ref.t('done')),
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
          decoration: InputDecoration(labelText: ref.t('collected_amount_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        // Nothing to answer in the normal case; one tap opens it when somebody
        // else handed the money over.
        if (_payerType == 'Customer')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _payerType = 'Others'),
              icon: const Icon(Icons.person_outline, size: 18),
              label: ManaText.raw(ref.t('someone_else_paid')),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _payerName,
                  textCapitalization: TextCapitalization.words,
                  // Optional on purpose: the Agent often does not know the
                  // full name of the son or neighbour who handed it over, and
                  // demanding one would push them back to "Customer".
                  decoration: InputDecoration(labelText: ref.t('who_paid_optional')),
                ),
              ),
              IconButton(
                tooltip: ref.t('customer'),
                onPressed: () => setState(() {
                  _payerType = 'Customer';
                  _payerName.clear();
                }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
        const SizedBox(height: ManaSpacing.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: ManaText.raw(ref.t('mixed_payment')),
          value: _mixed,
          onChanged: (v) => setState(() => _mixed = v),
        ),
        if (_mixed) ...[
          TextField(
            controller: _cashAmount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: ref.t('cash')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.sm),
          TextField(
            controller: _upiAmount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: ref.t('upi')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(ref.t('split_sum_note').replaceAll('{amount}', manaRupees(_splitSum)),
              style: TextStyle(
                fontSize: 16,
                color: (_splitSum - _collected) != 0 ? ManaColors.statusBad : ManaColors.statusGood,
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
            decoration: InputDecoration(labelText: ref.t('excess_disposition_field')),
            items: [
              DropdownMenuItem(value: 'Advance', child: ManaText.raw(ref.t('advance'))),
              DropdownMenuItem(value: 'Refund', child: ManaText.raw(ref.t('refund'))),
              DropdownMenuItem(value: 'Next Installment', child: ManaText.raw(ref.t('next_installment'))),
            ],
            onChanged: (v) => setState(() => _excessDisposition = v),
          ),
        ],
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: _submitting ? null : widget.onCancel, child: ManaText.raw(ref.t('cancel'))),
            ),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: (_canSubmit && !_submitting) ? _submit : null,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : ManaText.raw(ref.t('save')),
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
  static const _reasonKeys = {
    'Customer Not Available': 'customer_not_available',
    'Customer Refused': 'customer_refused',
    'Requested Later Visit': 'requested_later_visit',
    'Other': 'other',
  };

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
          decoration: InputDecoration(labelText: ref.t('visit_reason_field')),
          items: _reasons.map((r) => DropdownMenuItem(value: r, child: ManaText.raw(ref.t(_reasonKeys[r]!)))).toList(),
          onChanged: (v) => setState(() => _reason = v),
        ),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: _submitting ? null : widget.onCancel, child: ManaText.raw(ref.t('cancel'))),
            ),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: (_reason != null && !_submitting) ? _submit : null,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : ManaText.raw(ref.t('save_visit')),
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
        SnackBar(content: ManaText.raw(approve ? ref.t('extension_approved') : ref.t('extension_rejected'))),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(
          ref.t('extension_note'),
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => _decide(false),
                child: ManaText.raw(ref.t('reject')),
              ),
            ),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              child: ElevatedButton(
                onPressed: _submitting ? null : () => _decide(true),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : ManaText.raw(ref.t('approve')),
              ),
            ),
          ],
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextButton(onPressed: _submitting ? null : widget.onCancel, child: ManaText.raw(ref.t('cancel'))),
      ],
    );
  }
}
