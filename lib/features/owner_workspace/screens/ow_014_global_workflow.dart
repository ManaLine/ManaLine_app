import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/global_workflow_state.dart';

/// OW-014 — Global Workflow (Pre-Existing Member Creation). All four
/// entry points (OW-001→OW-012, OW-004, OW-002, OW-003) converge on
/// this Step 1-3 wizard. [preSelectedType] pre-fills/skips Step 1 when
/// the entry point already implies the member type — pass null only
/// when arriving from a type-agnostic entry point (none currently do,
/// per spec, but the constructor supports it).
class GlobalWorkflowScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String currentOwnerPersonId; // used as invited_by_person_id
  final MemberType? preSelectedType;

  const GlobalWorkflowScreen({
    super.key,
    required this.businessId,
    required this.currentOwnerPersonId,
    this.preSelectedType,
  });

  @override
  ConsumerState<GlobalWorkflowScreen> createState() => _GlobalWorkflowScreenState();
}

class _GlobalWorkflowScreenState extends ConsumerState<GlobalWorkflowScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(globalWorkflowProvider.notifier).initWithType(widget.preSelectedType);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalWorkflowProvider);

    return Scaffold(
      appBar: AppBar(title: const ManaText('add existing member')),
      body: SafeArea(
        child: switch (state.stage) {
          WizardStage.selectType => _SelectTypeStep(),
          WizardStage.searchMlid => _SearchMlidStep(businessId: widget.businessId),
          WizardStage.found => _FoundStep(businessId: widget.businessId, invitedBy: widget.currentOwnerPersonId),
          WizardStage.notFound => _NotFoundStep(businessId: widget.businessId),
          WizardStage.incomplete => _IncompleteStep(state: state),
          WizardStage.completionInProgress => _IncompleteStep(state: state),
          WizardStage.complete => _IncompleteStep(state: state),
        },
      ),
    );
  }
}

class _SelectTypeStep extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText('select member type', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.md),
        for (final type in MemberType.values)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline, color: ManaColors.brass),
              title: ManaText(type.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ref.read(globalWorkflowProvider.notifier).selectType(type),
            ),
          ),
      ],
    );
  }
}

class _SearchMlidStep extends ConsumerStatefulWidget {
  final String businessId;
  const _SearchMlidStep({required this.businessId});

  @override
  ConsumerState<_SearchMlidStep> createState() => _SearchMlidStepState();
}

class _SearchMlidStepState extends ConsumerState<_SearchMlidStep> {
  final _mobileController = TextEditingController();
  final _mlidController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalWorkflowProvider);

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText('search existing mlid', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        if (state.memberType != null)
          ManaText.raw('Type: ${state.memberType!.label}', style: const TextStyle(color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _mobileController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile Number'),
        ),
        const SizedBox(height: ManaSpacing.sm),
        const ManaText.raw('— OR —', style: TextStyle(color: ManaColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _mlidController,
          decoration: const InputDecoration(labelText: 'MLID'),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: state.searching
              ? null
              : () => ref.read(globalWorkflowProvider.notifier).search(
                    businessId: widget.businessId,
                    mobileNumber: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
                    mlid: _mlidController.text.trim().isEmpty ? null : _mlidController.text.trim(),
                  ),
          child: state.searching
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const ManaText('search'),
        ),
        if (state.error != null) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(state.error!, style: const TextStyle(color: ManaColors.statusBad)),
        ],
      ],
    );
  }
}

class _FoundStep extends ConsumerWidget {
  final String businessId;
  final String invitedBy;
  const _FoundStep({required this.businessId, required this.invitedBy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(globalWorkflowProvider);
    final result = state.searchResult;
    if (result == null) return const Center(child: ManaText.raw('No identity found.'));

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText('identity found', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.md),
        Card(
          child: ListTile(
            leading: const Icon(Icons.check_circle, color: ManaColors.statusGood),
            title: ManaText.raw(result.fullName),
            subtitle: ManaText.raw('MLID: ${result.mlid}${result.mobileNumber != null ? ' · ${result.mobileNumber}' : ''}'),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: state.loading
              ? null
              : () async {
                  await NetworkErrorHandler.run(context, () async {
                    return ref
                        .read(globalWorkflowProvider.notifier)
                        .requestMembership(businessId: businessId, invitedByPersonId: invitedBy);
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Membership requested — Pending Invitation.')),
                    );
                  }
                },
          child: const ManaText('request business membership'),
        ),
      ],
    );
  }
}

class _NotFoundStep extends ConsumerStatefulWidget {
  final String businessId;
  const _NotFoundStep({required this.businessId});

  @override
  ConsumerState<_NotFoundStep> createState() => _NotFoundStepState();
}

class _NotFoundStepState extends ConsumerState<_NotFoundStep> {
  final _fullName = TextEditingController();
  final _fatherHusband = TextEditingController();
  final _village = TextEditingController();
  final _mobile = TextEditingController();
  final _area = TextEditingController();
  final _remarks = TextEditingController();

  bool get _canSave =>
      _fullName.text.trim().isNotEmpty && _fatherHusband.text.trim().isNotEmpty && _village.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalWorkflowProvider);

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText('minimum information', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _fullName,
          decoration: const InputDecoration(labelText: 'Full Name *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _fatherHusband,
          decoration: const InputDecoration(labelText: 'Father / Husband Name *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _village,
          decoration: const InputDecoration(labelText: 'Village *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(controller: _mobile, decoration: const InputDecoration(labelText: 'Mobile Number (optional)')),
        const SizedBox(height: ManaSpacing.sm),
        TextField(controller: _area, decoration: const InputDecoration(labelText: 'Area / Locality (optional)')),
        const SizedBox(height: ManaSpacing.sm),
        TextField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks (optional)'), maxLines: 2),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: !_canSave || state.loading
              ? null
              : () async {
                  final ok = await NetworkErrorHandler.run(context, () async {
                    return ref.read(globalWorkflowProvider.notifier).createPreExistingMember(
                          businessId: widget.businessId,
                          fullName: _fullName.text.trim(),
                          fatherHusbandName: _fatherHusband.text.trim(),
                          village: _village.text.trim(),
                          mobileNumber: _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
                          areaLocality: _area.text.trim().isEmpty ? null : _area.text.trim(),
                          remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
                        );
                  });
                  if (ok == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pre-existing member created — Profile Incomplete.')),
                    );
                  }
                },
          child: state.loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const ManaText('save'),
        ),
      ],
    );
  }
}

class _IncompleteStep extends StatelessWidget {
  final GlobalWorkflowState state;
  const _IncompleteStep({required this.state});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: ManaColors.statusBad, shape: BoxShape.circle),
            ),
            const SizedBox(width: ManaSpacing.sm),
            ManaText('incomplete profile', style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        const SizedBox(height: ManaSpacing.md),
        const ManaText.raw(
          'This member exists as an internal record only, usable for manual/offline collection and '
          'record-keeping. Cannot receive SMS, receive OTP, accept agreements, or request online '
          'services until profile completion.',
          style: TextStyle(color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        Card(
          child: ListTile(
            title: const ManaText('complete profile'),
            subtitle: const ManaText.raw(
              'Capture Photo, Password, Address, PIN Code, Village, Identity Documents, OTP Verification, Terms Acceptance.',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile Completion sub-flow — separate screen, not in this pass\'s scope.')),
              );
            },
          ),
        ),
      ],
    );
  }
}
