import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
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
      appBar: AppBar(title: ManaText.raw(ref.t('add_existing_member'))),
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
        ManaText.raw(ref.t('select_member_type'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.md),
        for (final type in MemberType.values)
          Card(
            child: ListTile(
              leading: Icon(Icons.person_outline, color: ManaColors.brand),
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
        ManaText.raw(ref.t('search_existing_mlid'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        if (state.memberType != null)
          ManaText.raw(ref.t('type_note').replaceAll('{type}', state.memberType!.label),
              style: TextStyle(color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _mobileController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: ref.t('mobile_number_field')),
        ),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(ref.t('or_separator'), style: TextStyle(color: ManaColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _mlidController,
          decoration: InputDecoration(labelText: ref.t('mlid_field')),
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
              : ManaText.raw(ref.t('search')),
        ),
        if (state.error != null) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(state.error!, style: TextStyle(color: ManaColors.statusBad)),
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
    if (result == null) return Center(child: ManaText.raw(ref.t('no_identity_found')));

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('identity_found'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.md),
        Card(
          child: ListTile(
            leading: Icon(Icons.check_circle, color: ManaColors.statusGood),
            title: ManaText.raw(result.fullName),
            subtitle: ManaText.raw(ref.t('mlid_colon_note').replaceAll('{mlid}', result.mlid) +
                (result.mobileNumber != null ? ' · ${result.mobileNumber}' : '')),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        // The action depends on WHO is being added, and it used to not.
        //
        // This screen is shared by OW-002 (agent), OW-003 (investor) and
        // OW-004 (customer) via /ow-014?type=..., but it hardcoded
        // requestMembership for all three — so an Owner adding a customer
        // standing at the counter was told "Request Business Membership" and
        // got a membership_requests row nobody would ever approve. The direct
        // path (addExistingCustomer / addExistingAgent, onboarding_method
        // 'ID Lookup') already existed and was simply never called from here.
        //
        // Customer and agent: added directly by the Owner, who is with them.
        // Investor: stays request-based — that relationship is
        // investor-initiated by design (IW-002 writes the request, the Owner
        // accepts), and money is being taken in rather than lent out.
        _AddMemberButton(
          businessId: businessId,
          invitedBy: invitedBy,
          personName: result.fullName,
          mlid: result.mlid,
        ),
      ],
    );
  }
}

/// The found-step action, chosen by member type.
///
/// Customer and agent are added directly; investor sends a request. Split out
/// so the difference is visible in one place rather than buried in a ternary
/// inside a button.
class _AddMemberButton extends ConsumerWidget {
  final String businessId;
  final String invitedBy;
  final String personName;
  final String mlid;

  const _AddMemberButton({
    required this.businessId,
    required this.invitedBy,
    required this.personName,
    required this.mlid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(globalWorkflowProvider);
    final type = state.memberType;
    final isInvestor = type == MemberType.investor;

    final label = switch (type) {
      MemberType.agent => ref.t('add_agent_to_business'),
      MemberType.investor => ref.t('request_business_membership'),
      _ => ref.t('add_customer_to_business'),
    };

    return ElevatedButton(
      onPressed: state.loading
          ? null
          : () async {
              final notifier = ref.read(globalWorkflowProvider.notifier);
              final ok = await NetworkErrorHandler.run(context, () async {
                return isInvestor
                    ? notifier.requestMembership(
                        businessId: businessId, invitedByPersonId: invitedBy)
                    : notifier.addExistingMemberDirect(businessId: businessId);
              });
              if (!context.mounted) return;
              // Only claim success when it succeeded. The old code showed
              // "request sent" unconditionally, including after a failure.
              if (ok != true) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: ManaText.raw(
                    isInvestor
                        ? ref
                            .t('request_sent_note')
                            .replaceAll('{mlid}', mlid)
                            .replaceAll('{type}', type?.label ?? 'Member')
                        : ref.t('member_added_note').replaceAll('{name}', personName),
                  ),
                ),
              );
            },
      child: ManaText.raw(label),
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
        ManaText.raw(ref.t('minimum_information'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _fullName,
          decoration: InputDecoration(labelText: ref.t('full_name_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _fatherHusband,
          decoration: InputDecoration(labelText: ref.t('father_husband_name_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _village,
          decoration: InputDecoration(labelText: ref.t('village_required_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(controller: _mobile, decoration: InputDecoration(labelText: ref.t('mobile_number_optional_field'))),
        const SizedBox(height: ManaSpacing.sm),
        TextField(controller: _area, decoration: InputDecoration(labelText: ref.t('area_locality_optional_field'))),
        const SizedBox(height: ManaSpacing.sm),
        TextField(controller: _remarks, decoration: InputDecoration(labelText: ref.t('remarks_optional_field')), maxLines: 2),
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
                      SnackBar(content: ManaText.raw(ref.t('pre_existing_member_created_note'))),
                    );
                  }
                },
          child: state.loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : ManaText.raw(ref.t('save')),
        ),
      ],
    );
  }
}

class _IncompleteStep extends ConsumerWidget {
  final GlobalWorkflowState state;
  const _IncompleteStep({required this.state});

  // BUG FIXED this pass: this tile fired a SnackBar saying the Profile
  // Completion sub-flow was out of scope. It now navigates to the real
  // screen (ProfileCompletionScreen) — which needed migration 0053 to
  // exist first, since every write it performs is RLS-blocked for an Owner
  // acting on another person's rows. Disabled (with the reason shown)
  // rather than navigating when the wizard has no created member to point
  // at — reachable if this step is entered from a stage other than the
  // createPreExistingMember success path.
  bool get _canOpen => state.createdPersonId != null && state.createdMembershipId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: ManaColors.statusBad, shape: BoxShape.circle),
            ),
            const SizedBox(width: ManaSpacing.sm),
            Expanded(
              child: ManaText.raw(ref.t('incomplete_profile'),
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
          ],
        ),
        const SizedBox(height: ManaSpacing.md),
        ManaText.raw(
          ref.t('incomplete_profile_note'),
          style: TextStyle(color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        Card(
          child: ListTile(
            title: ManaText.raw(ref.t('complete_profile')),
            subtitle: ManaText.raw(
              ref.t('complete_profile_note'),
              style: const TextStyle(fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: _canOpen,
            onTap: !_canOpen
                ? null
                : () => context.push(
                      '/ow-014-complete-profile'
                      '?personId=${state.createdPersonId}'
                      '&membershipId=${state.createdMembershipId}',
                    ),
          ),
        ),
        if (!_canOpen) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(
            ref.t('no_member_selected_note'),
            style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
          ),
        ],
      ],
    );
  }
}
