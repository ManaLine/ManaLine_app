import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_centered_scroll.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/customer_loans_state.dart' show CustomerLoanSummary;
import '../state/online_payment_state.dart';

final _moneyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('d MMM yyyy, h:mm a');

/// CW-005 — Make A Payment. Loan selection is mandatory before payment
/// entry, always — there is no "Pay Any Loan" free-entry path anywhere
/// on this screen. Entered with a loan pre-selected from CW-004's Loan
/// Detail View, or from CW-001 → Select Business → Select Loan.
///
/// Reuses CW-004's own CustomerLoanSummary (it already carries
/// outstandingBalance, principalAmount, loanNumber — everything this
/// screen needs) rather than a parallel local type, since that chat's
/// delivered shape matches. If master chat finds CW-004's shape has
/// since diverged, this constructor param is the single place to
/// remap.
class MakeAPaymentScreen extends ConsumerStatefulWidget {
  final String loanId;

  /// Optional snapshot handed off from CW-004/CW-001 so the loan
  /// summary + Outstanding Balance can render immediately while a
  /// fresh detail fetch would otherwise be needed — same
  /// fallbackSnapshot pattern already established at IW-004.
  final CustomerLoanSummary? loanSnapshot;

  const MakeAPaymentScreen({super.key, required this.loanId, this.loanSnapshot});

  @override
  ConsumerState<MakeAPaymentScreen> createState() => _MakeAPaymentScreenState();
}

class _MakeAPaymentScreenState extends ConsumerState<MakeAPaymentScreen> {
  @override
  void initState() {
    super.initState();
    // Guard: loanId should always be present given the navigation
    // contract (CW-004/CW-001 always pass one), but if this screen is
    // ever entered without one, redirect back rather than rendering an
    // amount field with no loan context — per CW-005's own PERMISSION
    // ("no Pay Any Loan free entry").
    if (widget.loanId.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/cw-004');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loanId.trim().isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final state = ref.watch(onlinePaymentProvider);

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('make_a_payment')),
      body: SafeArea(
        child: switch (state.phase) {
          PaymentFlowPhase.entry || PaymentFlowPhase.upiInProgress => _PaymentEntryForm(
              loanId: widget.loanId,
              loanSnapshot: widget.loanSnapshot,
              upiInProgress: state.phase == PaymentFlowPhase.upiInProgress,
            ),
          PaymentFlowPhase.submitted => _SubmittedState(state: state, loanId: widget.loanId),
          PaymentFlowPhase.confirmed => _ConfirmedState(state: state, loanId: widget.loanId),
          PaymentFlowPhase.disputed => _DisputedState(state: state, loanId: widget.loanId),
        },
      ),
    );
  }
}

// --- S1 Payment Entry / S2 UPI In Progress ----------------------------------

class _PaymentEntryForm extends ConsumerStatefulWidget {
  final String loanId;
  final CustomerLoanSummary? loanSnapshot;
  final bool upiInProgress;

  const _PaymentEntryForm({required this.loanId, this.loanSnapshot, required this.upiInProgress});

  @override
  ConsumerState<_PaymentEntryForm> createState() => _PaymentEntryFormState();
}

class _PaymentEntryFormState extends ConsumerState<_PaymentEntryForm> {
  final _amountController = TextEditingController();
  String? _amountError;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int? get _amount => int.tryParse(_amountController.text.trim());

  bool get _canProceed {
    final a = _amount;
    return a != null && a > 0;
  }

  void _validate() {
    setState(() {
      final a = _amount;
      if (_amountController.text.trim().isEmpty) {
        _amountError = null;
      } else if (a == null || a <= 0) {
        _amountError = ref.t('enter_a_valid_amount');
      } else {
        _amountError = null;
      }
    });
  }

  /// S1 → S2 → (device UPI app) → back into the app → submit. This
  /// screen doesn't integrate a real UPI SDK (no such dependency/
  /// endpoint named anywhere in scope) — "Select UPI App / Pay via
  /// UPI" is represented as a single confirm step that hands off to
  /// PaymentFlowPhase.upiInProgress and then straight to submission,
  /// same stub-fidelity as every other hardware/external-app
  /// integration point elsewhere in this app (e.g. Live Photo at
  /// OW-005). Flagged for master chat if a real UPI intent/deep-link
  /// needs wiring later.
  Future<void> _payViaUpi() async {
    final amount = _amount;
    if (amount == null) return;
    ref.read(onlinePaymentProvider.notifier).beginUpiHandoff();

    final ok = await NetworkErrorHandler.run(context, () async {
      final r = await ref.read(onlinePaymentProvider.notifier).submit(loanId: widget.loanId, amount: amount);
      if (!r) throw Exception('Could not submit payment');
      return r;
    });
    if (ok == null) {
      // failed — error already shown; return to entry rather than
      // leaving the UI stuck mid-handoff.
      ref.read(onlinePaymentProvider.notifier).returnFromUpiApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.loanSnapshot;
    final submitting = ref.watch(onlinePaymentProvider).submitting;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(ref.t('selected_loan'), style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: ManaSpacing.xs),
                // Display, locked — per CW-005's own PAYMENT ENTRY
                // section, the loan is never editable/re-selectable
                // from within this screen.
                ManaText.raw(
                  snapshot?.loanNumber ?? widget.loanId,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: ManaSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: ManaText.raw(ref.t('outstanding_balance'))),
                    const SizedBox(width: ManaSpacing.sm),
                    Flexible(
                      child: ManaText.raw(
                        _moneyFormat.format(snapshot?.outstandingBalance ?? 0),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: ManaTypography.amount(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(ref.t('payment_amount'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _amountController,
          enabled: !widget.upiInProgress && !submitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '₹ ',
            labelText: ref.t('payment_amount_field'),
            errorText: _amountError,
          ),
          onChanged: (_) => _validate(),
        ),
        const SizedBox(height: ManaSpacing.xl),
        if (widget.upiInProgress) ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.lg),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: ManaSpacing.md),
                  ManaText.raw(ref.t('waiting_for_upi_app'), style: ManaType.secondary),
                ],
              ),
            ),
          ),
        ] else
          ElevatedButton(
            onPressed: (_canProceed && !submitting) ? _payViaUpi : null,
            child: submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : ManaText.raw(ref.t('pay_via_upi')),
          ),
      ],
    );
  }
}

