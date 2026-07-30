import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/document_viewer.dart';
import '../state/customer_state.dart' show customerApiServiceProvider;
import '../state/loan_details_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

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
      appBar: AppBar(title: const ManaText('loan details')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw('Could not load loan.\n$e', textAlign: TextAlign.center),
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

class _Header extends StatelessWidget {
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

  String get _statusLabel => switch (loan.status) {
        LoanStatus.draft => 'Draft',
        LoanStatus.active => 'Active',
        LoanStatus.gracePeriod => 'Grace Period',
        LoanStatus.penaltyEligible => 'Penalty Eligible',
        LoanStatus.penalty => 'Penalty',
        LoanStatus.closed => 'Closed',
        LoanStatus.cancelled => 'Cancelled',
        LoanStatus.defaulted => 'Defaulted',
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(loan.loanNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ManaText.raw(loan.customerName, style: const TextStyle(color: ManaColors.textSecondary)),
            ],
          ),
        ),
        ManaStatusPill(label: _statusLabel, status: _statusKind),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final LoanDetail loan;
  const _SummaryCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          children: [
            _row('Repayment Type', loan.repaymentType),
            _row('Installment Amount', _currency.format(loan.installmentAmount)),
            _row('Loan Amount', _currency.format(loan.loanAmount)),
            _row('Amount Given (locked)', _currency.format(loan.amountGiven)),
            _row('Outstanding Balance', _currency.format(loan.outstandingBalance)),
            _row("Today's Due", _currency.format(loan.todaysDue)),
            _row('Completed Installments', '${loan.completedInstallments}'),
            _row('Remaining Installments', '${loan.remainingInstallments}'),
            _row('Grace Status', loan.inGracePeriod ? 'In Grace Period' : 'Normal'),
            _row('Penalty Status', loan.penaltyEligible ? 'Penalty Eligible' : 'None'),
            _row('Collection Agent', loan.collectionAgentName),
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

class _GuarantorSection extends StatelessWidget {
  final GuarantorDetail? guarantor;
  const _GuarantorSection({required this.guarantor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ManaText('guarantor', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        // Always renders the container, even with no guarantor, so the
        // Owner can see at a glance one was never added rather than
        // wondering if the section failed to load (spec RESOLVED note).
        Card(
          child: guarantor == null
              ? const Padding(
                  padding: EdgeInsets.all(ManaSpacing.md),
                  child: ManaText.raw('No Guarantor', style: TextStyle(color: ManaColors.textSecondary)),
                )
              : Padding(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(guarantor!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ManaText.raw(guarantor!.relationship, style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
                      const SizedBox(height: ManaSpacing.xs),
                      ManaText.raw(guarantor!.phone, style: const TextStyle(fontSize: 12)),
                      ManaText.raw(guarantor!.address, style: const TextStyle(fontSize: 12)),
                      if (guarantor!.remarks != null && guarantor!.remarks!.isNotEmpty)
                        ManaText.raw(guarantor!.remarks!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
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
        const ManaText('available actions', style: TextStyle(fontWeight: FontWeight.bold)),
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
              label: const ManaText('collect payment'),
            ),
            OutlinedButton.icon(
              onPressed: loan.canTransferAgent ? () => _showTransferAgentDialog(context, ref) : null,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const ManaText('transfer agent'),
            ),
            OutlinedButton.icon(
              onPressed: loan.canEditAllowedFields ? () => _showEditFieldsDialog(context, ref) : null,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const ManaText('edit allowed fields'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showAddRemarkDialog(context, ref),
              icon: const Icon(Icons.comment_outlined, size: 18),
              label: const ManaText('add remarks'),
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
                    appBar: AppBar(title: ManaText.raw('${loan.customerName} — documents')),
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
              label: const ManaText('view documents'),
            ),
            if (loan.canCloseLoan)
              OutlinedButton.icon(
                onPressed: () => _confirmCloseLoan(context, ref),
                icon: const Icon(Icons.lock_outline, size: 18),
                label: ManaText(loan.status == LoanStatus.defaulted ? 'close (write-off)' : 'close loan'),
              ),
            if (loan.canApplyPenalty)
              FilledButton.tonalIcon(
                onPressed: () => _showApplyPenaltyDialog(context, ref),
                icon: const Icon(Icons.report_gmailerrorred, size: 18),
                label: const ManaText('apply penalty'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _showTransferAgentDialog(BuildContext context, WidgetRef ref) async {
    // Stub agent picker — real build reuses OW-002's agent list/search.
    // RESOLVED (locked): simple action, no confirmation/review screen.
    await NetworkErrorHandler.run(context, () async {
      return ref.read(loanDetailsProvider(loanId).notifier).transferAgent('stub-agent-id');
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent transferred — new agent notified.')),
      );
    }
  }

  Future<void> _showEditFieldsDialog(BuildContext context, WidgetRef ref) async {
    final remarks = TextEditingController(text: loan.remarks ?? '');
    final futureInfo = TextEditingController(text: loan.futureEffectiveInformation ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ManaText('edit allowed fields'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ManaText.raw(
              'Owner may edit: Collection Agent, Remarks, Future Effective '
              'Information only. Loan Amount, Amount Given, Interest, '
              'Processing Fee, Historical Collections, and Business Date are '
              'permanently locked (BR-016/169).',
              style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(controller: remarks, decoration: const InputDecoration(labelText: 'Remarks')),
            const SizedBox(height: ManaSpacing.md),
            TextField(controller: futureInfo, decoration: const InputDecoration(labelText: 'Future Effective Information')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const ManaText('save')),
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
        title: const ManaText('add remark'),
        content: TextField(controller: remark, decoration: const InputDecoration(hintText: 'Append-only')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const ManaText('save')),
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
        title: ManaText(isWriteOff ? 'confirm write-off' : 'confirm close loan'),
        content: ManaText.raw(
          isWriteOff
              ? 'This closes a Defaulted loan and writes off the remaining balance of '
                  '${_currency.format(loan.outstandingBalance)}. Owner-only action.'
              : 'Close this loan? Outstanding balance is ${_currency.format(loan.outstandingBalance)}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const ManaText('confirm')),
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
        content: Text(result.recognisedPenalty
            ? 'Loan closed. ${_currency.format(result.penaltyRecognised)} penalty recorded as collected today.'
            : result.writtenOff
                ? 'Loan written off. No penalty recorded as collected.'
                : 'Loan closed.'),
      ),
    );
  }

  Future<void> _showApplyPenaltyDialog(BuildContext context, WidgetRef ref) async {
    String option = 'Flat Amount';
    final amount = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const ManaText('apply penalty'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: option,
                decoration: const InputDecoration(labelText: 'Penalty Option'),
                items: const [
                  DropdownMenuItem(value: 'Flat Amount', child: Text('Flat Amount')),
                  DropdownMenuItem(value: '% of Overdue Installment', child: Text('% of Overdue Installment')),
                  DropdownMenuItem(value: '% of Remaining Balance', child: Text('% of Remaining Balance')),
                ],
                onChanged: (v) => setState(() => option = v ?? 'Flat Amount'),
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Penalty Amount *'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const ManaText('save')),
          ],
        ),
      ),
    );
    if (result != true) return;
    final amt = double.tryParse(amount.text.trim());
    if (amt == null || amt <= 0 || !context.mounted) return;
    // Gate the confirmation on the call actually succeeding — the RPC can
    // legitimately reject (Closed loan, missing can_apply_penalty), and
    // NetworkErrorHandler returns null with the server's reason already
    // shown in that case.
    final applied = await NetworkErrorHandler.run(context, () async {
      await ref.read(loanDetailsProvider(loanId).notifier).applyPenalty(penaltyOption: option, penaltyAmount: amt);
      return true;
    });
    if (applied == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Penalty applied — customer notified.')),
      );
    }
  }
}

class _PaymentHistorySection extends StatelessWidget {
  final LoanDetail loan;
  const _PaymentHistorySection({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ManaText('payment history', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        if (loan.paymentHistory.isEmpty)
          const ManaText.raw('No payments yet.', style: TextStyle(color: ManaColors.textSecondary))
        else
          ...loan.paymentHistory.map((p) => Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined, color: ManaColors.brass),
                  title: ManaText.raw(_currency.format(p.amount)),
                  subtitle: ManaText.raw('${p.paymentMode} · ${p.collector} · #${p.receiptNumber}'),
                  trailing: ManaText.raw(DateFormat('d MMM').format(p.businessDate),
                      style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
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
        const ManaText('penalty entries', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        ...loan.penaltyEntries.map((p) => Card(
              child: ListTile(
                leading: Icon(
                  p.isWaivedOrReduced ? Icons.remove_circle_outline : Icons.report_gmailerrorred,
                  color: p.isWaivedOrReduced ? ManaColors.textSecondary : ManaColors.statusBad,
                ),
                title: ManaText.raw('${_currency.format(p.penaltyAmount)} · ${p.penaltyOption}'),
                subtitle: ManaText.raw(
                  '${DateFormat('d MMM yyyy').format(p.appliedDate)}${p.isWaivedOrReduced ? ' · Waived/Reduced' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: (!p.isWaivedOrReduced && loan.canWaivePenalty)
                    ? TextButton(
                        onPressed: () => _showWaiveDialog(context, ref, p),
                        child: const ManaText('waive/reduce'),
                      )
                    : null,
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
          title: const ManaText('waive / reduce penalty'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ManaText.raw(
                'Owner-only action — a higher-trust concession than applying '
                'the penalty in the first place.',
                style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  waiveFully ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: waiveFully ? ManaColors.statusGood : ManaColors.textSecondary,
                ),
                title: const ManaText('waive fully'),
                onTap: () => setState(() => waiveFully = true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  !waiveFully ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: !waiveFully ? ManaColors.statusGood : ManaColors.textSecondary,
                ),
                title: const ManaText('reduce to amount'),
                onTap: () => setState(() => waiveFully = false),
              ),
              if (!waiveFully)
                TextField(
                  controller: reduced,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'New Penalty Amount'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const ManaText('confirm')),
          ],
        ),
      ),
    );
    if (result != true || !context.mounted) return;
    final reversed = await NetworkErrorHandler.run(context, () async {
      return ref.read(loanDetailsProvider(loanId).notifier).waiveOrReducePenalty(
            penaltyEntryId: entry.penaltyEntryId,
            waive: waiveFully,
            reducedAmount: waiveFully ? null : double.tryParse(reduced.text.trim()),
          );
    });
    if (reversed != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('₹${reversed.toStringAsFixed(0)} reversed off the outstanding balance.')),
      );
    }
  }
}
