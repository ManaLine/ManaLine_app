import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../state/customer_loans_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('d MMM yyyy');

/// CW-004 — My Loans. Two entry paths both land here with an explicit
/// businessId, not implicit global state: CW-001 Quick Actions passes
/// the currently-selected business; CW-006 My Profile/Memberships can
/// pass a different, explicitly-tapped Customer-role membership's
/// businessId. Both use this same constructor param.
class MyLoansScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String customerId;

  const MyLoansScreen({super.key, required this.businessId, required this.customerId});

  @override
  ConsumerState<MyLoansScreen> createState() => _MyLoansScreenState();
}

class _MyLoansScreenState extends ConsumerState<MyLoansScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerLoansProvider.notifier).load(customerId: widget.customerId, businessId: widget.businessId);
    });
  }

  Future<void> _refresh() =>
      ref.read(customerLoansProvider.notifier).load(customerId: widget.customerId, businessId: widget.businessId);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerLoansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('my loans'),
        leading: BackButton(onPressed: () => context.go('/cw-001', extra: widget.businessId)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: state.loading && state.loans.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.error != null && state.loans.isEmpty
                  ? _errorState(context)
                  : state.visibleSorted.isEmpty
                      ? _EmptyState(businessId: widget.businessId)
                      : ListView.separated(
                          padding: const EdgeInsets.all(ManaSpacing.lg),
                          itemCount: state.visibleSorted.length,
                          separatorBuilder: (_, __) => const SizedBox(height: ManaSpacing.sm),
                          itemBuilder: (context, i) {
                            final loan = state.visibleSorted[i];
                            return _LoanCard(
                              loan: loan,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: loan.loanId)),
                              ),
                            );
                          },
                        ),
        ),
      ),
    );
  }

  Widget _errorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('could not load loans'),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(onPressed: _refresh, child: const ManaText('retry')),
          ],
        ),
      ),
    );
  }
}

// --- S1 Loan List ------------------------------------------------------------

class _LoanCard extends StatelessWidget {
  final CustomerLoanSummary loan;
  final VoidCallback onTap;
  const _LoanCard({required this.loan, required this.onTap});

