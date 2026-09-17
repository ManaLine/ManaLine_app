import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/widgets/village_search_field.dart';
import '../../../shared/location_api_service.dart';
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

  /// Open on the registration form, skipping the MLID search.
  ///
  /// Set by a caller that has already searched and been told nobody matched —
  /// see GlobalWorkflowNotifier.initWithType for why searching a second time
  /// was the bug rather than the safeguard.
  final bool startAtRegistration;

  const GlobalWorkflowScreen({
    super.key,
    required this.businessId,
    required this.currentOwnerPersonId,
    this.preSelectedType,
    this.startAtRegistration = false,
  });

  @override
  ConsumerState<GlobalWorkflowScreen> createState() => _GlobalWorkflowScreenState();
}

class _GlobalWorkflowScreenState extends ConsumerState<GlobalWorkflowScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(globalWorkflowProvider.notifier).initWithType(
            widget.preSelectedType,
            startAtRegistration: widget.startAtRegistration,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalWorkflowProvider);

    return Scaffold(
      // The title follows the step, because it stopped being true. Landing on
      // the registration form under "Add Existing Member" tells somebody they
      // are attaching a person who already exists, at the moment the app has
      // just told them nobody does.
      appBar: ManaAppBar(
        title: ref.t(state.stage == WizardStage.notFound
            ? switch (state.memberType) {
                MemberType.agent => 'add_an_agent',
                MemberType.investor => 'add_investor',
                _ => 'add_existing_member',
              }
            : 'add_existing_member'),
      ),
      body: SafeArea(
        child: switch (state.stage) {
          WizardStage.selectType => _SelectTypeStep(),
          WizardStage.searchMlid => _SearchMlidStep(businessId: widget.businessId),
          WizardStage.found => _FoundStep(businessId: widget.businessId),
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

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _mobileController.dispose();
    _mlidController.dispose();
    super.dispose();
  }
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
              style: ManaType.secondary),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _mobileController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: ref.t('mobile_number_field')),
        ),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(ref.t('or_separator'), style: ManaType.secondary, textAlign: TextAlign.center),
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
          ManaText.raw(state.error!, style: ManaType.bad),
        ],
      ],
    );
  }
}

class _FoundStep extends ConsumerWidget {
  final String businessId;
  const _FoundStep({required this.businessId});

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
  final String personName;
  final String mlid;

