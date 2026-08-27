import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_centered_scroll.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/aadhaar_dispute_state.dart';

/// SP-001 — Duplicate-Aadhaar Dispute Resolution.
///
/// STANDALONE SCOPE NOTE (per briefing, flagged again here at the point of
/// use): this is NOT a Customer/Owner/Agent/Investor-facing screen and is
/// deliberately NOT wired into LR-013's role selector, `authFlowProvider`,
/// or any in-app navigation. It is a self-contained internal case-worker
/// tool, reachable only via its own direct route (`/sp-001`). The spec's
/// own RESOLVED section confirms a dedicated Support-tool UI/access-model
/// (real staff auth, permissions) is intentional future work — the check
/// below is a placeholder stub, not real authentication. See END RESULT
/// summary for the integration note to master chat.
///
/// Visual language is deliberately utilitarian (case ID, step indicator,
/// action log) rather than matching the customer-facing workspaces' polish
/// — no verification ring, no business-switcher, no role selector. Design
/// tokens (colors/spacing/typography) are still reused for consistency,
/// per the briefing's "same fidelity/convention" instruction, just applied
/// more plainly.
class Sp001AadhaarDisputeResolutionScreen extends ConsumerStatefulWidget {
  const Sp001AadhaarDisputeResolutionScreen({super.key});

  @override
  ConsumerState<Sp001AadhaarDisputeResolutionScreen> createState() =>
      _Sp001AadhaarDisputeResolutionScreenState();
}

class _Sp001AadhaarDisputeResolutionScreenState
    extends ConsumerState<Sp001AadhaarDisputeResolutionScreen> {
  // Placeholder stub gate only — real Support staff auth is separate future
  // work per the spec's own RESOLVED section. Not a security control.
  bool _staffAcknowledged = false;

  @override
  Widget build(BuildContext context) {
    if (!_staffAcknowledged) {
      return _StaffStubGate(
          onAcknowledge: () => setState(() => _staffAcknowledged = true));
    }
    return const _CaseWorkspace();
  }
}

