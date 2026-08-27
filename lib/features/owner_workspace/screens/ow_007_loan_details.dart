import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/apply_penalty_sheet.dart';
import '../../../shared/agent_picker_sheet.dart';
import '../../../shared/document_viewer.dart';
import '../../../shared/translation_service.dart';
import '../state/customer_state.dart' show customerApiServiceProvider;
import '../state/loan_details_state.dart';


/// OW-007 — Loan Details. Entry: OW-004 Customer Profile (Loans tab), or
/// OW-009's day-detail Loans sub-tab. Every action stays inline on this
/// screen except Collect Payment, which routes to OW-006 pre-filled.
class LoanDetailsScreen extends ConsumerWidget {
  final String loanId;
  const LoanDetailsScreen({super.key, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(loanDetailsProvider(loanId));

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('loan_details')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw(ref.t('could_not_load_loan_note').replaceAll('{error}', '$e'),
                  textAlign: TextAlign.center),
            ),
          ),
          data: (loan) => RefreshIndicator(
            onRefresh: () => ref.read(loanDetailsProvider(loanId).notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              children: [
                _Header(loan: loan),
                const SizedBox(height: ManaSpacing.lg),
                _SummaryCard(loan: loan),
                const SizedBox(height: ManaSpacing.lg),
                _GuarantorSection(guarantor: loan.guarantor),
                const SizedBox(height: ManaSpacing.lg),
                _ActionsSection(loanId: loanId, loan: loan),
                const SizedBox(height: ManaSpacing.lg),
                _PaymentHistorySection(loan: loan),
                const SizedBox(height: ManaSpacing.lg),
                _PenaltySection(loanId: loanId, loan: loan),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final LoanDetail loan;
  const _Header({required this.loan});

  ManaStatus get _statusKind => switch (loan.status) {
        LoanStatus.active => ManaStatus.good,
        LoanStatus.gracePeriod => ManaStatus.warn,
        LoanStatus.penaltyEligible || LoanStatus.penalty => ManaStatus.bad,
        LoanStatus.closed => ManaStatus.neutral,
        LoanStatus.cancelled || LoanStatus.defaulted => ManaStatus.bad,
        LoanStatus.draft => ManaStatus.neutral,
      };

  String get _statusKey => switch (loan.status) {
        LoanStatus.draft => 'draft',
        LoanStatus.active => 'active',
        LoanStatus.gracePeriod => 'grace_period',
        LoanStatus.penaltyEligible => 'penalty_eligible',
        LoanStatus.penalty => 'penalty',
        LoanStatus.closed => 'closed',
        LoanStatus.cancelled => 'cancelled',
        LoanStatus.defaulted => 'defaulted',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(loan.loanNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ManaType.sheetTitle),
              ManaText.raw(loan.customerName,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: ManaType.secondary),
            ],
          ),
        ),
        const SizedBox(width: ManaSpacing.xs),
        Flexible(child: ManaStatusPill(label: ref.t(_statusKey), status: _statusKind)),
      ],
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  final LoanDetail loan;
  const _SummaryCard({required this.loan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          children: [
            _row(ref.t('repayment_type'), loan.repaymentType),
            _row(ref.t('installment_amount'), manaRupees(loan.installmentAmount)),
            _row(ref.t('loan_amount'), manaRupees(loan.loanAmount)),
            _row(ref.t('amount_given_locked'), manaRupees(loan.amountGiven)),
            _row(ref.t('outstanding_balance'), manaRupees(loan.outstandingBalance)),
            _row(ref.t('todays_due'), manaRupees(loan.todaysDue)),
            _row(ref.t('completed_installments'), '${loan.completedInstallments}'),
            _row(ref.t('remaining_installments'), '${loan.remainingInstallments}'),
            _row(ref.t('grace_status'), ref.t(loan.inGracePeriod ? 'in_grace_period' : 'normal')),
            _row(ref.t('penalty_status'), ref.t(loan.penaltyEligible ? 'penalty_eligible' : 'none')),
            _row(ref.t('collection_agent'), loan.collectionAgentName),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: ManaText.raw(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ManaType.note),
            ),
            const SizedBox(width: ManaSpacing.xs),
            Flexible(
              child: ManaText.raw(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: ManaType.smallStrong),
            ),
          ],
        ),
      );
}

