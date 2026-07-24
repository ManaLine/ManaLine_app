import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/loan_request_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('d MMM yyyy, h:mm a');

/// CW-003 — Request New Loan. Reached from CW-001 Quick Actions. A Loan
/// Request is its own object (`loan_requests`, §6.5) — it only becomes
/// a real loan via the existing OW-005 New Loan Workflow once
/// Owner/Agent approves; this screen never renders anything resembling
/// that wizard (Live Photo/Agreement/OTP), it only creates the request.
///
/// SPEC GAP (flagged for master chat): CW-003's own PERMISSION section
/// names `businesses.customer_loan_requests_allowed` as a hard
/// server-side gate, but no endpoint is specified for a Customer to
/// read that flag (or `allow_custom_amount`, which STEP 1 also
/// references) ahead of attempting the flow. This screen accepts both
/// as constructor params so CW-001 (or whichever screen owns the
/// Business Membership/Business Settings payload) can pass them
/// through; until that's wired, callers not yet supplying real values
/// should pass `customerLoanRequestsAllowed: false` so the gate fails
/// closed rather than silently defaulting open.
class RequestNewLoanScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String customerId;
  final bool customerLoanRequestsAllowed;
  final bool businessAllowsCustomAmount;

  const RequestNewLoanScreen({
    super.key,
    required this.businessId,
    required this.customerId,
    this.customerLoanRequestsAllowed = false,
    this.businessAllowsCustomAmount = true,
  });

  @override
  ConsumerState<RequestNewLoanScreen> createState() => _RequestNewLoanScreenState();
}

class _RequestNewLoanScreenState extends ConsumerState<RequestNewLoanScreen> {
  final _amountController = TextEditingController();
  final _purposeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(loanRequestProvider.notifier);
      await notifier.loadGateAndTemplates(
        businessId: widget.businessId,
        customerLoanRequestsAllowed: widget.customerLoanRequestsAllowed,
        businessAllowsCustomAmount: widget.businessAllowsCustomAmount,
      );
      if (!mounted) return;
      // Recover cooldown state from the Customer's own request history
      // (S5 24h reapply gate) so re-entering CW-003 after a Reject
      // doesn't let them fill the form again before it lifts.
      final own = await NetworkErrorHandler.run(
        context,
        () => ref.read(loanRequestApiServiceProvider).fetchOwnRequests(customerId: widget.customerId),
      );
      if (own != null && own.isNotEmpty) {
        own.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        ref.read(loanRequestProvider.notifier).applyCooldownIfActive(own.first);
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loanRequestProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('request new loan'),
        leading: BackButton(onPressed: () => context.go('/cw-001', extra: widget.businessId)),
      ),
      body: SafeArea(
        child: switch (state.phase) {
          LoanRequestPhase.gateCheck =>
            const Center(child: CircularProgressIndicator()),
          LoanRequestPhase.notAllowed => _NotAllowedState(businessId: widget.businessId),
          LoanRequestPhase.cooldown => _CooldownState(state: state, businessId: widget.businessId),
          LoanRequestPhase.templateSelection => _TemplateSelectionStep(state: state),
          LoanRequestPhase.requestDetails ||
          LoanRequestPhase.submitting =>
            _RequestDetailsStep(
              state: state,
              amountController: _amountController,
              purposeController: _purposeController,
              businessId: widget.businessId,
            ),
          LoanRequestPhase.pendingReview => _PendingReviewState(businessId: widget.businessId),
          LoanRequestPhase.approved => _ApprovedState(businessId: widget.businessId),
          LoanRequestPhase.rejected => _RejectedState(state: state, businessId: widget.businessId),
        },
      ),
    );
  }
}

// --- Gate: not allowed ----------------------------------------------------

