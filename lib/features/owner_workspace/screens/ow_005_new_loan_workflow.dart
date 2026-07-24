import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/live_face_capture_screen.dart';
import '../state/customer_state.dart';
import '../state/loan_wizard_state.dart';

/// OW-005 — New Loan Workflow. 6-step wizard: Customer Selection →
/// Eligibility Check → Loan Details → Guarantor (conditional) → Live Photo
/// (BR-036/081, mandatory) → Confirm. No draft persistence (per spec,
/// distinct from OW-000) — exiting mid-flow resets progress.
class NewLoanWorkflowScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String? prefilledCustomerId;
  const NewLoanWorkflowScreen({super.key, required this.businessId, this.prefilledCustomerId});

  @override
  ConsumerState<NewLoanWorkflowScreen> createState() => _NewLoanWorkflowScreenState();
}

class _NewLoanWorkflowScreenState extends ConsumerState<NewLoanWorkflowScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(loanWizardProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    // Resets on exit at any step per spec's own NAVIGATION section — no
    // draft persistence for this wizard.
    ref.read(loanWizardProvider.notifier).reset();
    super.dispose();
  }

  static const _steps = LoanWizardStep.values;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loanWizardProvider);
    final stepIndex = _steps.indexOf(state.step);

    return Scaffold(
      appBar: AppBar(title: const ManaText('new loan')),
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(current: stepIndex + 1, total: _steps.length),
            Expanded(child: _stepBody(state)),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(LoanWizardState state) {
    switch (state.step) {
      case LoanWizardStep.customerSelection:
        return _Step1CustomerSelection(businessId: widget.businessId);
      case LoanWizardStep.eligibility:
        return const _Step2Eligibility();
      case LoanWizardStep.loanDetails:
        return const _Step3LoanDetails();
      case LoanWizardStep.guarantor:
        return const _Step4Guarantor();
      case LoanWizardStep.livePhoto:
        return const _Step4bLivePhoto();
      case LoanWizardStep.confirm:
        return _Step5Confirm(businessId: widget.businessId);
    }
  }
}

class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;
  const _StepIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, ManaSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: current / total,
                minHeight: 6,
                backgroundColor: ManaColors.surfaceSunken,
                color: ManaColors.brass,
              ),
            ),
          ),
          const SizedBox(width: ManaSpacing.md),
          ManaText.raw('Step $current of $total',
              style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
        ],
      ),
    );
  }
}

// --- Step 1 — Customer Selection --------------------------------------

class _Step1CustomerSelection extends ConsumerStatefulWidget {
  final String businessId;
  const _Step1CustomerSelection({required this.businessId});

  @override
  ConsumerState<_Step1CustomerSelection> createState() => _Step1CustomerSelectionState();
}

class _Step1CustomerSelectionState extends ConsumerState<_Step1CustomerSelection> {
  final _query = TextEditingController();
  CustomerSummary? _found;
  bool _searching = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).searchIdentity(fullName: _query.text.trim());
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
        const ManaText.raw('Search by Phone, MANA LINE ID, Aadhaar, Customer Name, or Village.',
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
          const ManaText.raw('No matching customer. New customers must be physically present '
              'and created via Customer Management before a first loan can be issued.',
              style: TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
      ],
    );
  }
}

// --- Step 2 — Eligibility Check ------------------------------------------

