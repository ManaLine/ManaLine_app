import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_label_value_row.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/bf_request_card.dart';
import '../../../shared/loan_customer_search.dart';
import '../state/agent_dashboard_state.dart';
import '../../../shared/soft_delete_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../state/loan_distribution_state.dart';
import '../../owner_workspace/state/loan_wizard_state.dart';
import '../../../shared/live_face_capture_screen.dart';
import '../../../shared/mana_time.dart';


/// AG-007 — Loan Distribution. Per spec's own PURPOSE/WIZARD STEPS: this
/// is NOT a new wizard. The 5-step flow (Customer Selection → Eligibility
/// → Loan Details → Guarantor → Confirm) is OW-005's, reused verbatim
/// under Agent auth via the *same* `loanWizardProvider` notifier — this
/// file only rebuilds the UI shell locally (per file-ownership boundary;
/// OW-005's own private step widgets aren't importable) and changes the
/// one thing that must differ for an Agent: Loan Active (S4) returns to
/// AG-001, not OW-001 (per OW-005's own locked rule, restated in
/// AG-007's NAVIGATION section).
///
/// This screen also owns what's genuinely new here: the BF Cash Panel
/// (this Agent's BF balance) and BF Cash Transfer (Send/Receive, BR-173)
/// — the natural recovery path when Step 2/Confirm's BF Cash Validation
/// (BR-165) hard-blocks loan creation.
class Ag007LoanDistributionScreen extends ConsumerStatefulWidget {
  final String agentId;
  final String businessId;
  final String? prefilledCustomerId; // from AG-004 "Create Loan" / AG-005 draft resume

  const Ag007LoanDistributionScreen({
    super.key,
    required this.agentId,
    required this.businessId,
    this.prefilledCustomerId,
  });

  @override
  ConsumerState<Ag007LoanDistributionScreen> createState() => _Ag007LoanDistributionScreenState();
}