class _NotAllowedState extends StatelessWidget {
  final String businessId;
  const _NotAllowedState({required this.businessId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, size: 48, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('not available for this business',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            const ManaText.raw(
              'This Business does not currently accept Customer-initiated '
              'loan requests. Please speak with the Owner or Agent directly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton(
              onPressed: () => context.go('/cw-001', extra: businessId),
              child: const ManaText('back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Gate: cooldown active --------------------------------------------------

class _CooldownState extends StatelessWidget {
  final LoanRequestState state;
  final String businessId;
  const _CooldownState({required this.state, required this.businessId});

  @override
  Widget build(BuildContext context) {
    final cooldown = state.lastResult?.cooldownUntil;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, size: 48, color: ManaColors.statusWarn),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('resubmission not available yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            if (state.lastResult?.rejectionReason != null) ...[
              ManaText.raw('Previous request rejected: ${state.lastResult!.rejectionReason}',
                  textAlign: TextAlign.center, style: const TextStyle(color: ManaColors.textSecondary)),
              const SizedBox(height: ManaSpacing.sm),
            ],
            ManaText.raw(
              cooldown != null
                  ? 'You may submit a new request to this Business after ${_dateFmt.format(cooldown.toLocal())}.'
                  : 'You may submit a new request to this Business after a 24-hour cooldown.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton(
              onPressed: () => context.go('/cw-001', extra: businessId),
              child: const ManaText('back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- S1 Template Selection --------------------------------------------------

class _TemplateSelectionStep extends ConsumerWidget {
  final LoanRequestState state;
  const _TemplateSelectionStep({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const ManaText('select a loan template', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: ManaSpacing.sm),
        const ManaText.raw(
          'Choose a template, or request a custom amount.',
          style: TextStyle(color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        ...state.templates.map((t) => _TemplateTile(
              template: t,
              selected: state.selectedTemplate?.templateId == t.templateId,
              onTap: () => ref.read(loanRequestProvider.notifier).selectTemplate(t),
            )),
        if (state.businessAllowsCustomAmount) ...[
          const SizedBox(height: ManaSpacing.sm),
          _CustomAmountTile(
            selected: state.requestingCustomAmount,
            onTap: () => ref.read(loanRequestProvider.notifier).selectCustomAmount(),
          ),
        ],
      ],
    );
  }
}

/// Checkmark-ListTile selection pattern — Radio/RadioListTile is
/// deprecated in this SDK version and must not be used anywhere.
class _TemplateTile extends StatelessWidget {
  final LoanTemplateSummary template;
  final bool selected;
  final VoidCallback onTap;
  const _TemplateTile({required this.template, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        leading: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? ManaColors.brass : ManaColors.textSecondary,
        ),
        title: ManaText.raw(template.templateName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: ManaText.raw(
          '${_currency.format(template.defaultAmount)} · ${template.durationValue} × ${template.repaymentFrequency}',
          style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _CustomAmountTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _CustomAmountTile({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? ManaColors.brass : ManaColors.textSecondary,
        ),
        title: const ManaText('request custom amount'),
        subtitle: const ManaText.raw(
          'Not tied to a template — enter your own amount and frequency.',
          style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
        ),
        onTap: onTap,
      ),
    );
  }
}

// --- S2 Request Details ----------------------------------------------------

class _RequestDetailsStep extends ConsumerWidget {
  final LoanRequestState state;
  final TextEditingController amountController;
  final TextEditingController purposeController;
  final String businessId;

  const _RequestDetailsStep({
    required this.state,
    required this.amountController,
    required this.purposeController,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(loanRequestProvider.notifier);
    final submitting = state.phase == LoanRequestPhase.submitting;

    // Keep controllers in sync with a template-driven prefill without
    // fighting user edits — only overwrite when the field is still at
    // the state's own value (i.e. right after selectTemplate ran).
    if (amountController.text != state.requestedAmountText && amountController.text.isEmpty) {
      amountController.text = state.requestedAmountText;
    }

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        if (state.businessOffersTemplates) ...[
          TextButton.icon(
            onPressed: notifier.backToTemplateSelection,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const ManaText('back to template selection'),
          ),
          const SizedBox(height: ManaSpacing.sm),
        ],
        ManaText(
          state.selectedTemplate != null
              ? 'template: ${state.selectedTemplate!.templateName}'
              : 'custom amount request',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: ManaSpacing.lg),
        TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          enabled: state.selectedTemplate == null,
          decoration: const InputDecoration(labelText: 'Requested Amount *', prefixText: '₹ '),
          onChanged: notifier.setRequestedAmount,
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: purposeController,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Purpose (optional)'),
          onChanged: notifier.setPurposeRemark,
        ),
        if (state.requestingCustomAmount) ...[
          const SizedBox(height: ManaSpacing.md),
          const ManaText('preferred repayment frequency', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: ManaSpacing.xs),
          ...['Daily', 'Weekly', 'Monthly'].map((f) => _FrequencyTile(
                label: f,
                selected: state.preferredFrequency == f,
                onTap: () => notifier.setPreferredFrequency(f),
              )),
        ],
        const SizedBox(height: ManaSpacing.lg),
        Card(
          color: ManaColors.surfaceMuted,
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ManaText('review summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: ManaSpacing.sm),
                _SummaryRow(label: 'Amount', value: _currency.format(double.tryParse(state.requestedAmountText) ?? 0)),
                if (state.purposeRemark.trim().isNotEmpty)
                  _SummaryRow(label: 'Purpose', value: state.purposeRemark.trim()),
                _SummaryRow(
                  label: 'Frequency',
                  value: state.selectedTemplate?.repaymentFrequency ?? state.preferredFrequency,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (state.error != null) ...[
          ManaText.raw(state.error!, style: const TextStyle(color: ManaColors.statusBad)),
          const SizedBox(height: ManaSpacing.sm),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (!state.canSubmit || submitting)
                ? null
                : () => NetworkErrorHandler.run(context, () => notifier.submit(businessId: businessId)),
            child: submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const ManaText('submit request'),
          ),
        ),
      ],
    );
  }
}

class _FrequencyTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FrequencyTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: selected ? ManaColors.brass : ManaColors.textSecondary,
        size: 20,
      ),
      title: ManaText(label),
      onTap: onTap,
      dense: true,
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ManaText(label, style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
          Flexible(child: ManaText.raw(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// --- S3 Pending Review -------------------------------------------------------

class _PendingReviewState extends StatelessWidget {
  final String businessId;
  const _PendingReviewState({required this.businessId});

  @override
  Widget build(BuildContext context) {
    return _ResultState(
      icon: Icons.hourglass_top,
      iconColor: ManaColors.statusWarn,
      title: 'request submitted',
      body: 'Status: Pending Owner/Agent Review. You will be notified as soon as they respond.',
      primaryLabel: 'back to dashboard',
      onPrimary: () => context.go('/cw-001', extra: businessId),
    );
  }
}

// --- S4 Approved --------------------------------------------------------------

class _ApprovedState extends StatelessWidget {
  final String businessId;
  const _ApprovedState({required this.businessId});

  @override
  Widget build(BuildContext context) {
    return _ResultState(
      icon: Icons.check_circle,
      iconColor: ManaColors.statusGood,
      title: 'loan approved',
      body: 'Your loan has been created using the standard New Loan Workflow. '
          'It now appears in My Loans.',
      primaryLabel: 'view my loans',
      onPrimary: () => context.go('/cw-004', extra: businessId),
    );
  }
}

// --- S5 Rejected --------------------------------------------------------------

class _RejectedState extends StatelessWidget {
  final LoanRequestState state;
  final String businessId;
  const _RejectedState({required this.state, required this.businessId});

  @override
  Widget build(BuildContext context) {
    final cooldown = state.lastResult?.cooldownUntil;
    return _ResultState(
      icon: Icons.cancel_outlined,
      iconColor: ManaColors.statusBad,
      title: 'request rejected',
      body: [
        if (state.lastResult?.rejectionReason != null) 'Reason: ${state.lastResult!.rejectionReason}',
        cooldown != null
            ? 'You may reapply to this Business after ${_dateFmt.format(cooldown.toLocal())}.'
            : 'You may reapply to this Business after a 24-hour cooldown.',
      ].join('\n\n'),
      primaryLabel: 'back to dashboard',
      onPrimary: () => context.go('/cw-001', extra: businessId),
    );
  }
}

// --- shared result-state layout (mirrors CW-002's own pattern) --------------

class _ResultState extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;

  const _ResultState({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: iconColor),
            const SizedBox(height: ManaSpacing.md),
            ManaText(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(body, textAlign: TextAlign.center, style: const TextStyle(color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton(onPressed: onPrimary, child: ManaText(primaryLabel)),
          ],
        ),
      ),
    );
  }
}