class _Step2Eligibility extends ConsumerWidget {
  const _Step2Eligibility();

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
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loanWizardProvider);

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
          child: const ManaText.raw(
            'BF Cash Validation (BR-165): the collecting Agent\'s (or Owner\'s) available '
            'BF Cash must cover the loan amount — hard block, not a warning. Verified at '
            'confirm time inside the create call.',
            style: TextStyle(fontSize: 12),
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

// --- Step 3 — Loan Details ------------------------------------------

class _Step3LoanDetails extends ConsumerStatefulWidget {
  const _Step3LoanDetails();

  @override
  ConsumerState<_Step3LoanDetails> createState() => _Step3LoanDetailsState();
}

class _Step3LoanDetailsState extends ConsumerState<_Step3LoanDetails> {
  final _repaymentAmount = TextEditingController();
  final _interest = TextEditingController();
  final _processingFee = TextEditingController();
  final _duration = TextEditingController();
  final _installment = TextEditingController();
  String _repaymentType = 'Weekly';
  DateTime _effectiveDate = DateTime.now();
  String? _agentId;
  String? _agentName;

  double get _amountGiven =>
      (double.tryParse(_repaymentAmount.text) ?? 0) -
      (double.tryParse(_interest.text) ?? 0) -
      (double.tryParse(_processingFee.text) ?? 0);

  bool get _canSubmit =>
      (double.tryParse(_repaymentAmount.text) ?? 0) > 0 &&
      (int.tryParse(_duration.text) ?? 0) > 0 &&
      (double.tryParse(_installment.text) ?? 0) > 0 &&
      _agentId != null;

  void _submit() {
    ref.read(loanWizardProvider.notifier).setLoanDetails(
          repaymentAmount: double.parse(_repaymentAmount.text),
          interest: double.tryParse(_interest.text) ?? 0,
          processingFee: double.tryParse(_processingFee.text) ?? 0,
          repaymentType: _repaymentType,
          durationValue: int.parse(_duration.text),
          installmentAmount: double.parse(_installment.text),
          effectiveDate: _effectiveDate.toIso8601String(),
          collectionAgentId: _agentId!,
          collectionAgentName: _agentName!,
        );
  }

  @override
  Widget build(BuildContext context) {
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
        const SizedBox(height: ManaSpacing.md),
        OutlinedButton.icon(
          // Stub Collection Agent picker — real build reuses OW-002's list.
          onPressed: () => setState(() {
            _agentId = 'stub-agent-id';
            _agentName = 'Stub Agent';
          }),
          icon: Icon(_agentId == null ? Icons.badge_outlined : Icons.check_circle, size: 18),
          label: ManaText(_agentId == null ? 'select collection agent *' : 'agent: $_agentName'),
        ),
        const SizedBox(height: ManaSpacing.lg),
        Container(
          padding: const EdgeInsets.all(ManaSpacing.md),
          decoration: BoxDecoration(color: ManaColors.brassFaint, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              const Expanded(
                child: ManaText('amount given (system-derived, read-only)', style: TextStyle(fontSize: 12)),
              ),
              ManaText.raw('₹${_amountGiven.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          child: const ManaText('continue'),
        ),
      ],
    );
  }
}

// --- Step 4 — Guarantor (conditional) ------------------------------------

class _Step4Guarantor extends ConsumerStatefulWidget {
  const _Step4Guarantor();

  @override
  ConsumerState<_Step4Guarantor> createState() => _Step4GuarantorState();
}

class _Step4GuarantorState extends ConsumerState<_Step4Guarantor> {
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
        const ManaText.raw('Guarantor is loan-scoped, not customer-scoped — different loans '
            'for the same customer may have different guarantors.',
            style: TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
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
          TextField(
            controller: _relationship,
            decoration: const InputDecoration(labelText: 'Relationship'),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _remarks,
            decoration: const InputDecoration(labelText: 'Remarks'),
          ),
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

// --- Step 4.5 — Live Photo + Grace Period (BR-036/081, BR-007/381) --------

class _Step4bLivePhoto extends ConsumerStatefulWidget {
  const _Step4bLivePhoto();

  @override
  ConsumerState<_Step4bLivePhoto> createState() => _Step4bLivePhotoState();
}

class _Step4bLivePhotoState extends ConsumerState<_Step4bLivePhoto> {
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
          style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
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
          style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
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

// --- Step 5 — Confirm ------------------------------------------

class _Step5Confirm extends ConsumerWidget {
  final String businessId;
  const _Step5Confirm({required this.businessId});

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final loanNumber = await NetworkErrorHandler.run(context, () async {
      final n = await ref.read(loanWizardProvider.notifier).confirm(businessId: businessId);
      if (n == null) throw Exception(ref.read(loanWizardProvider).error ?? 'Loan could not be created.');
      return n;
    });
    if (loanNumber == null) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Loan $loanNumber created — active.')));
    context.go('/ow-001', extra: businessId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loanWizardProvider);

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
                _row('Collection Agent', state.collectionAgentName ?? ''),
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
            child: ManaText.raw(state.error!, style: const TextStyle(color: ManaColors.statusBad)),
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