class _StaffStubGate extends ConsumerWidget {
  final VoidCallback onAcknowledge;
  const _StaffStubGate({required this.onAcknowledge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ManaColors.surfaceMuted,
      body: SafeArea(
        // The gate every step is shown behind, so when it clipped, all seven
        // steps clipped. At 1.3x the Continue button went off the bottom and
        // there is nothing else on this screen to press.
        child: ManaCenteredScroll(
          padding: const EdgeInsets.all(ManaSpacing.xl),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.admin_panel_settings_outlined,
                    size: 40, color: ManaColors.textSecondary),
                const SizedBox(height: ManaSpacing.lg),
                ManaText.raw(
                  'Support / Admin Internal Tool',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ManaColors.textPrimary),
                ),
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(
                  'SP-001 — Duplicate-Aadhaar Dispute Resolution.\n'
                  'Internal case-worker tool. Not part of the Owner/Agent/\n'
                  'Investor/Customer app. Real staff authentication is\n'
                  'separate future work — proceeding here is a stand-in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: ManaColors.textSecondary,
                      height: 1.5),
                ),
                const SizedBox(height: ManaSpacing.xl),
                ElevatedButton(
                  onPressed: onAcknowledge,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: ManaColors.ink,
                      foregroundColor: Colors.white),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: ManaSpacing.lg, vertical: ManaSpacing.sm),
                    child: ManaText.raw(ref.t('continue_as_support_staff')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaseWorkspace extends ConsumerWidget {
  const _CaseWorkspace();

  static const _steps = [
    DisputeStep.caseIntake,
    DisputeStep.secondPersonVerification,
    DisputeStep.suspensionConfirm,
    DisputeStep.originalHolderIntake,
    DisputeStep.originalHolderVerification,
    DisputeStep.resolution,
    DisputeStep.caseClosed,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caseState = ref.watch(aadhaarDisputeCaseProvider);

    return Scaffold(
      backgroundColor: ManaColors.surfaceMuted,
      // Dark chrome marks this as the support workspace rather than a
      // lending one. The bespoke title TextStyle is dropped: the theme's
      // title style is the point of a shared bar, and this screen had no
      // reason to be 1px different from every other.
      appBar: ManaAppBar(
        title: ref.t('aadhaar_dispute_case'),
        backgroundColor: ManaColors.ink,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(currentStep: caseState.step, steps: _steps),
            if (caseState.error != null)
              _InlineErrorBanner(message: caseState.error!),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                child: switch (caseState.step) {
                  DisputeStep.caseIntake => const _CaseIntakeStep(),
                  DisputeStep.secondPersonVerification =>
                    const _ManualVerificationStep(
                      title: 'Manual Verification — Second Person',
                      description:
                          'Human review only. Compare the submitted proof document '
                          'against the claimed Aadhaar number. No automated matching.',
                      isOriginalHolderStep: false,
                    ),
                  DisputeStep.suspensionConfirm =>
                    const _SuspensionConfirmStep(),
                  DisputeStep.originalHolderIntake =>
                    const _OriginalHolderIntakeStep(),
                  DisputeStep.originalHolderVerification =>
                    const _ManualVerificationStep(
                      title: 'Manual Verification — Original Holder',
                      description:
                          'Human review only. Compare the original holder\'s newly '
                          'submitted proof against their corrected Aadhaar number.',
                      isOriginalHolderStep: true,
                    ),
                  DisputeStep.resolution => const _ResolutionStep(),
                  DisputeStep.caseClosed => const _CaseClosedStep(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Step indicator — utilitarian, not the polished workspace styling.
// ============================================================================

class _StepIndicator extends StatelessWidget {
  final DisputeStep currentStep;
  final List<DisputeStep> steps;
  const _StepIndicator({required this.currentStep, required this.steps});

  String _label(DisputeStep step) => switch (step) {
        DisputeStep.caseIntake => 'Intake',
        DisputeStep.secondPersonVerification => 'Verify',
        DisputeStep.suspensionConfirm => 'Suspend',
        DisputeStep.originalHolderIntake => 'Holder Intake',
        DisputeStep.originalHolderVerification => 'Holder Verify',
        DisputeStep.resolution => 'Resolve',
        DisputeStep.caseClosed => 'Closed',
      };

  @override
  Widget build(BuildContext context) {
    final currentIndex = steps.indexOf(currentStep);
    return Container(
      color: ManaColors.surface,
      padding: const EdgeInsets.symmetric(
          horizontal: ManaSpacing.md, vertical: ManaSpacing.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              _StepChip(
                  label: _label(steps[i]),
                  active: i == currentIndex,
                  done: i < currentIndex),
              if (i != steps.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right,
                      size: 16, color: ManaColors.textDisabled),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;
  const _StepChip(
      {required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final color = active
        ? ManaColors.ink
        : (done ? ManaColors.statusGood : ManaColors.textDisabled);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: ManaSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: active ? ManaColors.inkFaint : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ManaText.raw(
        label,
        style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  final String message;
  const _InlineErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ManaColors.statusBadFaint,
      padding: const EdgeInsets.symmetric(
          horizontal: ManaSpacing.lg, vertical: ManaSpacing.sm),
      child: ManaText.raw(message,
          style: ManaType.noteBad),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    // Material, not a decorated Container. The decision tiles inside are
    // ListTiles, and a ListTile paints its ink on the nearest Material
    // ancestor -- with a coloured DecoratedBox in between, the splash went
    // behind the card and the tap looked like it had not registered. On a
    // screen where a case worker is choosing Verified or Not Verified about
    // somebody's identity, silent taps are how the wrong one gets picked.
    //
    // Same paint: colour, radius and border are carried onto the Material's
    // own shape rather than a box drawn over it.
    return Material(
      color: ManaColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: ManaColors.surfaceSunken),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Picks a proof-document image and uploads it to the private
/// `dispute-documents` Storage bucket (0030_module21_sp001_per_row_ops_and_storage.sql
/// — RLS-gated to app.is_platform_admin(), insert+select only). Returns
/// the storage path (bucket-relative), used as `documentUrl` by
/// uploadProofDocument()/submitOriginalHolderResubmission() — this bucket
/// is deliberately non-public, so callers must fetch via a signed URL
/// (createSignedUrl) when displaying the document later, never a bare
/// public URL. Returns null if the person cancels the picker.
Future<String?> _pickAndUploadDisputeDocument(String folderPrefix) async {
  final picked = await ImagePicker()
      .pickImage(source: ImageSource.gallery, imageQuality: 85);
  if (picked == null) return null;

  final bytes = await picked.readAsBytes();
  final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
  final path = '$folderPrefix/${DateTime.now().microsecondsSinceEpoch}.$ext';

  await Supabase.instance.client.storage.from('dispute-documents').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: false),
      );

  return path;
}

// ============================================================================
// Step 1 — Case Intake
// ============================================================================

class _CaseIntakeStep extends ConsumerStatefulWidget {
  const _CaseIntakeStep();

  @override
  ConsumerState<_CaseIntakeStep> createState() => _CaseIntakeStepState();
}

class _CaseIntakeStepState extends ConsumerState<_CaseIntakeStep> {
  final _searchController = TextEditingController();
  String? _attachedDocName;

  @override
  Widget build(BuildContext context) {
    final caseState = ref.watch(aadhaarDisputeCaseProvider);
    final notifier = ref.read(aadhaarDisputeCaseProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('step_1_case_intake'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          'Look up the existing account by MLID or Aadhaar, then attach the '
          'second person\'s submitted proof document.',
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(ref.t('search_by_mlid_aadhaar'),
                  style: ManaType.smallStrong),
              const SizedBox(height: ManaSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        hintText: ref.t('search_by_mlid_aadhaar'),
                      ),
                      onChanged: notifier.setSearchInput,
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  ElevatedButton(
                    onPressed: caseState.looking
                        ? null
                        : () => notifier.lookupExistingAccount(),
                    child: caseState.looking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : ManaText.raw(ref.t('look_up')),
                  ),
                ],
              ),
              if (caseState.existingAccount != null) ...[
                const SizedBox(height: ManaSpacing.md),
                Container(
                  padding: const EdgeInsets.all(ManaSpacing.sm),
                  decoration: BoxDecoration(
                      color: ManaColors.inkFaint,
                      borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(
                          'Existing MLID: ${caseState.existingAccount!.currentMlid}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      ManaText.raw(
                          'Account Holder: ${caseState.existingAccount!.fullName}',
                          style: TextStyle(
                              fontSize: 13, color: ManaColors.textSecondary)),
                      const SizedBox(height: 4),
                      ManaText.raw(
                        'Visible to Support only — never shown to the registrant.',
                        style: TextStyle(
                            fontSize: 13,
                            color: ManaColors.textDisabled,
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ManaText.raw('Second Person\'s Proof Document',
                  style: ManaType.smallStrong),
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton.icon(
                onPressed: () async {
                  final result =
                      await NetworkErrorHandler.run(context, () async {
                    final documentUrl = await _pickAndUploadDisputeDocument(
                        'second_person_proof');
                    if (documentUrl == null) {
                      return null; // person cancelled the picker
                    }
                    await notifier.uploadSecondPersonProof(documentUrl);
                    return documentUrl;
                  });
                  if (result != null) {
                    if (!mounted) return;
                    setState(() => _attachedDocName = result.split('/').last);
                  }
                },
                icon: const Icon(Icons.upload_file, size: 18),
                label:
                    ManaText.raw(_attachedDocName ?? 'Attach Proof Document'),
              ),
            ],
          ),
        ),
        const SizedBox(height: ManaSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: caseState.canProceedFromIntake
                ? notifier.goToSecondPersonVerification
                : null,
            style: ElevatedButton.styleFrom(backgroundColor: ManaColors.accent),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
              child: ManaText.raw(ref.t('proceed_to_manual_verification')),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// ============================================================================
// Step 2 / Step 4b — Manual Verification (shared widget, human-only decision)
// ============================================================================

class _ManualVerificationStep extends ConsumerWidget {
  final String title;
  final String description;
  final bool isOriginalHolderStep;
  const _ManualVerificationStep({
    required this.title,
    required this.description,
    required this.isOriginalHolderStep,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caseState = ref.watch(aadhaarDisputeCaseProvider);
    final notifier = ref.read(aadhaarDisputeCaseProvider.notifier);
    final decision = isOriginalHolderStep
        ? caseState.originalHolderDecision
        : caseState.secondPersonDecision;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(description,
            style:
                ManaType.note),
        const SizedBox(height: ManaSpacing.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(ref.t('decision'),
                  style: ManaType.smallStrong),
              const SizedBox(height: ManaSpacing.sm),
              _DecisionTile(
                label: ref.t('verified'),
                selected: decision == ManualVerificationDecision.verified,
                onTap: () => isOriginalHolderStep
                    ? notifier.setOriginalHolderDecision(
                        ManualVerificationDecision.verified)
                    : notifier.setSecondPersonDecision(
                        ManualVerificationDecision.verified),
              ),
              _DecisionTile(
                label: ref.t('not_verified'),
                selected: decision == ManualVerificationDecision.notVerified,
                onTap: () => isOriginalHolderStep
                    ? notifier.setOriginalHolderDecision(
                        ManualVerificationDecision.notVerified)
                    : notifier.setSecondPersonDecision(
                        ManualVerificationDecision.notVerified),
              ),
            ],
          ),
        ),
        if (decision == ManualVerificationDecision.notVerified) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(
            'Marked Not Verified. Case stays open at this step until '
            'genuine proof is submitted — no automatic escalation or timeout.',
            style: ManaType.noteWarn,
          ),
        ],
        const SizedBox(height: ManaSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: decision == ManualVerificationDecision.verified
                ? () => isOriginalHolderStep
                    ? notifier.resolveCase()
                    : notifier.proceedToSuspensionSummary()
                : null,
            style: ElevatedButton.styleFrom(backgroundColor: ManaColors.accent),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
              child: caseState.resolving || caseState.loadingSuspensionImpact
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : ManaText.raw(isOriginalHolderStep
                      ? 'Continue to Resolution'
                      : 'Continue to Suspension Review'),
            ),
          ),
        ),
      ],
    );
  }
}

class _DecisionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DecisionTile(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // checkmark-ListTile selection pattern — Radio/RadioListTile are
    // deprecated in this SDK version, per project convention.
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: selected ? ManaColors.brand : ManaColors.textSecondary,
      ),
      title: ManaText(label),
      onTap: onTap,
      dense: true,
    );
  }
}

// ============================================================================
// Step 3 — Suspension summary + explicit confirm (serious, wide-reaching)
// ============================================================================

class _SuspensionConfirmStep extends ConsumerWidget {
  const _SuspensionConfirmStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caseState = ref.watch(aadhaarDisputeCaseProvider);
    final notifier = ref.read(aadhaarDisputeCaseProvider.notifier);
    final rows = caseState.suspensionImpact?.rows ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('step_3_suspend_original'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          'Second person verified. Review the impact below before confirming — '
          'this suspends the original account\'s business(es) where they hold '
          'Owner, and their memberships elsewhere. This does not suspend '
          'businesses they don\'t own.',
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (caseState.loadingSuspensionImpact)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(ManaSpacing.xl),
                  child: CircularProgressIndicator()))
        else if (rows.isEmpty)
          _SectionCard(
              child: ManaText.raw(ref.t('no_impact_rows'),
                  style:
                      ManaType.note))
        else
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(ref.t('will_be_suspended'),
                    style:
                        ManaType.smallStrong),
                const SizedBox(height: ManaSpacing.sm),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ManaSpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                          row.isOwnerBusiness
                              ? Icons.storefront_outlined
                              : Icons.badge_outlined,
                          size: 18,
                          color: ManaColors.statusBad,
                        ),
                        const SizedBox(width: ManaSpacing.sm),
                        Expanded(
                          child: ManaText.raw(
                            row.isOwnerBusiness
                                ? '${row.label} — entire business suspended (Owner)'
                                : '${row.label} — membership suspended (${row.role})',
                            style: ManaType.small,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: ManaSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: rows.isEmpty || caseState.suspending
                ? null
                : () => notifier.confirmSuspension(),
            style:
                ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
              child: caseState.suspending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : ManaText.raw(ref.t('confirm_suspension'),
                      style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Step 4a — Original Holder Intake (corrected Aadhaar + proof)
// ============================================================================

class _OriginalHolderIntakeStep extends ConsumerStatefulWidget {
  const _OriginalHolderIntakeStep();

  @override
  ConsumerState<_OriginalHolderIntakeStep> createState() =>
      _OriginalHolderIntakeStepState();
}

class _OriginalHolderIntakeStepState
    extends ConsumerState<_OriginalHolderIntakeStep> {
  final _aadhaarController = TextEditingController();
  String? _attachedDocName;
  String? _attachedDocUrl;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(aadhaarDisputeCaseProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('step_4_reverification'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          'Original account holder has been notified and asked to submit '
          'their own correct Aadhaar and proof to Support.',
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(ref.t('corrected_aadhaar_number'),
                  style: ManaType.smallStrong),
              const SizedBox(height: ManaSpacing.sm),
              TextField(
                controller: _aadhaarController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: ManaSpacing.lg),
              ManaText.raw(ref.t('proof_document'),
                  style: ManaType.smallStrong),
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton.icon(
                onPressed: () async {
                  final result =
                      await NetworkErrorHandler.run(context, () async {
                    return _pickAndUploadDisputeDocument(
                        'original_holder_proof');
                  });
                  if (result != null) {
                    if (!mounted) return;
                    setState(() {
                      _attachedDocUrl = result;
                      _attachedDocName = result.split('/').last;
                    });
                  }
                },
                icon: const Icon(Icons.upload_file, size: 18),
                label:
                    ManaText.raw(_attachedDocName ?? 'Attach Proof Document'),
              ),
            ],
          ),
        ),
        const SizedBox(height: ManaSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _aadhaarController.text.trim().isNotEmpty &&
                    _attachedDocUrl != null
                ? () => NetworkErrorHandler.run(context, () async {
                      return notifier.submitOriginalHolderResubmission(
                        correctedAadhaar: _aadhaarController.text.trim(),
                        documentUrl: _attachedDocUrl!,
                      );
                    })
                : null,
            style: ElevatedButton.styleFrom(backgroundColor: ManaColors.accent),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
              child: ManaText.raw(ref.t('proceed_to_manual_verification')),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _aadhaarController.dispose();
    super.dispose();
  }
}

// ============================================================================
// Step 5 handled inline via _ManualVerificationStep(isOriginalHolderStep:
// true)'s Continue button, which calls resolveCase() directly — the spec
// calls for "one button that triggers, together" unblock + unsuspend +
// upgrade-mlid, matching a single Support action rather than a separate
// confirmation screen. This placeholder step exists for switch-exhaustiveness
// and shows a brief in-flight state if reached directly.
// ============================================================================

class _ResolutionStep extends ConsumerWidget {
  const _ResolutionStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _SectionCard(
      child: Padding(
        padding: EdgeInsets.all(ManaSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

// ============================================================================
// Step 6 — Case Closed
// ============================================================================

class _CaseClosedStep extends ConsumerWidget {
  const _CaseClosedStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caseState = ref.watch(aadhaarDisputeCaseProvider);
    final notifier = ref.read(aadhaarDisputeCaseProvider.notifier);
    final history = caseState.idHistoryEntry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: ManaColors.statusGood),
            const SizedBox(width: ManaSpacing.sm),
            // Expanded: the heading is a translated sentence beside a fixed
            // icon, which ran 127px past the edge in English and 387px in
            // Telugu -- at 1.0x, before any scaling.
            Expanded(
              child: ManaText.raw(ref.t('case_resolved_slot_freed'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: ManaSpacing.md),
        ManaText.raw(
          'Original holder unblocked, business(es)/memberships unsuspended, '
          'and the MLID correction is complete. person_id never changed — '
          'every historical loan, investment, and membership stays correctly '
          'attributed automatically. Nothing to manually reattach.',
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (history != null)
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(ref.t('mlid_correction_record'),
                    style:
                        ManaType.smallStrong),
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(ref.t('old_mlid_note').replaceAll('{mlid}', history.oldMlid),
                    style: ManaType.small),
                ManaText.raw(ref.t('new_mlid_note').replaceAll('{mlid}', history.newMlid),
                    style: ManaType.small),
                ManaText.raw(ref.t('reason_note').replaceAll('{reason}', history.reason),
                    style: TextStyle(
                        fontSize: 13, color: ManaColors.textSecondary)),
              ],
            ),
          ),
        const SizedBox(height: ManaSpacing.lg),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(ref.t('next_step'),
                  style: ManaType.smallStrong),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                'The disputed MLID slot is now free. The second person\'s real '
                'registration can proceed — either Support completes it '
                'separately, or hands back to self-service.',
                style: ManaType.note,
              ),
            ],
          ),
        ),
        const SizedBox(height: ManaSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: notifier.startNewCase,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
              child: ManaText.raw(ref.t('start_new_case')),
            ),
          ),
        ),
      ],
    );
  }
}
