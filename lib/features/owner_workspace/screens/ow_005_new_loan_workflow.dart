import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_label_value_row.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/live_face_capture_screen.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/bf_request_card.dart';
import '../../../shared/loan_customer_search.dart';
import '../state/loan_wizard_state.dart';
import '../state/owner_api_service.dart';
import '../state/owner_workspace_state.dart';

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
      if (!mounted) return;
      ref.read(loanWizardProvider.notifier).reset();
      // BUG FIXED this pass: prefilledCustomerId was declared but never
      // actually read anywhere — every entry point that passed one (e.g.
      // this Loan Requests approval flow) silently landed on the plain
      // empty Step 1 search instead of the intended customer.
      if (widget.prefilledCustomerId != null) {
        // Guarded on both sides of the await. This is the only postFrame
        // callback in lib/ that touches ref AFTER an await -- the other
        // thirty run entirely within the frame that scheduled them, where
        // the widget cannot have gone. Here it can: selectCustomerById is a
        // round trip, and backing out of Issue Loan while it is in flight
        // threw "Cannot use ref after the widget was disposed".
        if (!mounted) return;
        await ref.read(loanWizardProvider.notifier).selectCustomerById(
              customerId: widget.prefilledCustomerId!,
              sourceRequestId: widget.sourceRequestId,
            );
      }
    });
  }

  // No dispose-time reset. `ref.read()` inside dispose() is forbidden by
  // Riverpod -- it threw "Cannot use \"ref\" after the widget was disposed"
  // every single time somebody left this wizard, so the reset it looked like
  // it was doing has never once happened. The guarantee it was reaching for
  // is already met on the way IN: initState resets before the first frame, so a fresh wizard
  // starts empty regardless of how the last one ended.


  static const _steps = LoanWizardStep.values;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loanWizardProvider);
    final stepIndex = _steps.indexOf(state.step);

    return Scaffold(
      appBar: ManaAppBar(
        homeRoute: '/ow-001',
        title: ref.t('new_loan'),
        // The two things an Owner reaches for from inside a loan.
        //
        // Both were tiles on the Home dashboard, which meant backing out of a
        // half-started loan to reach them -- and this wizard resets on exit,
        // so backing out costs everything typed so far. Registering a
        // customer in particular is the one that comes up mid-loan: the
        // borrower is standing there and is not on the book yet.
        //
        // Same pattern Workforce Management already uses for its own add
        // paths, which is why those were taken off the dashboard too.
        actions: [
          IconButton(
            tooltip: ref.t('register_customer'),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () =>
                context.push('/ow-004?action=register', extra: widget.businessId),
          ),
          IconButton(
            tooltip: ref.t('group_loans'),
            icon: const Icon(Icons.groups_2_outlined),
            onPressed: () => context.push('/ow-015', extra: widget.businessId),
          ),
        ],
      ),
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
        return _Step3LoanDetails(businessId: widget.businessId);
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
              style: ManaType.note),
        ],
      ),
    );
  }
}

// --- Step 1 — Customer Selection --------------------------------------

/// Step 1 is ManaLoanCustomerSearch, shared with AG-007.
///
/// This screen and the Agent's each carried their own copy, and the copies
/// drifted until the Agent's stopped working. One widget now; the role decides
/// only what it OFFERS, never what gets written -- the server decides that
/// from the caller's own membership.
class _Step1CustomerSelection extends ConsumerWidget {
  final String businessId;
  const _Step1CustomerSelection({required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaLoanCustomerSearch(
      businessId: businessId,
      // The Owner may always bring somebody onto their own book.
      canAddCustomer: true,
      onSelected: (c) => ref.read(loanWizardProvider.notifier).selectCustomer(c),
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
            style: ManaType.secondary),
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
                          // Expanded, because an eligibility reason is a
                          // sentence, not a word -- and it is longer in every
                          // language other than English.
                          Expanded(child: ManaText.raw(c.$1, style: ManaType.small)),
                        ],
                      ),
                    )),
                ..._deferredCheckKeys.map((key) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, size: 16, color: ManaColors.textSecondary),
                          const SizedBox(width: ManaSpacing.sm),
                          Expanded(flex: 3, child: ManaText.raw(ref.t(key), style: ManaType.small)),
                          const SizedBox(width: ManaSpacing.xs),
                          // "At Confirm" was bare beside a flexible label, so
                          // the label yielded and this ran off the edge.
                          Flexible(
                            child: ManaText.raw(ref.t('at_confirm'),
                                style: ManaType.note, textAlign: TextAlign.right),
                          ),
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
            style: ManaType.small,
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
  final String businessId;
  const _Step3LoanDetails({required this.businessId});

  @override
  ConsumerState<_Step3LoanDetails> createState() => _Step3LoanDetailsState();
}

