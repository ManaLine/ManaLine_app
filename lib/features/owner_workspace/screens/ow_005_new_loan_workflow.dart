import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/live_face_capture_screen.dart';
import '../../../shared/translation_service.dart';
import '../state/customer_state.dart';
import '../state/loan_wizard_state.dart';

/// OW-005 — New Loan Workflow. 6-step wizard: Customer Selection →
/// Eligibility Check → Loan Details → Guarantor (conditional) → Live Photo
/// (BR-036/081, mandatory) → Confirm. No draft persistence (per spec,
/// distinct from OW-000) — exiting mid-flow resets progress.
class NewLoanWorkflowScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String? prefilledCustomerId;
  // Set when reached from a Loan Requests approval — see loan_wizard_
  // state.dart's confirm() for how this resolves the originating request.
  final String? sourceRequestId;
  const NewLoanWorkflowScreen({
    super.key,
    required this.businessId,
    this.prefilledCustomerId,
    this.sourceRequestId,
  });

  @override
  ConsumerState<NewLoanWorkflowScreen> createState() => _NewLoanWorkflowScreenState();
}

class _NewLoanWorkflowScreenState extends ConsumerState<NewLoanWorkflowScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(loanWizardProvider.notifier).reset();
      // BUG FIXED this pass: prefilledCustomerId was declared but never
      // actually read anywhere — every entry point that passed one (e.g.
      // this Loan Requests approval flow) silently landed on the plain
      // empty Step 1 search instead of the intended customer.
      if (widget.prefilledCustomerId != null) {
        await ref.read(loanWizardProvider.notifier).selectCustomerById(
              customerId: widget.prefilledCustomerId!,
              sourceRequestId: widget.sourceRequestId,
            );
      }
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
      appBar: AppBar(title: ManaText.raw(ref.t('new_loan'))),
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

class _StepIndicator extends ConsumerWidget {
  final int current;
  final int total;
  const _StepIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                color: ManaColors.brand,
              ),
            ),
          ),
          const SizedBox(width: ManaSpacing.md),
          ManaText.raw(
              ref.t('step_of_note').replaceAll('{current}', '$current').replaceAll('{total}', '$total'),
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
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
  /// >1 match for the typed name. Shown as a prompt to narrow the search
  /// rather than silently picking one.
  int _ambiguousCount = 0;
  bool _searching = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    // Same fix as OW-004's Add Customer search: this box was always sent
    // as `fullName:` regardless of what was typed, so an MLID search
    // (e.g. "MLPI100000014") queried full_name ILIKE '%MLPI100000014%'
    // and never matched, even for a customer who genuinely exists.
    // Classify by shape and route to the matching owner_search_person()
    // param instead. (Village is not a supported search dimension on
    // that RPC at all — the label overpromises there; out of scope here.)
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
      // searchIdentity returns EVERY match now (a name is not unique).
      // These two screens pick a single customer for a loan, so an
      // ambiguous name search deliberately selects nothing rather than
      // guessing — issuing a loan against the wrong person of the same
      // name is the failure that matters here.
      final matches = result ?? const <CustomerSummary>[];
      _found = matches.length == 1 ? matches.first : null;
      _ambiguousCount = matches.length > 1 ? matches.length : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('select_customer'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(ref.t('search_customer_note'),
            style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                decoration: InputDecoration(labelText: ref.t('search')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            ElevatedButton(
              onPressed: (_query.text.trim().isNotEmpty && !_searching) ? _search : null,
              child: _searching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('search')),
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
                child: ManaText.raw(ref.t('select')),
              ),
            ),
          )
        // Several people share the typed name. Say so and make them narrow
        // it — picking one for the Owner is how a loan lands on the wrong
        // person of the same name.
        else if (_ambiguousCount > 0 && !_searching)
          ManaText.raw(
            '$_ambiguousCount people match that name. Search by MANA LINE ID, '
            'Aadhaar or mobile number to pick the right one.',
            style: TextStyle(fontSize: 13, color: ManaColors.statusWarn),
          )
        else if (_query.text.trim().isNotEmpty && !_searching)
          ManaText.raw(ref.t('no_matching_customer_note'),
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
      ],
    );
  }
}