  const _AddMemberButton({
    required this.businessId,
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
                        businessId: businessId)
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

/// Nobody on file with that number -- so register them properly.
///
/// WHAT THIS REPLACED, AND WHY IT HAD TO GO. The heading said "Minimum
/// Information" and it collected three required fields: a full name, a
/// father/husband name, and a VILLAGE TYPED INTO A BOX. It could not work.
/// supabase/functions/auth-register validates `address.village_id` and a
/// six-digit `pin_code`, and the method behind the button sent neither -- so
/// every Save on that form was a 400, and had been since it was written. It
/// also hardcoded gender '0' against a NOT NULL column, with its own FLAGGED
/// note saying so.
///
/// Reported from a handset as "completely remove that minimal information
/// form in both" -- right instinct, and for a harder reason than the one
/// given: an Agent registered this way had an address that was a string
/// somebody typed, which is the difference between being findable by village
/// and not.
///
/// THE SAME FIELD SET AS A CUSTOMER, because it is the same act. A person is
/// a person; the role is what is attached afterwards, and Add Customer has
/// already settled what registering one costs at a doorstep -- name,
/// father/husband, gender, a village from the picker, and a mobile or an
/// Aadhaar so the record can be matched later.
class _NotFoundStepState extends ConsumerState<_NotFoundStep> {
  final _fullName = TextEditingController();
  final _fatherHusband = TextEditingController();
  final _mobile = TextEditingController();
  final _aadhaar = TextEditingController();
  final _doorNo = TextEditingController();
  final _area = TextEditingController();
  final _remarks = TextEditingController();
  String? _gender;
  String? _villageId;
  String? _villagePin;
  String? _villageLabel;

  @override
  void dispose() {
    _fullName.dispose();
    _fatherHusband.dispose();
    _mobile.dispose();
    _aadhaar.dispose();
    _doorNo.dispose();
    _area.dispose();
    _remarks.dispose();
    super.dispose();
  }

  /// A VILLAGE PICK IS A LOCATION ROW, not a name.
  ///
  /// Resolved through the same service the customer form uses, so a village
  /// chosen here and one chosen there point at the same `locations` row --
  /// idempotent through add_location_if_missing.
  Future<void> _onVillagePicked(ManaVillage? v) async {
    if (v == null) {
      setState(() {
        _villageId = null;
        _villagePin = null;
        _villageLabel = null;
      });
      return;
    }
    var id = v.locationId;
    if (id.isEmpty) {
      final resolved = await NetworkErrorHandler.run(
          context, () => ref.read(locationApiServiceProvider).resolveId(v));
      if (resolved == null || !mounted) return;
      id = resolved;
    }
    if (!mounted) return;
    setState(() {
      _villageId = id;
      if (v.pinCode.isNotEmpty) _villagePin = v.pinCode;
      _villageLabel = [v.name, v.mandal, v.district, v.state]
          .where((s) => s.trim().isNotEmpty)
          .join(' — ');
    });
  }

  /// What is missing, in order, or null.
  ///
  /// THE SAME SHAPE Add Customer settled on this pass, and for the same
  /// reason: a disabled Save at a doorstep is indistinguishable from a broken
  /// one, so the button is always pressable and always answers.
  String? _whatIsMissing() {
    if (_fullName.text.trim().length < 2) return ref.t('full_name_required');
    if (_fatherHusband.text.trim().length < 2) {
      return ref.t('father_husband_name_required');
    }
    if (_gender == null) return ref.t('gender_required');
    if (_villageId == null || (_villagePin ?? '').length != 6) {
      return ref.t('village_required');
    }
    if (_mobile.text.trim().isNotEmpty && _mobile.text.trim().length != 10) {
      return ref.t('mobile_must_be_ten_digits');
    }
    if (_aadhaar.text.trim().isNotEmpty && _aadhaar.text.trim().length != 12) {
      return ref.t('aadhaar_must_be_twelve_digits');
    }
    // An Agent or an Investor SIGNS IN -- they are being granted reach into
    // somebody else's book, and respond_to_invitation is how they accept. A
    // person the app cannot reach cannot accept, so unlike a migrated
    // customer this is not optional for them.
    if (_mobile.text.trim().isEmpty && _aadhaar.text.trim().isEmpty) {
      return ref.t('customer_needs_phone_or_aadhaar');
    }
    return null;
  }

  Future<void> _save() async {
    final why = _whatIsMissing();
    if (why != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: ManaText.raw(why)));
      return;
    }
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(globalWorkflowProvider.notifier).createPreExistingMember(
            businessId: widget.businessId,
            fullName: _fullName.text.trim(),
            fatherHusbandName: _fatherHusband.text.trim(),
            genderDigit: _gender!,
            villageId: _villageId!,
            pinCode: _villagePin!,
            doorNo: _doorNo.text.trim(),
            mobileNumber:
                _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
            aadhaarNumber:
                _aadhaar.text.trim().isEmpty ? null : _aadhaar.text.trim(),
            areaLocality: _area.text.trim().isEmpty ? null : _area.text.trim(),
            remarks:
                _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
          );
    });
    // `mounted`, the State's own -- context.mounted is a different question
    // and the analyzer is right to say so: this is a State.context.
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('pre_existing_member_created_note'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalWorkflowProvider);

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('register_new_person'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(ref.t('register_new_person_note'), style: ManaType.note),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: ref.t('full_name_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _fatherHusband,
          textCapitalization: TextCapitalization.words,
          decoration:
              InputDecoration(labelText: ref.t('father_husband_name_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.sm),
        // Gender is NOT NULL on persons and the MLID's own check digit is
        // derived from it. The old form hardcoded '0' and said so in a
        // comment; it is asked now.
        DropdownButtonFormField<String>(
          initialValue: _gender,
          isExpanded: true,
          decoration: InputDecoration(labelText: ref.t('gender_field')),
          items: [
            DropdownMenuItem(value: '1', child: ManaText.raw(ref.t('male'))),
            DropdownMenuItem(value: '2', child: ManaText.raw(ref.t('female'))),
            DropdownMenuItem(value: '3', child: ManaText.raw(ref.t('others'))),
          ],
          onChanged: (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          decoration:
              InputDecoration(labelText: ref.t('mobile_number_optional_field')),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _aadhaar,
          keyboardType: TextInputType.number,
          maxLength: 12,
          decoration: InputDecoration(labelText: ref.t('aadhaar_number_field')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _doorNo,
          decoration: InputDecoration(labelText: ref.t('door_house_no')),
        ),
        const SizedBox(height: ManaSpacing.md),
        ManaVillageSearchField(
          label: ref.t('search_village_town'),
          onPicked: _onVillagePicked,
        ),
        if (_villageLabel != null) ...[
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(
              ref.t('selected_note').replaceAll('{label}', _villageLabel!),
              style: ManaType.note),
        ],
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _area,
          decoration:
              InputDecoration(labelText: ref.t('area_locality_optional_field')),
        ),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _remarks,
          decoration:
              InputDecoration(labelText: ref.t('remarks_optional_field')),
          maxLines: 2,
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          // ALWAYS PRESSABLE. See _whatIsMissing.
          onPressed: state.loading ? null : _save,
          child: state.loading
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
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
          style: ManaType.secondary,
        ),
        const SizedBox(height: ManaSpacing.lg),
        Card(
          child: ListTile(
            title: ManaText.raw(ref.t('complete_profile')),
            subtitle: ManaText.raw(
              ref.t('complete_profile_note'),
              style: ManaType.small,
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
            style: ManaType.note,
          ),
        ],
      ],
    );
  }
}
