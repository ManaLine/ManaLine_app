import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/title_case_formatter.dart';
import '../../../shared/business_name_checker.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../login_registration/state/auth_api_service.dart';
import '../state/owner_workspace_state.dart';
import '../state/owner_api_service.dart' show AgentSummary;
import '../../../shared/widgets/village_picker_field.dart';
import '../../../shared/widgets/village_search_field.dart';
import '../../../shared/location_api_service.dart';

/// OW-000 — First Business Setup. 6-step wizard shell over fields that
/// already exist in OW-012/OW-014 (this screen introduces no new fields,
/// per its own PURPOSE). Header text is the only difference between a
/// brand-new Owner and one adding business #2+ (BR-119 Revised).
class FirstBusinessSetupScreen extends ConsumerStatefulWidget {
  final bool isAdditionalBusiness;
  const FirstBusinessSetupScreen(
      {super.key, this.isAdditionalBusiness = false});

  @override
  ConsumerState<FirstBusinessSetupScreen> createState() =>
      _FirstBusinessSetupScreenState();
}

class _FirstBusinessSetupScreenState
    extends ConsumerState<FirstBusinessSetupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(businessSetupProvider.notifier)
          .start(isAdditionalBusiness: widget.isAdditionalBusiness);
    });
  }

  static const _steps = BusinessSetupStep.values;

  void _goTo(BusinessSetupStep step) =>
      ref.read(businessSetupProvider.notifier).goToStep(step);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessSetupProvider);
    final stepIndex = _steps.indexOf(state.currentStep);

    return Scaffold(
      appBar: ManaAppBar(
        title: ref.t(state.isAdditionalBusiness
            ? 'set_up_new_business'
            : 'first_business_setup'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(current: stepIndex + 1, total: _steps.length),
            if (state.error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(
                    ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, 0),
                padding: const EdgeInsets.all(ManaSpacing.md),
                decoration: BoxDecoration(
                  color: ManaColors.statusBadFaint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ManaText.raw(state.error!,
                    style: ManaType.bad),
              ),
            Expanded(child: _stepBody(state)),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(BusinessSetupState state) {
    switch (state.currentStep) {
      case BusinessSetupStep.createBusiness:
        return _Step1CreateBusiness(
            onNext: () => _goTo(BusinessSetupStep.operatingAreas));
      // No account-cycle step. It asked for a duration and a submission time
      // per area, and neither exists any more: an account runs from the last
      // submission to the next one. Six steps, then five.
      case BusinessSetupStep.operatingAreas:
        return _Step2OperatingAreas(
          onBack: () => _goTo(BusinessSetupStep.createBusiness),
          onNext: () => _goTo(BusinessSetupStep.existingMembers),
        );
      case BusinessSetupStep.existingMembers:
        return _Step4ExistingMembers(
          onBack: () => _goTo(BusinessSetupStep.operatingAreas),
          onNext: () => _goTo(BusinessSetupStep.agreements),
          onSkip: () => _goTo(BusinessSetupStep.agreements),
        );
      case BusinessSetupStep.agreements:
        return _Step5Agreements(
          onBack: () => _goTo(BusinessSetupStep.existingMembers),
          onNext: () => _goTo(BusinessSetupStep.assignAreas),
          onSkip: () => _goTo(BusinessSetupStep.assignAreas),
        );
      case BusinessSetupStep.assignAreas:
        return _Step6AssignAreas(
            onBack: () => _goTo(BusinessSetupStep.agreements));
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
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, ManaSpacing.sm),
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
          ManaText.raw(ref.t('step_x_of_y').replaceAll('{current}', '$current').replaceAll('{total}', '$total'),
              style: TextStyle(
                  fontSize: 13, color: ManaColors.textSecondary)),
        ],
      ),
    );
  }
}