class _Ag007LoanDistributionScreenState extends ConsumerState<Ag007LoanDistributionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(loanDistributionProvider.notifier).loadTransfers(agentId: widget.agentId);
    });
  }

  void _startNewLoan() {
    ref.read(loanWizardProvider.notifier).reset();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AgentLoanWizardFlow(businessId: widget.businessId, agentId: widget.agentId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bfState = ref.watch(agentDashboardProvider);
    final distState = ref.watch(loanDistributionProvider);

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('loan_distribution_screen')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(loanDistributionProvider.notifier).loadTransfers(agentId: widget.agentId),
          child: ListView(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            children: [
              _BfCashPanel(bfAssignment: bfState.bfAssignment),
              const SizedBox(height: ManaSpacing.lg),
              ElevatedButton.icon(
                onPressed: bfState.bfAssignment == null ? null : _startNewLoan,
                icon: const Icon(Icons.request_page_outlined),
                label: ManaText.raw(ref.t('start_new_loan')),
              ),
              const SizedBox(height: ManaSpacing.xxl),
              ManaText.raw(ref.t('bf_cash_transfer'), style: ManaType.cardTitle),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                ref.t('bf_cash_transfer_note'),
                style: ManaType.note,
              ),
              const SizedBox(height: ManaSpacing.md),
              _SendBfCashCard(agentId: widget.agentId),
              const SizedBox(height: ManaSpacing.lg),
              if (distState.error != null)
                Container(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  margin: const EdgeInsets.only(bottom: ManaSpacing.md),
                  decoration:
                      BoxDecoration(color: ManaColors.statusBadFaint, borderRadius: BorderRadius.circular(8)),
                  child: ManaText.raw(distState.error!, style: ManaType.bad),
                ),
              _TransferList(
                title: 'awaiting your confirmation',
                transfers: distState.incoming(widget.agentId),
                agentId: widget.agentId,
                showConfirmAction: true,
              ),
              const SizedBox(height: ManaSpacing.md),
              _TransferList(
                title: 'sent — awaiting other agent',
                transfers: distState.outgoing(widget.agentId),
                agentId: widget.agentId,
                showConfirmAction: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- BF Cash Panel ---------------------------------------------------------

class _BfCashPanel extends ConsumerWidget {
  final AgentBfAssignment? bfAssignment;
  const _BfCashPanel({required this.bfAssignment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('bf_cash_panel'), style: ManaType.strong),
            const SizedBox(height: ManaSpacing.sm),
            // The label was guarded and the figure beside it was not, so the
            // BF cash an Agent is holding ran 26px off the card at 2.0x.
            ManaLabelValueRow(
              label: ref.t('current_bf_cash_balance'),
              value: bfAssignment == null ? '—' : manaRupees(bfAssignment!.openingBf),
              valueStyle: ManaType.sheetTitle,
            ),
            if (bfAssignment == null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(
                ref.t('no_bf_assignment_note'),
                style: ManaType.noteWarn,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- BF Cash Transfer — Send ------------------------------------------------

class _SendBfCashCard extends ConsumerStatefulWidget {
  final String agentId;
  const _SendBfCashCard({required this.agentId});

  @override
  ConsumerState<_SendBfCashCard> createState() => _SendBfCashCardState();
}

class _SendBfCashCardState extends ConsumerState<_SendBfCashCard> {

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _toAgentName.dispose();
    _toAgentId.dispose();
    _amount.dispose();
    super.dispose();
  }
  final _toAgentName = TextEditingController();
  final _toAgentId = TextEditingController(); // stub picker — real build reuses OW-002's agent list
  final _amount = TextEditingController();

  bool get _canSend =>
      _toAgentName.text.trim().isNotEmpty &&
      _toAgentId.text.trim().isNotEmpty &&
      (int.tryParse(_amount.text) ?? 0) > 0;

  Future<void> _send() async {
    final ok = await NetworkErrorHandler.run(context, () async {
      final sent = await ref.read(loanDistributionProvider.notifier).sendTransfer(
            fromAgentId: widget.agentId,
            toAgentId: _toAgentId.text.trim(),
            toAgentName: _toAgentName.text.trim(),
            amount: int.parse(_amount.text), // whole rupees (M8)
            businessDate: manaBusinessDate(),
          );
      if (!sent) {
        throw Exception(ref.read(loanDistributionProvider).error ?? 'Transfer could not be sent.');
      }
      return sent;
    });
    if (ok == null || !mounted) return;
    setState(() {
      _toAgentName.clear();
      _toAgentId.clear();
      _amount.clear();
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(ref.t('bf_transfer_sent_note'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sending = ref.watch(loanDistributionProvider).sendingTransfer;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('send_bf_cash'), style: ManaType.emphasis),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _toAgentName,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: ref.t('to_agent_name_field')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _toAgentId,
              decoration: InputDecoration(labelText: ref.t('to_agent_id_field')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: ref.t('amount_required_field')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            ElevatedButton(
              onPressed: (_canSend && !sending) ? _send : null,
              child: sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('send')),
            ),
          ],
        ),
      ),
    );
  }
}

// --- BF Cash Transfer — lists ------------------------------------------------

class _TransferList extends ConsumerWidget {
  final String title;
  final List<CashTransfer> transfers;
  final String agentId;
  final bool showConfirmAction;

  const _TransferList({
    required this.title,
    required this.transfers,
    required this.agentId,
    required this.showConfirmAction,
  });

  Future<void> _confirm(BuildContext context, WidgetRef ref, CashTransfer t) async {
    final ok = await NetworkErrorHandler.run(context, () async {
      final result = await ref
          .read(loanDistributionProvider.notifier)
          .confirmTransfer(transferId: t.transferId, agentId: agentId);
      if (!result) {
        throw Exception(ref.read(loanDistributionProvider).error ?? 'Could not confirm transfer.');
      }
      return result;
    });
    if (ok == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: ManaText.raw(ref.t('bf_transfer_confirmed_note'))));
  }

  Future<void> _deleteTransfer(
      BuildContext context, WidgetRef ref, CashTransfer t) async {
    final other = t.direction(agentId) == 'Incoming' ? t.fromAgentName : t.toAgentName;
    final deleted = await ConfirmDeleteDialog.show(
      context,
      entity: DeletableEntity.cashTransfer,
      recordId: t.transferId,
      description: '${manaRupees(t.amount)} with $other on ${t.businessDate}',
    );
    if (!deleted || !context.mounted) return;
    await ref.read(loanDistributionProvider.notifier).loadTransfers(agentId: agentId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (transfers.isEmpty) {
      return ManaText.raw(ref.t('no_transfers_note').replaceAll('{title}', title),
          style: ManaType.note);
    }
    // BUG FIXED this pass: the Confirm button had no in-flight guard at
    // all — confirmTransfer() does a real balance-affecting write, and a
    // double-tap (easy on a real device, especially over a slow
    // connection where the first tap's spinner never showed) could fire
    // it twice. confirmingTransferId already existed and was already
    // correctly toggled by the notifier; nothing here ever watched it.
    final confirming = ref.watch(loanDistributionProvider).confirmingTransferId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(title, style: ManaType.smallStrong),
        const SizedBox(height: ManaSpacing.sm),
        ...transfers.map((t) => Card(
              margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
              child: ListTile(
                leading: Icon(Icons.sync_alt, color: ManaColors.statusWarn),
                title: ManaText.raw(
                  t.direction(agentId) == 'Incoming'
                      ? ref.t('from_agent_note').replaceAll('{name}', t.fromAgentName)
                      : ref.t('to_agent_note').replaceAll('{name}', t.toAgentName),
                  style: ManaType.emphasis,
                ),
                subtitle: ManaText.raw('${t.businessDate} · ${manaRupees(t.amount)}',
                    style: TextStyle(fontSize: 16, color: ManaColors.textSecondary)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Not Flexible: a flexible child in a MainAxisSize.min
                    // Row makes it claim the whole tile width, which
                    // ListTile.trailing rejects outright.
                    showConfirmAction
                        ? ElevatedButton(
                            onPressed: confirming ? null : () => _confirm(context, ref, t),
                            child: confirming
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : ManaText.raw(ref.t('confirm')),
                          )
                        : ManaStatusPill(label: ref.t('pending_label'), status: ManaStatus.warn),
                    // A transfer neither side has confirmed has moved no
                    // cash yet, so deleting one is how a mistyped hand-over
                    // is cancelled rather than left pending forever.
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: ManaColors.statusBad,
                      tooltip: ref.t('delete'),
                      onPressed: () => _deleteTransfer(context, ref, t),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

// ============================================================================
// Agent-side wizard shell — reuses loanWizardProvider verbatim (OW-005).
// Only the post-Confirm navigation target differs (AG-001, not OW-001) and
// the BF Cash Blocked messaging/recovery links are Agent-specific framing.
// ============================================================================

class _AgentLoanWizardFlow extends ConsumerStatefulWidget {
  final String businessId;
  final String agentId;
  const _AgentLoanWizardFlow({required this.businessId, required this.agentId});

  @override
  ConsumerState<_AgentLoanWizardFlow> createState() => _AgentLoanWizardFlowState();
}

class _AgentLoanWizardFlowState extends ConsumerState<_AgentLoanWizardFlow> {
  static const _steps = LoanWizardStep.values;

  // No dispose-time reset. `ref.read()` inside dispose() is forbidden by
  // Riverpod -- it threw "Cannot use \"ref\" after the widget was disposed"
  // every single time somebody left this wizard, so the reset it looked like
  // it was doing has never once happened. The guarantee it was reaching for
  // is already met on the way IN: _startNewLoan resets before it pushes this flow, so a fresh wizard
  // starts empty regardless of how the last one ended.


  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loanWizardProvider);
    final stepIndex = _steps.indexOf(state.step);

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('new_loan')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, ManaSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (stepIndex + 1) / _steps.length,
                        minHeight: 6,
                        backgroundColor: ManaColors.surfaceSunken,
                        color: ManaColors.brand,
                      ),
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.md),
                  // Flexible: "Step 3 Of 6" translated is wider than English,
                  // and bare beside an Expanded bar it ran 26px off the edge
                  // at 2.0x on every one of the six steps.
                  Flexible(
                    child: ManaText.raw(
                        ref
                            .t('step_x_of_y')
                            .replaceAll('{current}', '${stepIndex + 1}')
                            .replaceAll('{total}', '${_steps.length}'),
                        style: ManaType.note),
                  ),
                ],
              ),
            ),
            Expanded(child: _stepBody(state)),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(LoanWizardState state) {
    switch (state.step) {
      case LoanWizardStep.customerSelection:
        return _AgStep1CustomerSelection(
            businessId: widget.businessId, agentId: widget.agentId);
      case LoanWizardStep.eligibility:
        return const _AgStep2Eligibility();
      case LoanWizardStep.loanDetails:
        return _AgStep3LoanDetails(agentId: widget.agentId);
      case LoanWizardStep.guarantor:
        return const _AgStep4Guarantor();
      case LoanWizardStep.livePhoto:
        return const _AgStep4bLivePhoto();
      case LoanWizardStep.confirm:
        return _AgStep5Confirm(businessId: widget.businessId);
    }
  }
}

/// Step 1 is ManaLoanCustomerSearch, shared with OW-005.
///
/// What was here searched the GLOBAL identity RPC and refused any ambiguous
/// name outright. Those rows carry no customer_id, so once the wizard notifier
/// learned to reject a customer without one -- the fix for Confirm Loan dying
/// on `invalid input syntax for type uuid: ""` -- this screen's Select button
/// went silently dead. Sharing the widget removes the copy that drifted.
class _AgStep1CustomerSelection extends ConsumerWidget {
  final String businessId;
  final String agentId;
  const _AgStep1CustomerSelection({required this.businessId, required this.agentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Advisory only -- create_customer is gated server-side regardless. While
    // the permission is still loading, assume NOT allowed: offering a button
    // that then refuses is worse than one that appears a moment later.
    final perms = ref.watch(agentPermissionsProvider(agentId));
    return ManaLoanCustomerSearch(
      businessId: businessId,
      canAddCustomer: perms.valueOrNull?['can_create_customer'] ?? false,
      onSelected: (c) => ref.read(loanWizardProvider.notifier).selectCustomer(c),
    );
  }
}

class _AgStep2Eligibility extends ConsumerWidget {
  const _AgStep2Eligibility();

  static const _systemChecks = [
    'check_customer_exists',
    'check_business_linked',
    'check_customer_active',
    'check_not_blocked',
    'check_no_duplicate_loan',
    'check_no_owner_restrictions',
    'check_no_pending_approval',
    'check_outstanding_rules',
    'Line Repayment Index',
    'Remote-Issuance Rule (Existing Customer)',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loanWizardProvider);
    final bf = ref.watch(agentDashboardProvider).bfAssignment;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('eligibility_check'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(ref.t('customer_note').replaceAll('{name}', state.customer?.fullName ?? ''),
            style: ManaType.secondary),
        const SizedBox(height: ManaSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Column(
              children: _systemChecks
                  .map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, size: 16, color: ManaColors.statusGood),
                            const SizedBox(width: ManaSpacing.sm),
                            Expanded(child: ManaText.raw(ref.t(c), style: ManaType.small)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: ManaSpacing.md),
        Container(
          padding: const EdgeInsets.all(ManaSpacing.md),
          decoration: BoxDecoration(color: ManaColors.statusWarnFaint, borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(
                ref.t('bf_cash_validation_note'),
                style: ManaType.small,
              ),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                ref.t('current_bf_cash_balance_note').replaceAll(
                    '{amount}', bf == null ? '—' : manaRupees(bf.openingBf)),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (state.eligibilityFailureReason != null) ...[
          const SizedBox(height: ManaSpacing.md),
          Container(
            padding: const EdgeInsets.all(ManaSpacing.md),
            decoration: BoxDecoration(color: ManaColors.statusBadFaint, borderRadius: BorderRadius.circular(8)),
            child: ManaText.raw(state.eligibilityFailureReason!,
                style: ManaType.noteBad),
          ),
        ],
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: () => ref.read(loanWizardProvider.notifier).markEligibilityPassed(),
          child: ManaText.raw(ref.t('continue_label')),
        ),
      ],
    );
  }
}

class _AgStep3LoanDetails extends ConsumerStatefulWidget {
  final String agentId;
  const _AgStep3LoanDetails({required this.agentId});


  @override
  ConsumerState<_AgStep3LoanDetails> createState() => _AgStep3LoanDetailsState();
}

class _AgStep3LoanDetailsState extends ConsumerState<_AgStep3LoanDetails> {

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _repaymentAmount.dispose();
    _interest.dispose();
    _processingFee.dispose();
    _duration.dispose();
    _installment.dispose();
    super.dispose();
  }
  final _repaymentAmount = TextEditingController();
  final _interest = TextEditingController();
  final _processingFee = TextEditingController();
  final _duration = TextEditingController();
  final _installment = TextEditingController();
  String _repaymentType = 'Weekly';
  // IST, not the handset clock: this becomes p_effective_date, i.e. the
  // business day the loan is booked against. See lib/shared/mana_time.dart.
  DateTime _effectiveDate = manaNowIst();

  // Whole rupees (M8) — server stores money as DECIMAL(14,0).
  int get _amountGiven =>
      (int.tryParse(_repaymentAmount.text) ?? 0) -
      (int.tryParse(_interest.text) ?? 0) -
      (int.tryParse(_processingFee.text) ?? 0);

  bool get _canSubmit =>
      (int.tryParse(_repaymentAmount.text) ?? 0) > 0 &&
      (int.tryParse(_duration.text) ?? 0) > 0 &&
      (int.tryParse(_installment.text) ?? 0) > 0;

  void _submit(String agentId) {
    // Collection Agent = this Agent (self) — an Agent issuing a loan
    // remotely is its own collection agent, unlike OW-005's Owner-side
    // picker which selects among the workforce.
    ref.read(loanWizardProvider.notifier).setLoanDetails(
          repaymentAmount: int.parse(_repaymentAmount.text),
          interest: int.tryParse(_interest.text) ?? 0,
          processingFee: int.tryParse(_processingFee.text) ?? 0,
          repaymentType: _repaymentType,
          durationValue: int.parse(_duration.text),
          installmentAmount: int.parse(_installment.text),
          effectiveDate: _effectiveDate.toIso8601String(),
          collectionAgentId: agentId,
          collectionAgentName: 'Self (This Agent)',
        );
  }

  @override
  Widget build(BuildContext context) {
    final agentId = widget.agentId;
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('loan_details'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.lg),
        TextField(
          controller: _repaymentAmount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('repayment_amount_required_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _interest,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('interest_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _processingFee,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('processing_fee_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        DropdownButtonFormField<String>(
          // isExpanded: a DropdownButton sizes to its widest item and
          // overflows rather than shrinking -- measured at 1.0x on OW-002.
          isExpanded: true,
          initialValue: _repaymentType,
          decoration: InputDecoration(labelText: ref.t('repayment_type_field_plain')),
          items: [
            DropdownMenuItem(value: 'Weekly', child: ManaText.raw(ref.t('weekly'))),
            DropdownMenuItem(value: 'Monthly', child: ManaText.raw(ref.t('monthly'))),
            DropdownMenuItem(value: 'Daily', child: ManaText.raw(ref.t('daily'))),
          ],
          onChanged: (v) => setState(() => _repaymentType = v ?? 'Weekly'),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('duration_installments_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _installment,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('installment_amount_required_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: ManaText.raw(ref.t('effective_date')),
          subtitle: ManaText.raw('${_effectiveDate.day}/${_effectiveDate.month}/${_effectiveDate.year}'),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _effectiveDate,
              // Bounds off the same IST clock as the default above — mixing
              // the two can put initialDate outside [firstDate, lastDate].
              firstDate: manaNowIst().subtract(const Duration(days: 1)),
              lastDate: manaNowIst().add(const Duration(days: 365)),
            );
            if (!mounted) return;
            if (picked != null) setState(() => _effectiveDate = picked);
          },
        ),
        const SizedBox(height: ManaSpacing.lg),
        Container(
          padding: const EdgeInsets.all(ManaSpacing.md),
          decoration: BoxDecoration(color: ManaColors.brandFaint, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Expanded(
                child: ManaText.raw(ref.t('amount_given_derived_label'),
                    style: ManaType.small),
              ),
              const SizedBox(width: ManaSpacing.xs),
              ManaText.raw('₹$_amountGiven',
                  style: ManaType.cardTitle),
            ],
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: _canSubmit ? () => _submit(agentId) : null,
          child: ManaText.raw(ref.t('continue_label')),
        ),
      ],
    );
  }
}

class _AgStep4Guarantor extends ConsumerStatefulWidget {
  const _AgStep4Guarantor();

  @override
  ConsumerState<_AgStep4Guarantor> createState() => _AgStep4GuarantorState();
}

class _AgStep4GuarantorState extends ConsumerState<_AgStep4Guarantor> {

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _name.dispose();
    _relationship.dispose();
    _phone.dispose();
    _address.dispose();
    _remarks.dispose();
    super.dispose();
  }
  bool? _needsGuarantor;
  final _name = TextEditingController();
  final _relationship = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _remarks = TextEditingController();

  bool get _canSubmit => _needsGuarantor == false || (_needsGuarantor == true && _name.text.trim().isNotEmpty);

  void _submit() {
    ref.read(loanWizardProvider.notifier).setGuarantor(
          needsGuarantor: _needsGuarantor ?? false,
          name: _name.text.trim(),
          relationship: _relationship.text.trim(),
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          remarks: _remarks.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('guarantor'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(ref.t('guarantor_loan_scoped_note'),
            style: ManaType.note),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(ref.t('need_guarantor_question'), style: ManaType.emphasis),
        const SizedBox(height: ManaSpacing.sm),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: ManaText.raw(ref.t('yes')),
                selected: _needsGuarantor == true,
                onSelected: (_) => setState(() => _needsGuarantor = true),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            Expanded(
              child: ChoiceChip(
                label: ManaText.raw(ref.t('no')),
                selected: _needsGuarantor == false,
                onSelected: (_) => setState(() => _needsGuarantor = false),
              ),
            ),
          ],
        ),
        if (_needsGuarantor == true) ...[
          const SizedBox(height: ManaSpacing.lg),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: ref.t('guarantor_name_field')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(controller: _relationship, decoration: InputDecoration(labelText: ref.t('relationship_field'))),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: ref.t('phone_field')),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(controller: _address, decoration: InputDecoration(labelText: ref.t('address_field'))),
          const SizedBox(height: ManaSpacing.md),
          TextField(controller: _remarks, decoration: InputDecoration(labelText: ref.t('remarks_field'))),
        ],
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: (_needsGuarantor != null && _canSubmit) ? _submit : null,
          child: ManaText.raw(ref.t('continue_label')),
        ),
      ],
    );
  }
}