class _GuarantorSection extends ConsumerWidget {
  final GuarantorDetail? guarantor;
  const _GuarantorSection({required this.guarantor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('guarantor'), style: ManaType.strong),
        const SizedBox(height: ManaSpacing.sm),
        // Always renders the container, even with no guarantor, so the
        // Owner can see at a glance one was never added rather than
        // wondering if the section failed to load (spec RESOLVED note).
        Card(
          child: guarantor == null
              ? Padding(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  child: ManaText.raw(ref.t('no_guarantor'), style: ManaType.secondary),
                )
              : Padding(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(guarantor!.name, style: ManaType.emphasis),
                      ManaText.raw(guarantor!.relationship, style: ManaType.note),
                      const SizedBox(height: ManaSpacing.xs),
                      ManaText.raw(guarantor!.phone, style: ManaType.small),
                      ManaText.raw(guarantor!.address, style: ManaType.small),
                      if (guarantor!.remarks != null && guarantor!.remarks!.isNotEmpty)
                        ManaText.raw(guarantor!.remarks!, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ActionsSection extends ConsumerWidget {
  final String loanId;
  final LoanDetail loan;
  const _ActionsSection({required this.loanId, required this.loan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('available_actions'), style: ManaType.strong),
        const SizedBox(height: ManaSpacing.sm),
        Wrap(
          spacing: ManaSpacing.sm,
          runSpacing: ManaSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: loan.canCollectPayment
                  ? () => context.push('/ow-006', extra: loan.loanId)
                  : null,
              icon: const Icon(Icons.point_of_sale_outlined, size: 18),
              label: ManaText.raw(ref.t('collect_payment')),
            ),
            OutlinedButton.icon(
              onPressed: loan.canTransferAgent ? () => _showTransferAgentDialog(context, ref) : null,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: ManaText.raw(ref.t('transfer_agent')),
            ),
            OutlinedButton.icon(
              onPressed: loan.canEditAllowedFields ? () => _showEditFieldsDialog(context, ref) : null,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: ManaText.raw(ref.t('edit_allowed_fields')),
            ),
            OutlinedButton.icon(
              onPressed: () => _showAddRemarkDialog(context, ref),
              icon: const Icon(Icons.comment_outlined, size: 18),
              label: ManaText.raw(ref.t('add_remarks')),
            ),
            OutlinedButton.icon(
              // BUG FIXED this pass: was onPressed: () {} — a loan has no
              // documents of its own beyond what's already on the
              // borrowing customer (customer_documents also covers
              // Customer/Loan Agreement, Guarantor Document types), so
              // this opens that same customer's Documents view rather
              // than inventing a separate loan-scoped document set.
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: ManaAppBar(title: '${loan.customerName} — ${ref.t('documents')}'),
                    body: DocumentsListView(
                      expectedTypes: const [
                        'Aadhaar',
                        'Photo',
                        'Address Proof',
                        'Customer Agreement',
                        'Loan Agreement',
                        'Guarantor Documents',
                        'Other Documents',
                      ],
                      fetchDocuments: () =>
                          ref.read(customerApiServiceProvider).fetchCustomerDocuments(customerId: loan.customerId),
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: ManaText.raw(ref.t('view_documents')),
            ),
            if (loan.canCloseLoan)
              OutlinedButton.icon(
                onPressed: () => _confirmCloseLoan(context, ref),
                icon: const Icon(Icons.lock_outline, size: 18),
                label: ManaText.raw(ref.t(loan.status == LoanStatus.defaulted ? 'close_write_off' : 'close_loan')),
              ),
            if (loan.canApplyPenalty)
              FilledButton.tonalIcon(
                onPressed: () => _showApplyPenaltyDialog(context, ref),
                icon: const Icon(Icons.report_gmailerrorred, size: 18),
                label: ManaText.raw(ref.t('apply_penalty')),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _showTransferAgentDialog(BuildContext context, WidgetRef ref) async {
    final loan = ref.read(loanDetailsProvider(loanId)).valueOrNull;
    if (loan == null) return;

    // A real agent from this business, not the string 'stub-agent-id' that
    // used to go straight into the UPDATE.
    final membershipId = await showAgentPickerSheet(
      context,
      ref,
      businessId: loan.businessId,
      currentMembershipId: loan.collectionAgentId,
    );
    if (membershipId == null || !context.mounted) return;

    // Gated on the call succeeding. This announced the transfer regardless,
    // so a write that could never have worked still read as done.
    final moved = await NetworkErrorHandler.run(context, () async {
      await ref.read(loanDetailsProvider(loanId).notifier).transferAgent(membershipId);
      return true;
    });
    if (moved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('agent_transferred_note'))),
      );
    }
  }

  Future<void> _showEditFieldsDialog(BuildContext context, WidgetRef ref) async {
    final remarks = TextEditingController(text: loan.remarks ?? '');
    final futureInfo = TextEditingController(text: loan.futureEffectiveInformation ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Scrolls if it does not fit -- see ow_011_day_closure.dart.
        scrollable: true,
        title: ManaText.raw(ref.t('edit_allowed_fields')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ManaText.raw(
              ref.t('edit_allowed_fields_note'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(controller: remarks, decoration: InputDecoration(labelText: ref.t('remarks'))),
            const SizedBox(height: ManaSpacing.md),
            TextField(controller: futureInfo, decoration: InputDecoration(labelText: ref.t('future_effective_information'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: ManaText.raw(ref.t('save'))),
        ],
      ),
    );
    if (result != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(loanDetailsProvider(loanId).notifier).editAllowedFields(
            remarks: remarks.text.trim(),
            futureEffectiveInformation: futureInfo.text.trim(),
          );
    });
  }

  Future<void> _showAddRemarkDialog(BuildContext context, WidgetRef ref) async {
    final remark = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: ManaText.raw(ref.t('add_remark')),
        content: TextField(controller: remark, decoration: InputDecoration(hintText: ref.t('append_only'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: ManaText.raw(ref.t('save'))),
        ],
      ),
    );
    if (result != true || remark.text.trim().isEmpty || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(loanDetailsProvider(loanId).notifier).addRemark(remark.text.trim());
    });
  }

  Future<void> _confirmCloseLoan(BuildContext context, WidgetRef ref) async {
    final isWriteOff = loan.status == LoanStatus.defaulted;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: ManaText.raw(ref.t(isWriteOff ? 'confirm_write_off' : 'confirm_close_loan')),
        content: ManaText.raw(
          ref
              .t(isWriteOff ? 'write_off_note' : 'close_loan_confirm_note')
              .replaceAll('{amount}', manaRupees(loan.outstandingBalance)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: ManaText.raw(ref.t('confirm'))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(loanDetailsProvider(loanId).notifier).closeLoan(writeOffRemaining: isWriteOff);
    });
    if (result == null || !context.mounted) return;
    // Only a genuine payoff recognises penalty income — the server decides
    // that from the balance it saw before the write, so report what it
    // actually did rather than what the button was labelled.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ManaText.raw(result.recognisedPenalty
            ? ref.t('penalty_recognised_note').replaceAll('{amount}', manaRupees(result.penaltyRecognised))
            : ref.t(result.writtenOff ? 'written_off_note' : 'loan_closed_note')),
      ),
    );
  }

  /// The shared sheet, same as the round's Penalty tag opens.
  ///
  /// This asked for a penalty OPTION -- Flat Amount, % of Overdue Installment,
  /// % of Remaining Balance -- before it would take a figure. Nobody decides a
  /// penalty that way, all three ended in a rupee amount, and the server
  /// defaults the column now. One number, one sheet, one place it lives.
  Future<void> _showApplyPenaltyDialog(BuildContext context, WidgetRef ref) async {
    final loan = ref.read(loanDetailsProvider(loanId)).valueOrNull;
    if (loan == null) return;
    final applied = await showApplyPenaltySheet(
      context,
      ref,
      loanId: loanId,
      customerName: loan.customerName,
      outstandingBalance: loan.outstandingBalance,
    );
    if (applied) ref.read(loanDetailsProvider(loanId).notifier).refresh();
  }
}

class _PaymentHistorySection extends ConsumerWidget {
  final LoanDetail loan;
  const _PaymentHistorySection({required this.loan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('payment_history'), style: ManaType.strong),
        const SizedBox(height: ManaSpacing.sm),
        if (loan.paymentHistory.isEmpty)
          ManaText.raw(ref.t('no_payments_yet'), style: ManaType.secondary)
        else
          ...loan.paymentHistory.map((p) => Card(
                child: ListTile(
                  leading: Icon(Icons.receipt_long_outlined, color: ManaColors.brand),
                  title: ManaText.raw(manaRupees(p.amount)),
                  subtitle: ManaText.raw('${p.paymentMode} · ${p.collector} · #${p.receiptNumber}'),
                  trailing: ManaText.raw(DateFormat('d MMM').format(p.businessDate),
                      style: TextStyle(fontSize: 16, color: ManaColors.textSecondary)),
                ),
              )),
      ],
    );
  }
}

