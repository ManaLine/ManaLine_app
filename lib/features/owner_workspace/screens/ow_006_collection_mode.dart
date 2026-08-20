import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_collection_search_field.dart';
import '../../../design/components/mana_frequency_picker.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/widgets/address_check_banner.dart';
import '../../../shared/translation_service.dart';
import '../state/collection_mode_state.dart';
import 'package:go_router/go_router.dart';


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
  /// Local, not in the notifier: searching narrows what is on screen, it does
  /// not change the round. Keeping it out of the notifier is also what stops a
  /// reload from silently re-applying it.
  String _query = '';
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(collectionModeProvider.notifier).load(widget.businessId);
    });
  }


  /// Daily / Weekly / Monthly, or null for the whole round. Kept in the screen
  /// rather than the notifier because it is a view preference, not state the
  /// collection itself depends on — reloading the round must not silently
  /// re-narrow it.
  String? _frequency;

  Widget _frequencyPicker() => ManaFrequencyPicker(
        value: _frequency,
        onChanged: (f) => setState(() => _frequency = f),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectionModeProvider);
    final visible = manaFilterDueRows(state.sorted, _query, frequency: _frequency);

    return Scaffold(
      appBar: AppBar(
leading: BackButton(onPressed: () => context.go('/ow-001', extra: widget.businessId)),
        title: ManaText.raw(ref.t('collection_mode')),
        actions: [
          IconButton(
            icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
            tooltip: ref.t('search'),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              // Closing the search restores the full round. Leaving a filter
              // applied behind a collapsed box is how an Agent finishes the
              // day believing they visited everyone.
              if (!_searchOpen) _query = '';
            }),
          ),
        ],
        bottom: _searchOpen
            ? ManaCollectionSearchField(
                onChanged: (v) => setState(() => _query = v),
              )
            : null,
),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(collectionModeProvider.notifier).load(widget.businessId),
          child: state.loading && state.dueList.isEmpty
              ? const ManaSkeletonList()
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    _frequencyPicker(),
                    ManaText.raw(
                      ref.t('sorted_by_note'),
                      style: ManaType.note,
                    ),
                    const SizedBox(height: ManaSpacing.md),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          // "Nobody is due" and "nothing matched what you
                          // typed" are different facts, and telling an Agent
                          // the first when the second is true would read as an
                          // empty round.
                          child: ManaText.raw(
                              _query.trim().isEmpty
                                  ? ref.t('nobody_due_today')
                                  : ref.t('no_customers_match_view'),
                              textAlign: TextAlign.center,
                              style: ManaType.secondary),
                        ),
                      )
                    else
                      ...visible.map((row) => _DueRow(
                            row: row,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => CollectionEntryScreen(row: row, businessId: widget.businessId)),
                            ),
                          )),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DueRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final s = _statusIcon;
    // NOT a ListTile — its leading/title/trailing layout clamps content to
    // a fixed height (~56dp), which a two-line trailing column (amount +
    // LRI) does not fit inside once text scale grows, AND its fixed-width
    // trailing slot squeezes the title's available width down as the
    // trailing text widens — both fire only at larger text scales, which
    // is why this shipped unnoticed.
    //
    // The amount is deliberately NOT beside the name in a Row anymore
    // either. Two side-by-side Flexible texts still overflowed even with
    // ellipsis on both: a long unbroken name (a single word wider than
    // its half of the row) forces width beyond what its Flexible share
    // was ever going to get, since Flexible cannot shrink a child past
    // its own minimum intrinsic content width. Stacking the amount BELOW
    // the name/village instead means neither one is ever competing for
    // horizontal room with the other — each gets the full row width to
    // itself.
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(s.icon, color: s.color),
              const SizedBox(width: ManaSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: ManaText.raw(row.customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.emphasis),
                        ),
                        if (row.penaltyEligible) ...[
                          const SizedBox(width: ManaSpacing.xs),
                          ManaStatusPill(label: ref.t('penalty'), status: ManaStatus.bad),
                        ] else if (row.gracePeriod) ...[
                          const SizedBox(width: ManaSpacing.xs),
                          ManaStatusPill(label: ref.t('grace'), status: ManaStatus.warn),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    // maxLines/overflow required, not optional: the loan
                    // number is one unbroken token with no space for the
                    // line-breaker to wrap at, so without this it forces
                    // its own width regardless of what's available and
                    // overflows the row rather than wrapping.
                    ManaText.raw('${row.village} · ${row.loanNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ManaType.note),
                    const SizedBox(height: ManaSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: ManaText.raw('LRI ${row.lineRepaymentIndex}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.note),
                        ),
                        const SizedBox(width: ManaSpacing.sm),
                        Flexible(
                          child: ManaText.raw(manaRupees(row.installmentDue),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.cardTitle),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