// --- S3 Submitted ------------------------------------------------------------

class _SubmittedState extends ConsumerWidget {
  final OnlinePaymentState state;
  final String loanId;
  const _SubmittedState({required this.state, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = state.lastSubmission;
    // Scrolls rather than clips. Submitted overflowed the bottom from 1.3x
    // and Disputed at 2.0x -- up to 679px -- and what goes off the bottom of
    // these three is the receipt detail and the action beneath it, on the
    // screen a customer is looking at after their money has already left
    // their UPI app. Confirmed is fixed alongside them: it is built by the
    // same shape and would have broken the moment a refetch reached it.
    return ManaCenteredScroll(
      padding: const EdgeInsets.all(ManaSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top, size: 56, color: ManaColors.statusWarn),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('payment_submitted'), style: ManaType.sheetTitle),
            const SizedBox(height: ManaSpacing.sm),
            if (record != null)
              ManaText.raw(
                ref
                    .t('amount_submitted_note')
                    .replaceAll('{amount}', _moneyFormat.format(record.amount))
                    .replaceAll('{date}', _dateFmt.format(record.submittedAt.toLocal())),
                textAlign: TextAlign.center,
                style: ManaType.secondary,
              ),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              ref.t('submitted_status_note'),
              textAlign: TextAlign.center,
              style: ManaType.secondary,
            ),
            const SizedBox(height: ManaSpacing.lg),
            OutlinedButton(
              onPressed: () => ref.read(onlinePaymentProvider.notifier).refreshStatus(loanId: loanId),
              child: ManaText.raw(ref.t('check_status')),
            ),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(
              // Returns to CW-004 Loan Detail View (Pending Online
              // Payments) per CW-005's own NAVIGATION.
              onPressed: () => context.canPop() ? context.pop() : context.go('/cw-004'),
              child: ManaText.raw(ref.t('back_to_loan_detail')),
            ),
          ],
        ),
      ),
    );
  }
}

// --- S4 Confirmed --------------------------------------------------------------

class _ConfirmedState extends ConsumerWidget {
  final OnlinePaymentState state;
  final String loanId;
  const _ConfirmedState({required this.state, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = state.lastSubmission;
    // Scrolls rather than clips. Submitted overflowed the bottom from 1.3x
    // and Disputed at 2.0x -- up to 679px -- and what goes off the bottom of
    // these three is the receipt detail and the action beneath it, on the
    // screen a customer is looking at after their money has already left
    // their UPI app. Confirmed is fixed alongside them: it is built by the
    // same shape and would have broken the moment a refetch reached it.
    return ManaCenteredScroll(
      padding: const EdgeInsets.all(ManaSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 56, color: ManaColors.statusGood),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('payment_confirmed'), style: ManaType.sheetTitle),
            const SizedBox(height: ManaSpacing.sm),
            if (record != null)
              ManaText.raw(
                ref.t('posted_to_loan_note').replaceAll('{amount}', _moneyFormat.format(record.amount)),
                textAlign: TextAlign.center,
                style: ManaType.secondary,
              ),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton(
              onPressed: () => context.go('/cw-004'),
              child: ManaText.raw(ref.t('view_loan')),
            ),
          ],
        ),
      ),
    );
  }
}

// --- S5 Disputed --------------------------------------------------------------

class _DisputedState extends ConsumerWidget {
  final OnlinePaymentState state;
  final String loanId;
  const _DisputedState({required this.state, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Scrolls rather than clips. Submitted overflowed the bottom from 1.3x
    // and Disputed at 2.0x -- up to 679px -- and what goes off the bottom of
    // these three is the receipt detail and the action beneath it, on the
    // screen a customer is looking at after their money has already left
    // their UPI app. Confirmed is fixed alongside them: it is built by the
    // same shape and would have broken the moment a refetch reached it.
    return ManaCenteredScroll(
      padding: const EdgeInsets.all(ManaSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: ManaColors.statusBad),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('payment_could_not_be_confirmed'),
                style: ManaType.sheetTitle),
            const SizedBox(height: ManaSpacing.sm),
            // No Customer-side retry/resubmit action exists for a
            // Disputed payment per CW-005's own rule — stays open
            // until resolved manually, outside the app.
            ManaText.raw(
              ref.t('contact_business_note'),
              textAlign: TextAlign.center,
              style: ManaType.secondary,
            ),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton(
              onPressed: () => context.go('/cw-004'),
              child: ManaText.raw(ref.t('back_to_my_loans')),
            ),
          ],
        ),
      ),
    );
  }
}
