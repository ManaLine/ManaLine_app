import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/idempotency.dart';
import '../../../shared/mana_location.dart';
import '../../../shared/gps_address_service.dart';
import '../../../shared/widgets/workspace_nav.dart';
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
      // Index 1 is Collections, which is this screen. The bar refuses to
      // re-navigate to the tab it is already on, so pressing it does nothing
      // rather than pushing a duplicate route.
      bottomNavigationBar: ManaWorkspaceNav(
          workspace: ManaWorkspace.owner,
          businessId: businessId,
          currentIndex: 1),
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

  /// Non-null when this form is CORRECTING an entry rather than taking a new
  /// one. The round long-presses a settled row into here.
  ///
  /// One entry per loan per day is enforced server-side, so the alternative
  /// to correcting is a second row -- which is how one payment ends up with
  /// two receipts. The window closes when the account goes to the Owner;
  /// app.amend_collection refuses after that and says so.
  final CollectionEdit? editing;

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
    this.editing,
  });

  @override
  ConsumerState<ManaCollectionForm> createState() => ManaCollectionFormState();
}

class ManaCollectionFormState extends ConsumerState<ManaCollectionForm> {
  final _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing != null) {
      // Correcting: the form opens on what was actually recorded, not on the
      // instalment. Retyping an entry to change one figure in it is how the
      // other three figures get changed by accident.
      _amount.text = '${editing.collectedAmount}';
      _amount.selection = TextSelection(
          baseOffset: 0, extentOffset: _amount.text.length);
      _modeAmounts.addAll(editing.splits);
      _payerType = editing.payerType;
      _payerName.text = editing.payerName ?? '';
      return;
    }
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
      _modeAmounts['Cash'] = due;
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
    for (final c in _modeFields.values) {
      c.dispose();
    }
    super.dispose();
  }
  // Customer unless the Agent says otherwise. Asking who paid on every single
  // collection is a decision on the overwhelmingly common case, made standing
  // at a doorstep — so the question only appears when it is answered.
  String _payerType = 'Customer';
  final _payerName = TextEditingController();

  /// What was handed over, by mode. Absent = that mode was not used.
  ///
  /// Replaces a `Mixed Payment` switch over two hardcoded fields. Without the
  /// switch every collection was written as Cash -- the splits list was
  /// literally `[PaymentSplit('Cash', _collected)]` -- so a customer paying
  /// entirely by UPI, cheque or bank transfer was recorded as having handed
  /// over notes, and there was no way at all to say otherwise for the two
  /// modes the switch did not offer. The database has carried all four since
  /// payment_mode_enum was created.
  ///
  /// Cash starts holding the instalment so the common case is still one tap.
  final Map<String, int> _modeAmounts = {};

  /// One per mode, owned by this State.
  ///
  /// Created per dialog and disposed when it returned, which disposed a
  /// controller the dialog's own exit animation was still reading -- "A
  /// TextEditingController was used after being disposed" on every second
  /// mode entered. Their lifetime is the form's.
  final Map<String, TextEditingController> _modeFields = {
    for (final m in _modes) m: TextEditingController(),
  };

  static const _modes = ['Cash', 'UPI', 'Bank Transfer', 'Cheque'];

  static const _modeKeys = {
    'Cash': 'cash',
    'UPI': 'upi',
    'Bank Transfer': 'bank_transfer',
    'Cheque': 'cheque',
  };

  String? _excessDisposition;
  bool _submitting = false;

  /// Minted once per save the person commits to, and reused by every retry of
  /// it — including NetworkErrorHandler's Retry button, which re-enters
  /// _submit(). On a
  /// dropped 2G reply that is what stops the same collection being recorded
  /// twice. Cleared after a save lands so the next one is a new action.
  String? _idempotencyKey;

  // Whole rupees (M8) — money is never a double in this app.
  int get _collected => int.tryParse(_amount.text) ?? 0;

  /// The modes actually carrying money, in a stable order.
  List<String> get _activeModes =>
      [for (final m in _modes) if ((_modeAmounts[m] ?? 0) > 0) m];

  int get _modeSum =>
      _modeAmounts.values.fold<int>(0, (sum, v) => sum + v);

  /// Typing in Collected Amount is only unambiguous while ONE mode is
  /// carrying the money -- with two, the app cannot know which one the extra
  /// rupees went into, and guessing is how a receipt ends up naming a mode
  /// nobody used. With one it rebalances silently; with more the field reads
  /// back the sum the modes state.
  bool get _amountFollowsModes => _activeModes.length > 1;

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
    // The splits ARE the collected amount now rather than a parallel figure
    // that had to be reconciled against it, so they cannot disagree -- but a
    // collection with no mode against it would be written as money from
    // nowhere.
    if (_modeSum != _collected) return false;
    // No longer a gate. The server carries an unstated surplus as an Advance
    // rather than refusing the record -- a customer standing there with cash
    // is not a validation error, and refusing does not make the money go away.
    // The choice is still offered below; it is simply not required.
    return true;
  }

  /// Enter (or clear) the amount handed over in one mode.
  ///
  /// A tap on the mode opens the box for it and Save adds it in -- the app
  /// totals the modes rather than asking the Agent to total them and then
  /// checking their arithmetic, which is what the old Mixed Payment switch
  /// did with its "Split sum must equal collected amount" warning.
  ///
  /// Clearing the box, or saving a zero, drops the mode: a mode holding zero
  /// is a line on a receipt naming a payment nobody made.
  Future<void> _editMode(String mode) async {
    final existing = _modeAmounts[mode] ?? 0;
    final controller = _modeFields[mode]!;
    controller.text = existing > 0 ? '$existing' : '';
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    final saved = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Scrolls if it does not fit -- see ow_011_day_closure.dart.
        scrollable: true,
        title: ManaText.raw(ref.t(_modeKeys[mode]!)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('amount')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: ManaText.raw(ref.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(int.tryParse(controller.text.trim()) ?? 0),
            child: ManaText.raw(ref.t('save')),
          ),
        ],
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      if (saved > 0) {
        _modeAmounts[mode] = saved;
      } else {
        _modeAmounts.remove(mode);
      }
      // The collected amount is the sum of what was handed over. It is not a
      // separate figure that has to agree with the modes -- that reconciling
      // is exactly what the Mixed switch made the Agent do at a doorstep.
      _amount.text = _modeSum > 0 ? '$_modeSum' : '';
    });
  }

  Future<void> _submit() async {
    // Minted here, on the first attempt only: a key created inside the retry
    // closure would be new every time, which is the same as having none.
    _idempotencyKey ??= manaIdempotencyKey();
    setState(() => _submitting = true);
    // Every mode that carries money, and nothing else. A zero-rupee split
    // for a mode nobody used is a line on a receipt claiming a payment that
    // did not happen.
    final splits = [
      for (final m in _activeModes)
        PaymentSplit(paymentMode: m, amount: _modeAmounts[m]!),
    ];

    final editing = widget.editing;
    if (editing != null) {
      // No idempotency key, and none needed: an amendment sets the entry to
      // an absolute figure rather than moving it by a delta, so replaying one
      // after a dropped reply lands on the same amount and the same balance.
      // A retry of a NEW collection is what needs a key -- it would otherwise
      // be a second payment.
      final amended = await NetworkErrorHandler.run(context, () {
        return ref.read(collectionModeProvider.notifier).amendCollection(
              collectionId: editing.collectionId,
              collectedAmount: _collected,
              payerType: _payerType,
              payerName:
                  _payerName.text.trim().isEmpty ? null : _payerName.text.trim(),
              paymentSplits: splits,
              excessDisposition: _excessDisposition,
              previousAmount: editing.collectedAmount,
            );
      });
      if (!mounted) return;
      setState(() => _submitting = false);
      if (amended == null) return;
      _idempotencyKey = null;
      _showReceipt(amended);
      return;
    }

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
            idempotencyKey: _idempotencyKey,
          );
      if (o == null) throw Exception('Collection could not be saved.');
      return o;
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (outcome == null) return;

    // This loan already has an entry today. Nothing was written -- the way
    // forward is to correct that entry, not to add a second one.
    if (outcome.alreadyRecorded != null) {
      await _showAlreadyRecordedDialog(outcome.alreadyRecorded!);
      return;
    }
    if (!mounted) return;
    // Landed. The next save is a new action, not a replay of this one.
    _idempotencyKey = null;

    // Where it was taken, stamped after the fact and never in the way.
    //
    // Deliberately not awaited before the receipt: a phone with no fix, no
    // permission or no signal must still show the Agent that the money
    // landed. The location is a record, not a condition -- making it one
    // would mean a collection failing because a satellite was slow.
    _stampLocation(outcome.saved!.collectionId);

    _showReceipt(outcome.saved!);
  }

  /// This loan already has an entry today, so nothing was written.
  ///
  /// The old version of this offered "Continue", which recorded a SECOND
  /// payment against the same loan -- two receipts for one collection, and a
  /// balance short by the difference. There is one entry per loan per day
  /// now; the only way forward is to correct the one that exists, and the
  /// round's long press is where that is done.
  Future<void> _showAlreadyRecordedDialog(ExistingCollection existing) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Scrolls if it does not fit -- see ow_011_day_closure.dart.
        scrollable: true,
        title: ManaText.raw(ref.t(existing.window == 'cycle'
            ? 'already_collected_this_cycle'
            : 'already_collected_today')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(
              ref
                  .t('already_collected_note')
                  .replaceAll('{by}', existing.recordedBy)
                  .replaceAll('{amount}', manaRupees(existing.collectedAmount)),
            ),
            // Inside a cycle window the entry is not necessarily today's, and
            // a message that says "today" over a Weekly loan sends the Agent
            // back tomorrow to be refused again.
            if (existing.window == 'cycle' && existing.businessDate != null) ...[
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                ref.t('recorded_on_note').replaceAll('{date}',
                    DateFormat('d MMM').format(existing.businessDate!)),
                style: ManaType.note,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: ManaText.raw(ref.t('close')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    widget.onCancel();
  }

  /// Fire and forget. Failures are swallowed ON PURPOSE, which is the one
  /// place in this file that is acceptable: the collection is already
  /// recorded, and nothing the Agent can do about a missing fix is worth
  /// interrupting them at a doorstep to say.
  void _stampLocation(String collectionId) {
    if (collectionId.isEmpty) return;
    () async {
      try {
        final fix = await ManaLocation.currentFix();
        if (!fix.hasPosition) return;
        await ref
            .read(gpsAddressServiceProvider)
            .recordCollectionLocation(collectionId: collectionId, fix: fix);
      } catch (_) {
        // See above.
      }
    }();
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
          readOnly: _amountFollowsModes,
          decoration: InputDecoration(
            labelText: ref.t('collected_amount_field'),
            helperText: _amountFollowsModes ? ref.t('added_up_from_modes_note') : null,
            helperMaxLines: 2,
          ),
          // With one mode active this figure IS that mode's amount, so it
          // follows the typing rather than sitting beside it as a second
          // number to reconcile.
          onChanged: (v) => setState(() {
            final only = _activeModes.length == 1 ? _activeModes.first : 'Cash';
            final n = int.tryParse(v) ?? 0;
            _modeAmounts
              ..removeWhere((k, _) => k != only)
              ..[only] = n;
            if (n <= 0) _modeAmounts.remove(only);
          }),
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
        ManaText.raw(ref.t('how_it_was_paid'), style: ManaType.note),
        const SizedBox(height: ManaSpacing.xs),
        // Wrap, not a Row: these are translated labels, so their width is
        // data, and four of them do not fit on one 360px line in Telugu at
        // 2.0x. A Row here would be the fifth shipped overflow.
        Wrap(
          spacing: ManaSpacing.xs,
          runSpacing: ManaSpacing.xs,
          children: [
            for (final mode in _modes)
              // ChoiceChip, and the label carries the mode's NAME only.
              //
              // An InputChip here overflowed by 55px at 2.0x in Telugu --
              // its delete/check affordance leaves less room for a scaled
              // label than a ChoiceChip does, and the amount in the label
              // then pushed it to two lines. ChoiceChip is what OW-001's
              // quick-action groups use at the same scales. The amounts read
              // below, in text that is allowed to wrap.
              ChoiceChip(
                label: ManaText.raw(ref.t(_modeKeys[mode]!),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: (_modeAmounts[mode] ?? 0) > 0,
                onSelected: (_) => _editMode(mode),
              ),
          ],
        ),
        if (_activeModes.isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(
            [
              for (final m in _activeModes)
                '${ref.t(_modeKeys[m]!)} ${manaRupees(_modeAmounts[m]!)}'
            ].join('  ·  '),
            style: ManaType.note,
          ),
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
                        _collected <= 0
                            ? ref.t('save')
                            : ref
                                .t(widget.editing != null
                                    ? 'update_amount'
                                    : 'collect_amount')
                                .replaceAll('{amount}', manaRupees(_collected)),
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
