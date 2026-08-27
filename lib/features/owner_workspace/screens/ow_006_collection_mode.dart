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
    );
  }
}

// --- Collection Entry -------------------------------------------------
//
// The screen that used to sit here is gone. It restated what the round row
// already showed -- name, loan number, installment due, outstanding, LRI,
// grace, penalty -- and then offered three buttons before any money could be
// entered. Two screen transitions and three taps to record a number the app
// already knew, forty times a round.
//
// These three forms survive because the work in them is real: Full / Partial /
// Excess is classified server-side from the amount, a split has to add up, and
// somebody other than the customer often hands the money over. They are opened
// inline from the row now -- see ManaDueRow.

class ManaCollectionForm extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final String businessId;
  final VoidCallback onCancel;

  /// A collection landed. The form no longer knows what should happen next --
  /// it used to pop two routes, which only worked because it lived on a screen
  /// of its own. Inline in the round, the row closes and the round reloads.
  final VoidCallback? onRecorded;

  const ManaCollectionForm({
    super.key,
    required this.row,
    required this.businessId,
    required this.onCancel,
    this.onRecorded,
  });

  @override
  ConsumerState<ManaCollectionForm> createState() => ManaCollectionFormState();
}

class ManaCollectionFormState extends ConsumerState<ManaCollectionForm> {
  final _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Already written in, at today's due.
    //
    // The Agent used to type this figure on every collection, having just read
    // it off the row above. On a full payment -- which is most of them -- there
    // is now nothing to enter at all. Selected rather than merely filled, so a
    // customer paying something else can overwrite it without first clearing
    // it one digit at a time.
    // The instalment, matching what the row shows.
    //
    // This read installmentDue -- the whole arrears -- so the field opened on
    // Rs 5,30,000 and the button read "Collect Rs 5,30,000" under a row saying
    // Rs 30,000. Two figures for one action, on the screen where a wrong one
    // becomes a receipt.
    final due = widget.row.installmentAmount;
    if (due > 0) {
      _amount.text = '$due';
      _amount.selection = TextSelection(baseOffset: 0, extentOffset: '$due'.length);
    }
  }

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _amount.dispose();
    _payerName.dispose();
    _cashAmount.dispose();
    _upiAmount.dispose();
    super.dispose();
  }
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

  /// The same rule the server applies, against the same number.
  ///
  /// This compared the amount to installmentDue -- the ARREARS -- while
  /// record_collection compared it to one instalment. Two denominators for one
  /// classification: the pill lied on every loan in arrears, and the excess
  /// question never appeared where the server demanded it, so every amount
  /// above one instalment came back "Something went wrong".
  ///
  /// Both now measure against what is OWED. The balance already carries any
  /// penalty, because applying one adds it there.
  String get _resultType {
    final owed = widget.row.outstandingBalance;
    if (_collected > owed) return 'Excess';
    if (_collected < owed) return 'Partial';
    return 'Full';
  }

  bool get _canSubmit {
    if (_collected <= 0) return false;
    if (_mixed && (_splitSum - _collected) != 0) return false;
    // No longer a gate. The server carries an unstated surplus as an Advance
    // rather than refusing the record -- a customer standing there with cash
    // is not a validation error, and refusing does not make the money go away.
    // The choice is still offered below; it is simply not required.
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
    _showReceipt(outcome.saved!);
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
      if (!mounted) return;
      setState(() => _confirmDuplicate = false); // close — nothing recorded
    }
  }

  /// The receipt, then back to the round.
  ///
  /// Receipt number, what it was classified as, and the balance the customer
  /// is left with -- the three things the Agent reads back at the door.
  void _showReceipt(CollectionResult result) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        // Scrolls if it does not fit -- see ow_011_day_closure.dart.
        scrollable: true,
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
              // Closing the row and reloading the round is the caller's to
              // decide. Popping a route from here is what broke the moment
              // this form stopped being a screen.
              widget.onRecorded?.call();
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
            // isExpanded: a DropdownButton sizes to its widest item and
            // overflows rather than shrinking -- measured at 1.0x on OW-002.
            isExpanded: true,
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
              // The button carries the amount.
              //
              // This is the instant a wrong figure becomes real money, and a
              // button that says "Save" puts the number somewhere the thumb is
              // not. It reads back what is about to be recorded, and changes
              // as the field is edited.
              child: ElevatedButton(
                onPressed: (_canSubmit && !_submitting) ? _submit : null,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : ManaText.raw(
                        _collected > 0
                            ? ref.t('collect_amount').replaceAll('{amount}', manaRupees(_collected))
                            : ref.t('save'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Action B: No Collection ------------------------------------------

class ManaNoCollectionForm extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final VoidCallback onCancel;

  /// The visit was recorded. Inline in the round there is no screen to pop --
  /// see onRecorded on ManaCollectionForm.
  final VoidCallback? onRecorded;

  const ManaNoCollectionForm(
      {super.key, required this.row, required this.onCancel, this.onRecorded});

  @override
  ConsumerState<ManaNoCollectionForm> createState() => ManaNoCollectionFormState();
}

class ManaNoCollectionFormState extends ConsumerState<ManaNoCollectionForm> {
  String? _reason;
  bool _submitting = false;

  /// EVERY value of no_collection_reason_enum, spelled as the database
  /// spells it, because this string is the wire value.
  ///
  /// It used to be a list somebody wrote by hand -- Customer Not Available,
  /// Customer Refused, Requested Later Visit, Other -- and only the last of
  /// those is a real enum value. Saving a visit failed with
  ///
  ///   invalid input value for enum no_collection_reason_enum: "Customer Refused"
  ///
  /// on three choices out of four. The feature worked only if the Agent
  /// happened to pick the bottom of the list.
  ///
  /// Regenerate with:
  ///   select enumlabel from pg_enum e join pg_type t on t.oid=e.enumtypid
  ///   where t.typname='no_collection_reason_enum' order by e.enumsortorder;
  ///
  /// no_collection_reason_guard_test.dart holds the same list and fails if
  /// this one drifts from it again.
  static const _reasons = [
    'Customer Not Home',
    'House Locked',
    'Customer Out Of Village',
    'Requested Extension',
    'Medical Emergency',
    'Festival',
    'Natural Disaster',
    'Phone Call Not Answered',
    'Shifted Village',
    'Refused Payment',
    'Other',
  ];

  /// Label keys. The VALUE above goes to the server; this is only what the
  /// Agent reads.
  static const _reasonKeys = {
    'Customer Not Home': 'customer_not_home',
    'House Locked': 'house_locked',
    'Customer Out Of Village': 'customer_out_of_village',
    'Requested Extension': 'requested_extension',
    'Medical Emergency': 'medical_emergency',
    'Festival': 'festival',
    'Natural Disaster': 'natural_disaster',
    'Phone Call Not Answered': 'phone_call_not_answered',
    'Shifted Village': 'shifted_village',
    'Refused Payment': 'refused_payment',
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
    // NOT Navigator.pop. These forms used to sit on the collection entry
    // screen, so popping returned to the round. Inline in the row, the
    // nearest route IS the round -- popping threw the Agent out of it
    // mid-visit, back to the dashboard.
    if (ok == true && mounted) widget.onRecorded?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          // isExpanded: a DropdownButton sizes to its widest item and
          // overflows rather than shrinking -- measured at 1.0x on OW-002.
          isExpanded: true,
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

class ManaExtensionForm extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final VoidCallback onCancel;

  /// The extension was answered. Same reasoning as the other two forms.
  final VoidCallback? onRecorded;

  const ManaExtensionForm(
      {super.key, required this.row, required this.onCancel, this.onRecorded});

  @override
  ConsumerState<ManaExtensionForm> createState() => ManaExtensionFormState();
}

class ManaExtensionFormState extends ConsumerState<ManaExtensionForm> {
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
      widget.onRecorded?.call();
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