class _AgStep4bLivePhoto extends ConsumerStatefulWidget {
  const _AgStep4bLivePhoto();

  @override
  ConsumerState<_AgStep4bLivePhoto> createState() => _AgStep4bLivePhotoState();
}

class _AgStep4bLivePhotoState extends ConsumerState<_AgStep4bLivePhoto> {
  Future<void> _capture() async {
    final bytes = await LiveFaceCaptureScreen.capture(context);
    if (bytes == null || !mounted) return;
    ref.read(loanWizardProvider.notifier).setLivePhoto(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loanWizardProvider);
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('live_photo'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('live_photo_note'),
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (state.livePhotoBytes == null)
          OutlinedButton.icon(
            onPressed: _capture,
            icon: const Icon(Icons.camera_alt),
            label: ManaText.raw(ref.t('capture_live_photo')),
          )
        else
          Row(
            children: [
              CircleAvatar(radius: 28, backgroundImage: MemoryImage(state.livePhotoBytes!)),
              const SizedBox(width: ManaSpacing.md),
              TextButton.icon(
                onPressed: _capture,
                icon: const Icon(Icons.refresh, size: 18),
                label: ManaText.raw(ref.t('retake_photo')),
              ),
            ],
          ),
        const SizedBox(height: ManaSpacing.xl),
        ManaText.raw(ref.t('grace_period_days_header'), style: ManaType.emphasis),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('grace_period_note'),
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextFormField(
          key: ValueKey(state.gracePeriodDays),
          initialValue: state.gracePeriodDays.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('grace_period_days_field')),
          onChanged: (v) {
            final parsed = int.tryParse(v);
            if (parsed != null) ref.read(loanWizardProvider.notifier).setGracePeriodDays(parsed);
          },
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: state.livePhotoStepComplete
              ? () => ref.read(loanWizardProvider.notifier).goToStep(LoanWizardStep.confirm)
              : null,
          child: ManaText.raw(ref.t('continue_label')),
        ),
      ],
    );
  }
}