class _StepScaffold extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;
  final String nextLabel;
  final bool nextEnabled;
  final bool submitting;

  const _StepScaffold({
    required this.title,
    this.subtitle,
    required this.child,
    this.onBack,
    this.onNext,
    this.onSkip,
    this.nextLabel = 'continue',
    this.nextEnabled = true,
    this.submitting = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            children: [
              ManaText(title,
                  style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(subtitle!,
                    style: TextStyle(
                        color: ManaColors.textSecondary, fontSize: 13)),
              ],
              const SizedBox(height: ManaSpacing.lg),
              child,
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: Row(
              children: [
                if (onBack != null)
                  Expanded(
                    child: OutlinedButton(
                        onPressed: submitting ? null : onBack,
                        child: ManaText.raw(ref.t('back'))),
                  ),
                if (onBack != null) const SizedBox(width: ManaSpacing.md),
                if (onSkip != null)
                  Expanded(
                    child: TextButton(
                        onPressed: submitting ? null : onSkip,
                        child: ManaText.raw(ref.t('skip_for_now'))),
                  ),
                if (onSkip != null) const SizedBox(width: ManaSpacing.md),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (nextEnabled && !submitting) ? onNext : null,
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : ManaText(nextLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --- Step 1 — Create Business ----------------------------------------------

class _Step1CreateBusiness extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  const _Step1CreateBusiness({required this.onNext});

  @override
  ConsumerState<_Step1CreateBusiness> createState() =>
      _Step1CreateBusinessState();
}

class _Step1CreateBusinessState extends ConsumerState<_Step1CreateBusiness> {

  /// The village picked for the BUSINESS address, which is not the same thing
  /// as an operating area and is deliberately never resolved into a
  /// `locations` row — a head office nobody collects in does not belong in the
  /// operating directory.
  ManaVillage? _addressVillage;

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _businessName.dispose();
    _financeName.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }
  final _businessName = TextEditingController();
  final _financeName = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  Uint8List? _logoBytes;

  bool get _canSubmit =>
      _businessName.text.trim().isNotEmpty &&
      _financeName.text.trim().isNotEmpty;

  Future<void> _pickLogo() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (!mounted) return;
    setState(() => _logoBytes = bytes);
  }

  Future<void> _submit() async {
    final available = await BusinessNameChecker.isAvailable(_businessName.text);
    if (!available) {
      if (!mounted) return;
      final alternatives =
          await BusinessNameChecker.suggestAlternatives(_businessName.text);
      if (!mounted) return;
      final chosen = await showDialog<String>(
        context: context,
        builder: (_) => BusinessNameTakenDialog(
            name: _businessName.text.trim(), alternatives: alternatives),
      );
      if (!mounted) return;
      if (chosen != null) setState(() => _businessName.text = chosen);
      return; // let the person review/confirm before submitting again
    }
    if (!mounted) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(businessSetupProvider.notifier).submitStep1(
            businessName: _businessName.text.trim(),
            registeredFinanceName: _financeName.text.trim(),
            // Composed from the picked village, so the stored address always
            // carries mandal, district, state and PIN. Falls back to whatever
            // was typed when no village was picked — the field is optional and
            // a half-filled address is better than none.
            businessAddress: _addressVillage != null
                ? manaComposeAddress(
                    doorNo: _address.text, village: _addressVillage!)
                : (_address.text.trim().isEmpty ? null : _address.text.trim()),
            businessPhone:
                _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            businessEmail:
                _email.text.trim().isEmpty ? null : _email.text.trim(),
          );
    });
    if (ok == true) {
      final businessId = ref.read(businessSetupProvider).businessId;
      if (businessId != null && _logoBytes != null) {
        try {
          final path = '$businessId/logo.jpg';
          await Supabase.instance.client.storage
              .from('business-logos')
              .uploadBinary(
                path,
                _logoBytes!,
                fileOptions:
                    const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
          // The path, not a year-long signed URL. ManaBusinessLogo signs a
          // short-lived one when it draws -- see ManaStoredFile.
          await Supabase.instance.client
              .from('businesses')
              .update({'logo_url': path}).eq('business_id', businessId);
        } catch (e) {
          // Non-fatal — never block the wizard over a logo upload hiccup.
        }
      }
      widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = ref.watch(businessSetupProvider).submitting;
    return _StepScaffold(
      title: 'create your business',
      subtitle:
          'Business Name and Registered Finance Name are required. You can add more '
          'details later from Business Management.',
      nextEnabled: _canSubmit,
      submitting: submitting,
      onNext: _submit,
      child: Column(
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickLogo,
              child: CircleAvatar(
                radius: 40,
                backgroundColor: ManaColors.surfaceSunken,
                backgroundImage:
                    _logoBytes != null ? MemoryImage(_logoBytes!) : null,
                child: _logoBytes == null
                    ? Icon(Icons.add_a_photo_outlined,
                        color: ManaColors.textSecondary)
                    : null,
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _pickLogo,
              child: ManaText(
                  _logoBytes == null ? 'add business photo' : 'change photo'),
            ),
          ),
          TextField(
            controller: _businessName,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [TitleCaseTextFormatter()],
            decoration: InputDecoration(labelText: ref.t('business_name_field')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _financeName,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [TitleCaseTextFormatter()],
            decoration:
                InputDecoration(labelText: ref.t('registered_finance_name_field')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.md),
          // Door number plus a picked village, the same process registration
          // uses. This was one free-text box, so two people typing the same
          // place produced two different addresses and neither carried a PIN.
          TextField(
            controller: _address,
            decoration: InputDecoration(labelText: ref.t('door_no_street_field')),
          ),
          const SizedBox(height: ManaSpacing.sm),
          ManaVillageSearchField(
            label: ref.t('business_address_field'),
            onPicked: (v) => setState(() => _addressVillage = v),
          ),
          if (_addressVillage != null) ...[
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              manaComposeAddress(
                  doorNo: _address.text, village: _addressVillage!),
              style: ManaType.note,
            ),
          ],
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: ref.t('business_phone_field')),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: ref.t('business_email_field')),
          ),
        ],
      ),
    );
  }
}