// --- Step 2 — Eligibility Check ------------------------------------------

class _Step2Eligibility extends ConsumerWidget {
  const _Step2Eligibility();

  // BUG FIXED this pass: every one of these 9 checks previously rendered
  // a hardcoded green checkmark regardless of the actual customer, and
  // "continue" unconditionally called markEligibilityPassed() — showing
  // a real Owner a row of authoritative-looking passes that were never
  // actually evaluated. The 4 checks below ARE answerable from data this
  // screen already has (state.customer, loaded in Step 1) and now show
  // their REAL result; the remaining 5 genuinely require server-side
  // Calculation Engine / cross-loan state this screen doesn't have, so
  // — same honest treatment already used for BF Cash Validation right
  // below this list — they're shown as deferred-to-confirm-time, not
  // faked as already-passed.
  static const _deferredCheckKeys = [
    'no_duplicate_loan',
    'no_owner_restrictions',
    'no_pending_approval',
    'outstanding_rules',
    'line_repayment_index',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loanWizardProvider);
    final customer = state.customer;
    final customerActive = customer?.customerStatus == 'Active';
    final notBlocked = customer?.membershipStatus == 'Active';
    final realChecks = <(String, bool)>[
      (ref.t('customer_exists'), customer != null),
      (ref.t('business_linked'), customer != null),
      (ref.t('customer_active'), customerActive),
      (ref.t('not_blocked'), notBlocked),
    ];
    final allRealChecksPassed = realChecks.every((c) => c.$2);

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('eligibility_check'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(ref.t('customer_label_note').replaceAll('{name}', customer?.fullName ?? ''),
            style: TextStyle(color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Column(
              children: [
                ...realChecks.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(c.$2 ? Icons.check_circle : Icons.cancel,
                              size: 16, color: c.$2 ? ManaColors.statusGood : ManaColors.statusBad),
                          const SizedBox(width: ManaSpacing.sm),
                          ManaText.raw(c.$1, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    )),
                ..._deferredCheckKeys.map((key) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, size: 16, color: ManaColors.textSecondary),
                          const SizedBox(width: ManaSpacing.sm),
                          Expanded(child: ManaText.raw(ref.t(key), style: const TextStyle(fontSize: 13))),
                          ManaText.raw(ref.t('at_confirm'),
                              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
        const SizedBox(height: ManaSpacing.md),
        Container(
          padding: const EdgeInsets.all(ManaSpacing.md),
          decoration: BoxDecoration(color: ManaColors.statusWarnFaint, borderRadius: BorderRadius.circular(8)),
          child: ManaText.raw(
            ref.t('bf_cash_validation_note'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (state.eligibilityFailureReason != null) ...[
          const SizedBox(height: ManaSpacing.md),
          Container(
            padding: const EdgeInsets.all(ManaSpacing.md),
            decoration: BoxDecoration(color: ManaColors.statusBadFaint, borderRadius: BorderRadius.circular(8)),
            child: ManaText.raw(state.eligibilityFailureReason!,
                style: TextStyle(color: ManaColors.statusBad, fontSize: 13)),
          ),
        ],
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: () {
            if (allRealChecksPassed) {
              ref.read(loanWizardProvider.notifier).markEligibilityPassed();
            } else {
              final failed = realChecks.where((c) => !c.$2).map((c) => c.$1).join(', ');
              ref.read(loanWizardProvider.notifier).markEligibilityFailed('Failed: $failed');
            }
          },
          child: ManaText.raw(ref.t('continue_button')),
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

  // Whole rupees (M8) — the server stores money as DECIMAL(14,0).
  int get _amountGiven =>
      (int.tryParse(_repaymentAmount.text) ?? 0) -
      (int.tryParse(_interest.text) ?? 0) -
      (int.tryParse(_processingFee.text) ?? 0);

  bool get _canSubmit =>
      (int.tryParse(_repaymentAmount.text) ?? 0) > 0 &&
      (int.tryParse(_duration.text) ?? 0) > 0 &&
      (int.tryParse(_installment.text) ?? 0) > 0 &&
      _agentId != null;

  void _submit() {
    ref.read(loanWizardProvider.notifier).setLoanDetails(
          repaymentAmount: int.parse(_repaymentAmount.text),
          interest: int.tryParse(_interest.text) ?? 0,
          processingFee: int.tryParse(_processingFee.text) ?? 0,
          repaymentType: _repaymentType,
          durationValue: int.parse(_duration.text),
          installmentAmount: int.parse(_installment.text),
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
        ManaText.raw(ref.t('loan_details'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.lg),
        TextField(
          controller: _repaymentAmount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('repayment_amount_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _interest,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('interest')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _processingFee,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('processing_fee')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _repaymentType,
          decoration: InputDecoration(labelText: ref.t('repayment_type_field')),
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
          decoration: InputDecoration(labelText: ref.t('installment_amount_field')),
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
          label: ManaText.raw(
              _agentId == null ? ref.t('select_collection_agent_field') : ref.t('agent_note').replaceAll('{name}', _agentName ?? '')),
        ),
        const SizedBox(height: ManaSpacing.lg),
        Container(
          padding: const EdgeInsets.all(ManaSpacing.md),
          decoration: BoxDecoration(color: ManaColors.brandFaint, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Expanded(
                child: ManaText.raw(ref.t('amount_given_readonly_note'), style: const TextStyle(fontSize: 13)),
              ),
              ManaText.raw('₹$_amountGiven',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          child: ManaText.raw(ref.t('continue_button')),
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
        ManaText.raw(ref.t('guarantor'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(ref.t('guarantor_scope_note'),
            style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(ref.t('need_guarantor'), style: const TextStyle(fontWeight: FontWeight.w600)),
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
          TextField(
            controller: _relationship,
            decoration: InputDecoration(labelText: ref.t('relationship')),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: ref.t('phone_number')),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _address,
            decoration: InputDecoration(labelText: ref.t('address')),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _remarks,
            decoration: InputDecoration(labelText: ref.t('remarks')),
          ),
        ],
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: (_needsGuarantor != null && _canSubmit) ? _submit : null,
          child: ManaText.raw(ref.t('continue_button')),
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
        ManaText.raw(ref.t('live_photo'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('live_photo_mandatory_note'),
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (state.livePhotoBytes == null)
          OutlinedButton.icon(
            onPressed: _capture,
            icon: const Icon(Icons.camera_alt),
            label: ManaText.raw(ref.t('capture_live_photo_field')),
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
        ManaText.raw(ref.t('grace_period_days_label'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('grace_period_internal_note'),
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
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
          child: ManaText.raw(ref.t('continue_button')),
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
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('loan_created_note').replaceAll('{number}', loanNumber))));
    context.go('/ow-001', extra: businessId);
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
                _row(ref.t('customer'), state.customer?.fullName ?? ''),
                _row(ref.t('repayment_amount_field'), '₹${state.repaymentAmount ?? 0}'),
                _row(ref.t('interest'), '₹${state.interest ?? 0}'),
                _row(ref.t('processing_fee'), '₹${state.processingFee ?? 0}'),
                _row(ref.t('amount_given'), '₹${state.amountGiven}'),
                _row(ref.t('repayment_type_field'), state.repaymentType),
                _row(ref.t('duration'), ref.t('duration_note').replaceAll('{count}', '${state.durationValue ?? 0}')),
                _row(ref.t('installment'), '₹${state.installmentAmount ?? 0}'),
                _row(ref.t('collection_agent'), state.collectionAgentName ?? ''),
                _row(ref.t('guarantor'), state.needsGuarantor ? (state.guarantorName ?? '') : ref.t('none')),
              ],
            ),
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: ManaSpacing.md),
          Container(
            padding: const EdgeInsets.all(ManaSpacing.md),
            decoration: BoxDecoration(color: ManaColors.statusBadFaint, borderRadius: BorderRadius.circular(8)),
            child: ManaText.raw(state.error!, style: TextStyle(color: ManaColors.statusBad)),
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

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: ManaText.raw(label, style: TextStyle(color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}