class _Step3LoanDetailsState extends ConsumerState<_Step3LoanDetails> {

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

  /// The real workforce list, not a stub. `_agentId` is the agent's
  /// MEMBERSHIP id, not `agents.agent_id` — that is what reaches
  /// `loans.collection_agent_membership_id`, and the two are different columns
  /// on different tables.
  Future<void> _pickAgent() async {
    final notifier = ref.read(workforceProvider.notifier);
    if (ref.read(workforceProvider).agents.isEmpty) {
      await notifier.load(widget.businessId);
    }
    if (!mounted) return;

    final agents = [
      for (final a in ref.read(workforceProvider).agents)
        if (a.status == 'Active' && a.membershipId != null) a,
    ];

    if (agents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('no_active_agents_note'))),
      );
      return;
    }

    final chosen = await showModalBottomSheet<AgentSummary>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(ManaSpacing.md),
              child: ManaText.raw(ref.t('select_collection_agent_field'),
                  style: ManaType.heavy),
            ),
            for (final a in agents)
              ListTile(
                title: ManaText.raw(a.fullName),
                subtitle: ManaText.raw(a.mlid),
                onTap: () => Navigator.of(c).pop(a),
              ),
          ],
        ),
      ),
    );

    if (chosen != null && mounted) {
      setState(() {
        _agentId = chosen.membershipId;
        _agentName = chosen.fullName;
      });
    }
  }

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
          // isExpanded: a DropdownButton sizes to its widest item and
          // overflows rather than shrinking -- measured at 1.0x on OW-002.
          isExpanded: true,
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
              // Bounds off the same IST clock as the default above — mixing
              // the two can put initialDate outside [firstDate, lastDate].
              firstDate: manaNowIst().subtract(const Duration(days: 1)),
              lastDate: manaNowIst().add(const Duration(days: 365)),
            );
            if (!mounted) return;
            if (picked != null) setState(() => _effectiveDate = picked);
          },
        ),
        const SizedBox(height: ManaSpacing.md),
        OutlinedButton.icon(
          onPressed: _pickAgent,
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
                child: ManaText.raw(ref.t('amount_given_readonly_note'), style: ManaType.small),
              ),
              ManaText.raw('₹$_amountGiven',
                  style: ManaType.cardTitle),
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
        ManaText.raw(ref.t('guarantor_scope_note'),
            style: ManaType.note),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(ref.t('need_guarantor'), style: ManaType.emphasis),
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
          style: ManaType.note,
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
        ManaText.raw(ref.t('grace_period_days_label'), style: ManaType.emphasis),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('grace_period_internal_note'),
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
                ManaLabelValueRow(dense: true, label: ref.t('customer'), value: state.customer?.fullName ?? ''),
                ManaLabelValueRow(dense: true, label: ref.t('repayment_amount_field'), value: '₹${state.repaymentAmount ?? 0}'),
                ManaLabelValueRow(dense: true, label: ref.t('interest'), value: '₹${state.interest ?? 0}'),
                ManaLabelValueRow(dense: true, label: ref.t('processing_fee'), value: '₹${state.processingFee ?? 0}'),
                ManaLabelValueRow(dense: true, label: ref.t('amount_given'), value: '₹${state.amountGiven}'),
                ManaLabelValueRow(dense: true, label: ref.t('repayment_type_field'), value: state.repaymentType),
                ManaLabelValueRow(dense: true, label: ref.t('duration'), value: ref.t('duration_note').replaceAll('{count}', '${state.durationValue ?? 0}')),
                ManaLabelValueRow(dense: true, label: ref.t('installment'), value: '₹${state.installmentAmount ?? 0}'),
                ManaLabelValueRow(dense: true, label: ref.t('collection_agent'), value: state.collectionAgentName ?? ''),
                ManaLabelValueRow(dense: true, label: ref.t('guarantor'), value: state.needsGuarantor ? (state.guarantorName ?? '') : ref.t('none')),
              ],
            ),
          ),
        ),
        // A float refusal is not the same kind of failure as a bad figure, so
        // it does not get the same red box. Nothing here is wrong -- the till
        // is empty -- and what the Agent needs is a way to ask, not a warning.
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