  ManaStatus get _pillStatus => switch (loan.loanStatus) {
        'Active' => ManaStatus.good,
        'Grace Period' => ManaStatus.warn,
        'Overdue' => ManaStatus.bad,
        'Penalty' => ManaStatus.bad,
        _ => ManaStatus.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Row(
          children: [
            Flexible(
              child: ManaText.raw(loan.loanNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: ManaSpacing.xs),
            ManaStatusPill(label: loan.loanStatus, status: _pillStatus),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (loan.templateName != null)
                ManaText.raw(loan.templateName!, style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
              ManaText.raw(
                'Outstanding ${_currency.format(loan.outstandingBalance)} of ${_currency.format(loan.principalAmount)}',
                style: TextStyle(fontSize: 16, color: ManaColors.textSecondary),
              ),
              if (loan.nextDueDate != null)
                ManaText.raw(
                  'Next due ${_currency.format(loan.nextDueAmount ?? 0)} on ${_dateFmt.format(loan.nextDueDate!)}',
                  style: TextStyle(fontSize: 16, color: ManaColors.textSecondary),
                ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      ),
    );
  }
}

// --- S3 Empty ------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final String businessId;
  const _EmptyState({required this.businessId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('no loans yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              'You have no loans in this Business yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            // Inferred default-state handling per CW-004's own S3 note
            // ("not explicitly stated in source") — routes toward
            // CW-003, same named-destination stub pattern used
            // elsewhere until a caller wires whether this Business
            // actually allows Customer-initiated requests.
            ElevatedButton.icon(
              onPressed: () => context.push('/cw-003', extra: businessId),
              icon: const Icon(Icons.request_page_outlined),
              label: const ManaText('request a new loan'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- S2 Loan Detail --------------------------------------------------------------

class LoanDetailScreen extends ConsumerStatefulWidget {
  final String loanId;
  const LoanDetailScreen({super.key, required this.loanId});

  @override
  ConsumerState<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends ConsumerState<LoanDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fresh detail state per entry — no stale loan bleeding in from a
      // previously-viewed Loan Detail (mirrors LoanWizardNotifier's own
      // no-draft-persistence convention). Reset happens on entry, not
      // in dispose(), since calling ref after this widget is disposed
      // is unsafe with Riverpod.
      ref.read(loanDetailProvider.notifier).reset();
      ref.read(loanDetailProvider.notifier).load(widget.loanId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loanDetailProvider);

    return Scaffold(
      appBar: AppBar(title: const ManaText('loan detail')),
      body: SafeArea(
        child: state.loading && state.detail == null
            ? const Center(child: CircularProgressIndicator())
            : state.detail == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(ManaSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
                          const SizedBox(height: ManaSpacing.md),
                          const ManaText('could not load loan'),
                          const SizedBox(height: ManaSpacing.sm),
                          ElevatedButton(
                            onPressed: () => ref.read(loanDetailProvider.notifier).load(widget.loanId),
                            child: const ManaText('retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    children: [
                      _AgreementSummaryCard(detail: state.detail!),
                      const SizedBox(height: ManaSpacing.lg),
                      _ScheduleCard(schedule: state.detail!.schedule),
                      const SizedBox(height: ManaSpacing.lg),
                      _PaymentHistoryCard(loading: state.historyLoading, history: state.paymentHistory),
                      if (state.detail!.pendingOnlinePayments.isNotEmpty) ...[
                        const SizedBox(height: ManaSpacing.lg),
                        _PendingOnlinePaymentsCard(pending: state.detail!.pendingOnlinePayments),
                      ],
                      if (state.detail!.penaltyAmount != null || state.detail!.gracePeriodEndDate != null) ...[
                        const SizedBox(height: ManaSpacing.lg),
                        _PenaltyGraceCard(detail: state.detail!),
                      ],
                      const SizedBox(height: ManaSpacing.xl),
                      _ActionsRow(loanId: widget.loanId),
                    ],
                  ),
      ),
    );
  }
}

class _AgreementSummaryCard extends StatelessWidget {
  final CustomerLoanDetail detail;
  const _AgreementSummaryCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final s = detail.summary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: ManaText.raw(s.loanNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                const SizedBox(width: ManaSpacing.xs),
                ManaStatusPill(
                  label: s.loanStatus,
                  status: switch (s.loanStatus) {
                    'Active' => ManaStatus.good,
                    'Grace Period' => ManaStatus.warn,
                    'Overdue' || 'Penalty' => ManaStatus.bad,
                    _ => ManaStatus.neutral,
                  },
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            _row('Principal Amount', _currency.format(s.principalAmount)),
            _row('Outstanding Balance', _currency.format(s.outstandingBalance)),
            _row('Repayment Type', '${detail.durationValue} × ${detail.repaymentType}'),
            _row('Installment Amount', _currency.format(detail.installmentAmount)),
            _row('Effective Date', _dateFmt.format(detail.effectiveDate)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ManaText(label, style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
            ManaText.raw(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _ScheduleCard extends StatelessWidget {
  final List<LoanScheduleEntry> schedule;
  const _ScheduleCard({required this.schedule});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('repayment schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: ManaSpacing.sm),
            if (schedule.isEmpty)
              ManaText.raw('No schedule available.', style: TextStyle(color: ManaColors.textSecondary))
            else
              ...schedule.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ManaText.raw('#${e.installmentNumber} · ${_dateFmt.format(e.dueDate)}',
                            style: const TextStyle(fontSize: 13)),
                        Row(
                          children: [
                            ManaText.raw(_currency.format(e.installmentAmount),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(width: ManaSpacing.xs),
                            ManaStatusPill(
                              label: e.status,
                              status: switch (e.status) {
                                'Completed' => ManaStatus.good,
                                'Partial' => ManaStatus.warn,
                                _ => ManaStatus.neutral,
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

/// Payment History — confirmed collections only (Cash + Online), per
/// CW-004's own LOAN DETAIL VIEW. Field shape mirrors AG-002/OW-006's
/// CollectionDueRow labels where the schema overlaps (amount, receipt/
/// loan reference), read-only here since Customer can view but never
/// edit any financial field.
class _PaymentHistoryCard extends StatelessWidget {
  final bool loading;
  final List<LoanPaymentHistoryEntry> history;
  const _PaymentHistoryCard({required this.loading, required this.history});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('payment history', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: ManaSpacing.sm),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: ManaSpacing.md),
                child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (history.isEmpty)
              ManaText.raw('No confirmed payments yet.', style: TextStyle(color: ManaColors.textSecondary))
            else
              ...history.map((h) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ManaText.raw('${_dateFmt.format(h.businessDate)} · ${h.receiptNumber}',
                            style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                        Row(
                          children: [
                            ManaText.raw(_currency.format(h.collectedAmount),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(width: ManaSpacing.xs),
                            ManaStatusPill(
                              label: h.paymentMode,
                              status: h.paymentMode == 'Online' ? ManaStatus.neutral : ManaStatus.good,
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _PendingOnlinePaymentsCard extends StatelessWidget {
  final List<PendingOnlinePayment> pending;
  const _PendingOnlinePaymentsCard({required this.pending});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: ManaColors.statusWarnFaint,
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('pending online payments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw('Awaiting Owner/Agent confirmation.',
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.sm),
            ...pending.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ManaText.raw(_dateFmt.format(p.submittedAt), style: const TextStyle(fontSize: 13)),
                      ManaText.raw(_currency.format(p.amount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _PenaltyGraceCard extends StatelessWidget {
  final CustomerLoanDetail detail;
  const _PenaltyGraceCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detail.penaltyAmount != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ManaText('penalty', style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
                  ManaText.raw(_currency.format(detail.penaltyAmount!),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ManaColors.statusBad)),
                ],
              ),
            if (detail.gracePeriodEndDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ManaText('grace period end date', style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
                    ManaText.raw(_dateFmt.format(detail.gracePeriodEndDate!), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Make A Payment / Download Statement — stubbed as named destinations
/// per this chat's brief; CW-005 (not built by this chat) owns actual
/// payment entry.
class _ActionsRow extends StatelessWidget {
  final String loanId;
  const _ActionsRow({required this.loanId});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => context.push('/cw-005', extra: loanId),
            icon: const Icon(Icons.payments_outlined),
            label: const ManaText('make a payment'),
          ),
        ),
        const SizedBox(width: ManaSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              // Download Statement — GET /loans/{loan_id}/statement,
              // no dedicated UI beyond a stub trigger per this chat's
              // scope (file save/share mechanics not specified in
              // source; flagged for master chat).
            },
            icon: const Icon(Icons.download_outlined),
            label: const ManaText('download statement'),
          ),
        ),
      ],
    );
  }
}
