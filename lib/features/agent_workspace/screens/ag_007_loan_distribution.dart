import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/agent_dashboard_state.dart';
import '../state/loan_distribution_state.dart';
import '../../owner_workspace/state/customer_state.dart';
import '../../owner_workspace/state/loan_wizard_state.dart';
import '../../../shared/live_face_capture_screen.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

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
      appBar: AppBar(title: const ManaText('loan distribution')),
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
                label: const ManaText('start new loan'),
              ),
              const SizedBox(height: ManaSpacing.xxl),
              const ManaText('bf cash transfer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: ManaSpacing.xs),
              const ManaText.raw(
                'Send or receive BF Cash with another Agent. A transfer only moves '
                'the balance once BOTH agents confirm (BR-173) — no Owner approval '
                'gate applies.',
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
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
                  child: ManaText.raw(distState.error!, style: const TextStyle(color: ManaColors.statusBad)),
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

class _BfCashPanel extends StatelessWidget {
  final AgentBfAssignment? bfAssignment;
  const _BfCashPanel({required this.bfAssignment});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('bf cash panel', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: ManaSpacing.sm),
            Row(
              children: [
                const Expanded(
                  child: ManaText.raw('Current BF Cash Balance', style: TextStyle(color: ManaColors.textSecondary)),
                ),
                ManaText.raw(
                  bfAssignment == null ? '—' : _currency.format(bfAssignment!.openingBf),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            if (bfAssignment == null) ...[
              const SizedBox(height: ManaSpacing.sm),
              const ManaText.raw(
                'No BF Cash assignment found for this session yet — loan issuance is '
                'blocked until the Owner grants BF Cash access via AG-001\'s Opening BF gate.',
                style: TextStyle(fontSize: 13, color: ManaColors.statusWarn),
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
  final _toAgentName = TextEditingController();
  final _toAgentId = TextEditingController(); // stub picker — real build reuses OW-002's agent list
  final _amount = TextEditingController();

  bool get _canSend =>
      _toAgentName.text.trim().isNotEmpty &&
      _toAgentId.text.trim().isNotEmpty &&
      (double.tryParse(_amount.text) ?? 0) > 0;

  Future<void> _send() async {
    final ok = await NetworkErrorHandler.run(context, () async {
      final sent = await ref.read(loanDistributionProvider.notifier).sendTransfer(
            fromAgentId: widget.agentId,
            toAgentId: _toAgentId.text.trim(),
            toAgentName: _toAgentName.text.trim(),
            amount: double.parse(_amount.text),
            businessDate: DateTime.now().toIso8601String().split('T').first,
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
      const SnackBar(content: Text('BF Cash Transfer sent — pending the other Agent\'s confirmation.')),
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
            const ManaText('send bf cash', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _toAgentName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'To Agent Name *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _toAgentId,
              decoration: const InputDecoration(labelText: 'To Agent ID *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            ElevatedButton(
              onPressed: (_canSend && !sending) ? _send : null,
              child: sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const ManaText('send'),
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
        .showSnackBar(const SnackBar(content: Text('BF Cash Transfer confirmed — balance updated.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (transfers.isEmpty) {
      return ManaText.raw('No transfers — $title.', style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary));
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
        ManaText(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: ManaSpacing.sm),
        ...transfers.map((t) => Card(
              margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
              child: ListTile(
                leading: const Icon(Icons.sync_alt, color: ManaColors.statusWarn),
                title: ManaText.raw(
                  t.direction(agentId) == 'Incoming' ? 'From ${t.fromAgentName}' : 'To ${t.toAgentName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: ManaText.raw('${t.businessDate} · ${_currency.format(t.amount)}',
                    style: const TextStyle(fontSize: 16, color: ManaColors.textSecondary)),
                trailing: showConfirmAction
                    ? ElevatedButton(
                        onPressed: confirming ? null : () => _confirm(context, ref, t),
                        child: confirming
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const ManaText('confirm'),
                      )
                    : const ManaStatusPill(label: 'Pending', status: ManaStatus.warn),
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

  @override
  void dispose() {
    // No draft persistence for this wizard (per OW-005, unchanged) —
    // exiting mid-flow resets progress.
    ref.read(loanWizardProvider.notifier).reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loanWizardProvider);
    final stepIndex = _steps.indexOf(state.step);

    return Scaffold(
      appBar: AppBar(title: const ManaText('new loan')),
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
                  ManaText.raw('Step ${stepIndex + 1} of ${_steps.length}',
                      style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
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
        return const _AgStep1CustomerSelection();
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

class _AgStep1CustomerSelection extends ConsumerStatefulWidget {
  const _AgStep1CustomerSelection();

  @override
  ConsumerState<_AgStep1CustomerSelection> createState() => _AgStep1CustomerSelectionState();
}

class _AgStep1CustomerSelectionState extends ConsumerState<_AgStep1CustomerSelection> {
  final _query = TextEditingController();
  CustomerSummary? _found;
  bool _searching = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    // Same fix as OW-004/OW-005's customer search: this box was always
    // sent as `fullName:` regardless of what was typed, so an MLID/phone/
    // Aadhaar search never matched. Classify by shape and route to the
    // matching owner_search_person() param.
    final query = _query.text.trim();
    final isMlid = RegExp(r'^ML[A-Za-z]{2}\d+$').hasMatch(query);
    final digitsOnly = RegExp(r'^\d+$').hasMatch(query);
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).searchIdentity(
            mlid: isMlid ? query : null,
            aadhaar: !isMlid && digitsOnly && query.length == 12 ? query : null,
            phone: !isMlid && digitsOnly && query.length == 10 ? query : null,
            fullName: isMlid || digitsOnly ? null : query,
          );
    });
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText('select customer', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        const ManaText.raw('Search by Phone, MANA LINE ID, Aadhaar, Customer Name, or Village. Only '
            'existing customers may receive a remotely-issued loan — a brand-new '
            'customer must first be created via Customer Management.',
            style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                decoration: const InputDecoration(labelText: 'Search'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            ElevatedButton(
              onPressed: (_query.text.trim().isNotEmpty && !_searching) ? _search : null,
              child: _searching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const ManaText('search'),
            ),
          ],
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (_found != null)
          Card(
            child: ListTile(
              leading: const ManaVerificationRing(isVerified: true, size: 44),
              title: ManaText.raw(_found!.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: ManaText.raw('${_found!.mlid} · ${_found!.village}'),
              trailing: ElevatedButton(
                onPressed: () => ref.read(loanWizardProvider.notifier).selectCustomer(_found!),
                child: const ManaText('select'),
              ),
            ),
          )
        else if (_query.text.trim().isNotEmpty && !_searching)
          const ManaText.raw('No matching customer found.', style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
      ],
    );
  }
}

class _AgStep2Eligibility extends ConsumerWidget {
  const _AgStep2Eligibility();

  static const _systemChecks = [
    'Customer Exists',
    'Business Linked',
    'Customer Active',
    'Not Blocked',
    'No Duplicate Loan',
    'No Owner Restrictions',
    'No Pending Approval',
    'Outstanding Rules',
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
        ManaText('eligibility check', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw('Customer: ${state.customer?.fullName ?? ''}',
            style: const TextStyle(color: ManaColors.textSecondary)),
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
                            const Icon(Icons.check_circle, size: 16, color: ManaColors.statusGood),
                            const SizedBox(width: ManaSpacing.sm),
                            ManaText(c, style: const TextStyle(fontSize: 13)),
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
              const ManaText.raw(
                "BF Cash Validation (BR-165): this Agent's BF Cash must cover the "
                'loan amount — hard block, not a warning. Verified at confirm time '
                'inside the create call.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                'Current BF Cash Balance: ${bf == null ? '—' : _currency.format(bf.openingBf)}',
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
                style: const TextStyle(color: ManaColors.statusBad, fontSize: 13)),
          ),
        ],
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: () => ref.read(loanWizardProvider.notifier).markEligibilityPassed(),
          child: const ManaText('continue'),
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
  final _repaymentAmount = TextEditingController();
  final _interest = TextEditingController();
  final _processingFee = TextEditingController();
  final _duration = TextEditingController();
  final _installment = TextEditingController();
  String _repaymentType = 'Weekly';
  DateTime _effectiveDate = DateTime.now();

  double get _amountGiven =>
      (double.tryParse(_repaymentAmount.text) ?? 0) -
      (double.tryParse(_interest.text) ?? 0) -
      (double.tryParse(_processingFee.text) ?? 0);

  bool get _canSubmit =>
      (double.tryParse(_repaymentAmount.text) ?? 0) > 0 &&
      (int.tryParse(_duration.text) ?? 0) > 0 &&
      (double.tryParse(_installment.text) ?? 0) > 0;

  void _submit(String agentId) {
    // Collection Agent = this Agent (self) — an Agent issuing a loan
    // remotely is its own collection agent, unlike OW-005's Owner-side
    // picker which selects among the workforce.
    ref.read(loanWizardProvider.notifier).setLoanDetails(
          repaymentAmount: double.parse(_repaymentAmount.text),
          interest: double.tryParse(_interest.text) ?? 0,
          processingFee: double.tryParse(_processingFee.text) ?? 0,
          repaymentType: _repaymentType,
          durationValue: int.parse(_duration.text),
          installmentAmount: double.parse(_installment.text),
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
        ManaText('loan details', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.lg),
        TextField(
          controller: _repaymentAmount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Repayment Amount *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _interest,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Interest'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _processingFee,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Processing Fee'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _repaymentType,
          decoration: const InputDecoration(labelText: 'Repayment Type'),
          items: const [
            DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
            DropdownMenuItem(value: 'Daily', child: Text('Daily')),
          ],
          onChanged: (v) => setState(() => _repaymentType = v ?? 'Weekly'),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Duration (installments) *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _installment,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Installment Amount *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const ManaText('effective date'),
          subtitle: ManaText.raw('${_effectiveDate.day}/${_effectiveDate.month}/${_effectiveDate.year}'),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _effectiveDate,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _effectiveDate = picked);
          },
        ),
        const SizedBox(height: ManaSpacing.lg),
        Container(
          padding: const EdgeInsets.all(ManaSpacing.md),
          decoration: BoxDecoration(color: ManaColors.brandFaint, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              const Expanded(
                child: ManaText('amount given (system-derived, read-only)', style: TextStyle(fontSize: 13)),
              ),
              ManaText.raw('₹${_amountGiven.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: _canSubmit ? () => _submit(agentId) : null,
          child: const ManaText('continue'),
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
        ManaText('guarantor', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        const ManaText.raw('Guarantor is loan-scoped, not customer-scoped.',
            style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.lg),
        const ManaText('need guarantor?', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: ManaSpacing.sm),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const ManaText('yes'),
                selected: _needsGuarantor == true,
                onSelected: (_) => setState(() => _needsGuarantor = true),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            Expanded(
              child: ChoiceChip(
                label: const ManaText('no'),
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
            decoration: const InputDecoration(labelText: 'Guarantor Name *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(controller: _relationship, decoration: const InputDecoration(labelText: 'Relationship')),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
          const SizedBox(height: ManaSpacing.md),
          TextField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks')),
        ],
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: (_needsGuarantor != null && _canSubmit) ? _submit : null,
          child: const ManaText('continue'),
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
        ManaText('live photo', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        const ManaText.raw(
          'Mandatory before this loan can be created (BR-036/081, fraud prevention). '
          'Camera capture only — gallery upload is never offered.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (state.livePhotoBytes == null)
          OutlinedButton.icon(
            onPressed: _capture,
            icon: const Icon(Icons.camera_alt),
            label: const ManaText('capture live photo *'),
          )
        else
          Row(
            children: [
              CircleAvatar(radius: 28, backgroundImage: MemoryImage(state.livePhotoBytes!)),
              const SizedBox(width: ManaSpacing.md),
              TextButton.icon(
                onPressed: _capture,
                icon: const Icon(Icons.refresh, size: 18),
                label: const ManaText('retake photo'),
              ),
            ],
          ),
        const SizedBox(height: ManaSpacing.xl),
        const ManaText('grace period (days)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: ManaSpacing.xs),
        const ManaText.raw(
          'Internal only — never shown to the customer (BR-206). Owner-configurable, '
          'overridable per loan (BR-007/381).',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextFormField(
          key: ValueKey(state.gracePeriodDays),
          initialValue: state.gracePeriodDays.toString(),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Grace Period (days) *'),
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
          child: const ManaText('continue'),
        ),
      ],
    );
  }
}

class _AgStep5Confirm extends ConsumerWidget {
  final String businessId;
  const _AgStep5Confirm({required this.businessId});

  bool _looksLikeBfCashFailure(String reason) {
    final r = reason.toLowerCase();
    return r.contains('bf cash') || r.contains('insufficient');
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final loanNumber = await NetworkErrorHandler.run(context, () async {
      final n = await ref.read(loanWizardProvider.notifier).confirm(businessId: businessId);
      if (n == null) throw Exception(ref.read(loanWizardProvider).error ?? 'Loan could not be created.');
      return n;
    });
    if (loanNumber == null) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Loan $loanNumber created — active.')));
    // Per AG-007's own locked rule (mirrors OW-005): an Agent-created
    // loan returns to the Agent's own dashboard, not OW-001.
    context.go('/ag-001', extra: businessId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loanWizardProvider);
    final blocked = state.error != null && _looksLikeBfCashFailure(state.error!);

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText('confirm loan', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Column(
              children: [
                _row('Customer', state.customer?.fullName ?? ''),
                _row('Repayment Amount', '₹${state.repaymentAmount?.toStringAsFixed(0) ?? '0'}'),
                _row('Interest', '₹${state.interest?.toStringAsFixed(0) ?? '0'}'),
                _row('Processing Fee', '₹${state.processingFee?.toStringAsFixed(0) ?? '0'}'),
                _row('Amount Given', '₹${state.amountGiven.toStringAsFixed(0)}'),
                _row('Repayment Type', state.repaymentType),
                _row('Duration', '${state.durationValue ?? 0} installments'),
                _row('Installment', '₹${state.installmentAmount?.toStringAsFixed(0) ?? '0'}'),
                _row('Guarantor', state.needsGuarantor ? (state.guarantorName ?? '') : 'None'),
              ],
            ),
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: ManaSpacing.md),
          Container(
            padding: const EdgeInsets.all(ManaSpacing.md),
            decoration: BoxDecoration(color: ManaColors.statusBadFaint, borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(state.error!, style: const TextStyle(color: ManaColors.statusBad)),
                if (blocked) ...[
                  const SizedBox(height: ManaSpacing.sm),
                  const ManaText.raw(
                    'Loan Creation Blocked (BR-165). Top up BF Cash after the Owner sends '
                    'money outside the app, or receive a BF Cash Transfer from another '
                    'Agent — see the BF Cash Transfer section on the previous screen.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ],
            ),
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
                child: const ManaText('cancel'),
              ),
            ),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: state.submitting ? null : () => _confirm(context, ref),
                child: state.submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const ManaText('confirm — create loan'),
              ),
            ),
          ],
        ),
      ],
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