class _PenaltySection extends ConsumerWidget {
  final String loanId;
  final LoanDetail loan;
  const _PenaltySection({required this.loanId, required this.loan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loan.penaltyEntries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('penalty_entries'), style: ManaType.strong),
        const SizedBox(height: ManaSpacing.sm),
        // Not a ListTile. Its trailing slot takes the button's full natural
        // width before the title gets any, so the penalty amount was the part
        // that got squeezed -- it overflowed from 1.3x, and the translated
        // "Waive / Reduce" label is wider still in every language other than
        // English.
        //
        // The action now sits on its own line under the amount. It is the one
        // control here that rewrites a charge on somebody's loan, so it can
        // have the width, and the amount it applies to never has to shrink to
        // make room for it.
        ...loan.penaltyEntries.map((p) => Card(
              child: Padding(
                padding: const EdgeInsets.all(ManaSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          p.isWaivedOrReduced
                              ? Icons.remove_circle_outline
                              : Icons.report_gmailerrorred,
                          color: p.isWaivedOrReduced
                              ? ManaColors.textSecondary
                              : ManaColors.statusBad,
                        ),
                        const SizedBox(width: ManaSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ManaText.raw(
                                  '${manaRupees(p.penaltyAmount)} · ${p.penaltyOption}'),
                              ManaText.raw(
                                '${DateFormat('d MMM yyyy').format(p.appliedDate)}${p.isWaivedOrReduced ? ' · ${ref.t('waived_reduced')}' : ''}',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!p.isWaivedOrReduced && loan.canWaivePenalty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _showWaiveDialog(context, ref, p),
                          child: ManaText.raw(ref.t('waive_reduce')),
                        ),
                      ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Future<void> _showWaiveDialog(BuildContext context, WidgetRef ref, PenaltyEntry entry) async {
    final reduced = TextEditingController();
    bool waiveFully = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          // scrollable: the note, two option tiles and an amount field do not
          // fit AlertDialog's bounded height from 1.3x, and it does not scroll
          // them unless told to. What went under the fold was the reduced
          // amount field -- the number that decides how much of a penalty on
          // somebody's loan is actually cancelled.
          scrollable: true,
          title: ManaText.raw(ref.t('waive_reduce_penalty')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(
                ref.t('waive_note'),
                style: ManaType.note,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  waiveFully ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: waiveFully ? ManaColors.statusGood : ManaColors.textSecondary,
                ),
                title: ManaText.raw(ref.t('waive_fully')),
                onTap: () => setState(() => waiveFully = true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  !waiveFully ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: !waiveFully ? ManaColors.statusGood : ManaColors.textSecondary,
                ),
                title: ManaText.raw(ref.t('reduce_to_amount')),
                onTap: () => setState(() => waiveFully = false),
              ),
              if (!waiveFully)
                TextField(
                  controller: reduced,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: ref.t('new_penalty_amount')),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: ManaText.raw(ref.t('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: ManaText.raw(ref.t('confirm'))),
          ],
        ),
      ),
    );
    if (result != true || !context.mounted) return;
    final reversed = await NetworkErrorHandler.run(context, () async {
      return ref.read(loanDetailsProvider(loanId).notifier).waiveOrReducePenalty(
            penaltyEntryId: entry.penaltyEntryId,
            waive: waiveFully,
            reducedAmount: waiveFully ? null : int.tryParse(reduced.text.trim()),
          );
    });
    if (reversed != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('reversed_off_balance_note').replaceAll('{amount}', '$reversed'))),
      );
    }
  }
}