// --- Step 2 — Operating Areas ----------------------------------------------

class _Step2OperatingAreas extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  const _Step2OperatingAreas({required this.onBack, required this.onNext});

  @override
  ConsumerState<_Step2OperatingAreas> createState() =>
      _Step2OperatingAreasState();
}

class _Step2OperatingAreasState extends ConsumerState<_Step2OperatingAreas> {

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  String? _selectedVillageId;
  String? _selectedVillage; // display label
  // The submitted pin_code comes from the picked village's directory row —
  // ManaVillageSearchField owns PIN entry now (its PIN mode embeds
  // ManaVillagePickerField, which renders the PIN field), so there is no
  // separate screen-typed box to read it from.
  String? _selectedVillagePinCode;
  Key _villageFieldKey = UniqueKey();

  /// Resolves a picked village to a real `location_id`, materialising it from
  /// the LGD reference first if the Owner picked a suggestion nobody had used
  /// yet — same reasoning as [ManaVillagePickerField]'s own doc comment: it
  /// does not write anything, so a caller that needs the id resolves it.
  Future<void> _onVillagePicked(ManaVillage? v) async {
    if (v == null) {
      setState(() {
        _selectedVillageId = null;
        _selectedVillage = null;
        _selectedVillagePinCode = null;
      });
      return;
    }
    var id = v.locationId;
    if (id.isEmpty) {
      final result = await NetworkErrorHandler.run(context, () async {
        return ref.read(locationApiServiceProvider).resolveId(v);
      });
      if (result == null || !mounted) return;
      id = result;
    }
    if (!mounted) return;
    final label = [v.name, v.mandal, v.district, v.state]
        .where((s) => s.trim().isNotEmpty)
        .join(' — ');
    setState(() {
      _selectedVillageId = id;
      _selectedVillage = label;
      if (v.pinCode.isNotEmpty) _selectedVillagePinCode = v.pinCode;
    });
  }