class _AgStep5Confirm extends ConsumerWidget {
  final String businessId;
  const _AgStep5Confirm({required this.businessId});

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final loanNumber = await NetworkErrorHandler.run(context, () async {
      final n = await ref.read(loanWizardProvider.notifier).confirm(businessId: businessId);
      if (n == null) throw Exception(ref.read(loanWizardProvider).error ?? 'Loan could not be created.');
      return n;
    });
    if (loanNumber == null) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: ManaText.raw(ref.t('loan_created_note').replaceAll('{number}', loanNumber))));
    // Per AG-007's own locked rule (mirrors OW-005): an Agent-created
    // loan returns to the Agent's own dashboard, not OW-001.
    context.go('/ag-001', extra: businessId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loanWizardProvider);

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('confirm_loan'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Column(
              children: [
                ManaLabelValueRow(dense: true, label: ref.t('customer'), value: state.customer?.fullName ?? ''),
                ManaLabelValueRow(dense: true, label: ref.t('repayment_amount_required_field'), value: '₹${state.repaymentAmount ?? 0}'),
                ManaLabelValueRow(dense: true, label: ref.t('interest_field'), value: '₹${state.interest ?? 0}'),
                ManaLabelValueRow(dense: true, label: ref.t('processing_fee_field'), value: '₹${state.processingFee ?? 0}'),
                ManaLabelValueRow(dense: true, label: ref.t('amount_given'), value: '₹${state.amountGiven}'),
                ManaLabelValueRow(dense: true, label: ref.t('repayment_type_field_plain'), value: state.repaymentType),
                ManaLabelValueRow(
                  dense: true,
                  label: ref.t('duration'),
                  value: ref
                      .t('duration_installments_note')
                      .replaceAll('{count}', '${state.durationValue ?? 0}'),
                ),
                ManaLabelValueRow(dense: true, label: ref.t('installment_label'), value: '₹${state.installmentAmount ?? 0}'),
                ManaLabelValueRow(
                  dense: true,
                  label: ref.t('guarantor'),
                  value: state.needsGuarantor ? (state.guarantorName ?? '') : ref.t('none'),
                ),
              ],
            ),
          ),
        ),
        // Was decided by sniffing the error text for "bf cash" or
        // "insufficient" -- which would have matched any future message
        // containing either word, and missed this one the moment its wording
        // changed. The RPC returns a code; that is what is read now.
        if (state.blockedOnBf) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaBfRequestCard(
            available: state.bfAvailable ?? 0,
            required: state.bfRequired ?? 0,
            savedDraftId: state.savedDraftId,
            onSend: (amount, reason) =>
                ref.read(loanWizardProvider.notifier).requestBf(amount: amount, reason: reason),
          ),
        ] else if (state.error != null) ...[
          const SizedBox(height: ManaSpacing.md),
          Container(
            padding: const EdgeInsets.all(ManaSpacing.md),
            decoration: BoxDecoration(color: ManaColors.statusBadFaint, borderRadius: BorderRadius.circular(8)),
            child: ManaText.raw(state.error!, style: ManaType.bad),
          ),
        ],
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: state.submitting
                    ? null
                    : () {
                        ref.read(loanWizardProvider.notifier).reset();
                        Navigator.of(context).maybePop();
                      },
                child: ManaText.raw(ref.t('cancel')),
              ),
            ),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: state.submitting ? null : () => _confirm(context, ref),
                child: state.submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : ManaText.raw(ref.t('confirm_create_loan')),
              ),
            ),
          ],
        ),
      ],
    );
  }


}