  Future<void> _addArea() async {
    if (_selectedVillageId == null || _selectedVillagePinCode == null) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(businessSetupProvider.notifier).addOperatingArea(
            pinCode: _selectedVillagePinCode!,
            villageId: _selectedVillageId!,
            villageName: _selectedVillage!,
          );
    });
    if (ok == true) {
      if (!mounted) return;
      setState(() {
        _selectedVillageId = null;
        _selectedVillage = null;
        _selectedVillagePinCode = null;
        // A new key, not just cleared state: the search field owns its own
        // text/pick state internally and has no reset method, so re-keying is
        // the only way to send the Owner back to a blank search for the next
        // area rather than leaving the just-added village showing as picked.
        _villageFieldKey = UniqueKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessSetupProvider);
    return _StepScaffold(
      title: 'create operating area(s)',
      subtitle:
          'At least 1 Operating Area is required. Add villages one at a time — you '
          'can add more later from Business Management.',
      nextEnabled: state.step2Complete,
      submitting: state.submitting,
      onBack: widget.onBack,
      onNext: widget.onNext,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaVillageSearchField(
            key: _villageFieldKey,
            label: ref.t('search_village_town_plain_field'),
            onPicked: _onVillagePicked,
          ),
          if (_selectedVillage != null) ...[
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(ref.t('selected_note').replaceAll('{value}', '$_selectedVillage'),
                style: TextStyle(
                    fontSize: 13, color: ManaColors.textSecondary)),
          ],
          const SizedBox(height: ManaSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: (_selectedVillageId != null &&
                      _selectedVillagePinCode != null)
                  ? _addArea
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: ManaText.raw(ref.t('add_area')),
            ),
          ),
          const SizedBox(height: ManaSpacing.lg),
          if (state.operatingAreas.isEmpty)
            ManaText.raw(ref.t('no_operating_areas_added'),
                style: ManaType.secondary)
          else
            ...state.operatingAreas.map((a) => Card(
                  child: ListTile(
                    leading:
                        Icon(Icons.location_on, color: ManaColors.brand),
                    title: ManaText.raw('${a.villageName} — ${a.pinCode}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => ref
                          .read(businessSetupProvider.notifier)
                          .removeOperatingArea(a.localId),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

// --- Step 3 — Configure Account Cycle per Area ------------------------------
class _Step4ExistingMembers extends ConsumerWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  const _Step4ExistingMembers(
      {required this.onBack, required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StepScaffold(
      title: 'migrate existing book',
      subtitle: ref.t('migrate_existing_book_step_note'),
      onBack: onBack,
      onNext: () {
        ref
            .read(businessSetupProvider.notifier)
            .markExistingMembersStepVisited();
        onNext();
      },
      onSkip: onSkip,
      child: Card(
        child: ListTile(
          leading:
              Icon(Icons.group_add_outlined, color: ManaColors.brand),
          title: ManaText.raw(ref.t('migrate_existing_book')),
          subtitle: ManaText.raw(ref.t('migrate_existing_book_note'),
              style: ManaType.small),
          trailing: const Icon(Icons.chevron_right),
          // Was a SnackBar reading "OW-014 Global Workflow — not yet built in
          // this pass", which was stale twice: OW-014 IS built, and it is the
          // member-by-member workflow, not what this step is for. Step 3 is the
          // pre-existing BUSINESS migration — the weekly-ledger import that
          // brought the sri satyanarayana book across.
          onTap: () {
            final businessId = ref.read(businessSetupProvider).businessId;
            if (businessId == null) {
              // Step 1 creates the business, so this cannot normally happen —
              // and if it does, saying so beats a dead tap.
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: ManaText.raw(ref.t('create_the_business_first')),
              ));
              return;
            }
            context.push('/ow-018', extra: businessId);
          },
        ),
      ),
    );
  }
}

// --- Step 5 — Create Business Agreements (optional) -------------------------

class _Step5Agreements extends ConsumerWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  const _Step5Agreements(
      {required this.onBack, required this.onNext, required this.onSkip});

  Future<void> _create(BuildContext context, WidgetRef ref, String type) async {
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessSetupProvider.notifier).createAgreement(
            agreementType: type,
            documentUrl: 'stub://agreement/$type',
          );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessSetupProvider);
    return _StepScaffold(
      title: 'create business agreements',
      subtitle:
          'Optional at this stage — can be completed later from Business Management '
          '→ Business Agreements.',
      onBack: onBack,
      onNext: onNext,
      onSkip: onSkip,
      child: Column(
        children: ['Customer', 'Agent', 'Investor'].map((type) {
          final created = state.agreementTypesCreated.contains(type);
          // Not a ListTile. Its trailing slot must fit on the title's line,
          // and "Upload / Create" translated does not -- at 1.3x Flutter
          // asserted outright ("trailing widget consumes the entire tile
          // width"), which is a crash, not a clipped pixel. The action gets
          // its own line instead, where the label can be as long as the
          // language needs.
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          created ? Icons.check_circle : Icons.description_outlined,
                          color: created ? ManaColors.statusGood : ManaColors.brand),
                      const SizedBox(width: ManaSpacing.md),
                      Expanded(child: ManaText.raw('$type Agreement')),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: created ? null : () => _create(context, ref, type),
                      child: ManaText(created ? 'created' : 'upload / create'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// --- Step 6 — Assign Operating Areas to Agents -------------------------------

/// "Nobody in this list" — returned by the agent picker so the caller can tell
/// a chosen agent from a request to go and add one.
const Object _addAgentSentinel = Object();

class _Step6AssignAreas extends ConsumerWidget {
  final VoidCallback onBack;
  const _Step6AssignAreas({required this.onBack});

  // Was permanently disabled with a "agents can't exist yet" tooltip. They
  // can now: creating the business also makes the creator its first Agent,
  // so this picker always has at least one row — the Owner themselves,
  // which is how an Owner who walks a round is represented.
  Future<void> _assignAgent(BuildContext context, WidgetRef ref, OperatingAreaDraft a) async {
    final businessId = ref.read(businessSetupProvider).businessId;
    if (businessId == null) return;
    final agents = await NetworkErrorHandler.run(context, () async {
      return ref.read(ownerApiServiceProvider).fetchAgents(businessId: businessId, status: 'Active');
    });
    if (agents == null || !context.mounted) return;
    // Object?, because this sheet now has two kinds of answer: an agent to
    // assign, or _addAgentSentinel meaning "there is nobody here I want".
    final chosen = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw(ref.t('who_works_village_note').replaceAll('{village}', a.villageName),
                  style: ManaType.cardTitle),
            ),
            if (agents.isEmpty)
              Padding(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                child: ManaText.raw(ref.t('no_active_agents_found'),
                    style: ManaType.note),
              )
            else
              ...agents.map((agent) => ListTile(
                    leading: const ManaVerificationRing(isVerified: true, size: 32),
                    title: ManaText.raw(agent.fullName),
                    subtitle: ManaText.raw(agent.mlid, style: ManaType.small),
                    onTap: () => Navigator.of(context).pop(agent),
                  )),
            // The list previously held exactly one row on a new business -- the
            // Owner, who is its first Agent -- and no way to reach anybody
            // else. Assigning the round to yourself was the only possible
            // answer, and the real one ("my agent is Ramesh") had to wait until
            // after setup, from Workforce Management.
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.person_add_alt_1_outlined, color: ManaColors.brand),
              title: ManaText.raw(ref.t('add_an_agent')),
              subtitle: ManaText.raw(ref.t('search_or_register_agent_note'),
                  style: ManaType.small),
              onTap: () => Navigator.of(context).pop(_addAgentSentinel),
            ),
            const SizedBox(height: ManaSpacing.md),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;

    if (identical(chosen, _addAgentSentinel)) {
      // OW-014 searches for an existing person by MLID or name and registers a
      // new one when there is no match. Reopen the picker afterwards rather
      // than leaving the Owner to find their way back: they came here to
      // assign somebody, and adding the agent was a detour, not the goal.
      await context.push('/ow-014?type=agent', extra: businessId);
      if (!context.mounted) return;
      return _assignAgent(context, ref, a);
    }

    final agent = chosen as AgentSummary;
    if (agent.membershipId == null) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessSetupProvider.notifier).assignAreaToAgent(
            areaLocalId: a.localId,
            agentId: agent.agentId,
            agentMembershipId: agent.membershipId!,
            agentName: agent.fullName,
          );
    });
  }

  Future<void> _startBusiness(BuildContext context, WidgetRef ref) async {
    final businessId = await NetworkErrorHandler.run(context, () async {
      final id = await ref.read(businessSetupProvider.notifier).startBusiness();
      if (id == null) throw Exception('Could not start business');
      return id;
    });
    if (businessId == null) return;
    if (!context.mounted) return;
    // Refresh authFlowProvider's cached memberships — LR-012 (Business
    // Selector) deliberately never re-fetches on its own (trusts the
    // snapshot taken at login time, per its own doc comment), so without
    // this the newly created business silently doesn't appear if the
    // person ever navigates back there in the same session.
    final memberships = await NetworkErrorHandler.run(
      context,
      () => ref
          .read(authApiServiceProvider)
          .fetchMemberships(ref.read(authFlowProvider).personId!),
    );
    if (memberships != null) {
      ref.read(authFlowProvider.notifier).setMemberships(memberships);
    }
    if (!context.mounted) return;
    context.go('/ow-001', extra: businessId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessSetupProvider);
    return _StepScaffold(
      title: 'assign operating areas',
      subtitle: 'Every area is worked by an agent. You are already registered '
          'as this business\'s first agent, so you can assign an area to '
          'yourself now and add more agents later, from Workforce Management.',
      onBack: onBack,
      onNext:
          state.canStartBusiness ? () => _startBusiness(context, ref) : null,
      nextEnabled: state.canStartBusiness,
      nextLabel: 'start business',
      submitting: state.submitting,
      child: Column(
        children: state.operatingAreas.map((a) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText.raw(a.villageName,
                      style: ManaType.strong),
                  const SizedBox(height: ManaSpacing.xs),
                  ManaText.raw(
                    a.assignedAgentId != null
                        ? 'Assigned to ${a.assignedAgentName}'
                        : 'No agent assigned yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: a.resolved ? ManaColors.statusGood : ManaColors.statusWarn,
                    ),
                  ),
                  const SizedBox(height: ManaSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () => _assignAgent(context, ref, a),
                      child: ManaText(a.resolved ? 'reassign' : 'assign agent'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
