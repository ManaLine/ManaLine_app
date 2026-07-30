import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/title_case_formatter.dart';
import '../../../shared/business_name_checker.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../login_registration/state/auth_api_service.dart';
import '../state/owner_workspace_state.dart';

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
      appBar: AppBar(
        title: ManaText(state.isAdditionalBusiness
            ? 'set up new business'
            : 'first business setup'),
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
                    style: const TextStyle(color: ManaColors.statusBad)),
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
      case BusinessSetupStep.operatingAreas:
        return _Step2OperatingAreas(
          onBack: () => _goTo(BusinessSetupStep.createBusiness),
          onNext: () => _goTo(BusinessSetupStep.accountCycle),
        );
      case BusinessSetupStep.accountCycle:
        return _Step3AccountCycle(
          onBack: () => _goTo(BusinessSetupStep.operatingAreas),
          onNext: () => _goTo(BusinessSetupStep.existingMembers),
        );
      case BusinessSetupStep.existingMembers:
        return _Step4ExistingMembers(
          onBack: () => _goTo(BusinessSetupStep.accountCycle),
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

class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;
  const _StepIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
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
                color: ManaColors.brass,
              ),
            ),
          ),
          const SizedBox(width: ManaSpacing.md),
          ManaText.raw('Step $current of $total',
              style: const TextStyle(
                  fontSize: 13, color: ManaColors.textSecondary)),
        ],
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                    style: const TextStyle(
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
                        child: const ManaText('back')),
                  ),
                if (onBack != null) const SizedBox(width: ManaSpacing.md),
                if (onSkip != null)
                  Expanded(
                    child: TextButton(
                        onPressed: submitting ? null : onSkip,
                        child: const ManaText('skip for now')),
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
      if (chosen != null) setState(() => _businessName.text = chosen);
      return; // let the person review/confirm before submitting again
    }
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(businessSetupProvider.notifier).submitStep1(
            businessName: _businessName.text.trim(),
            registeredFinanceName: _financeName.text.trim(),
            businessAddress:
                _address.text.trim().isEmpty ? null : _address.text.trim(),
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
          final url = await Supabase.instance.client.storage
              .from('business-logos')
              .createSignedUrl(path, 60 * 60 * 24 * 365);
          await Supabase.instance.client
              .from('businesses')
              .update({'logo_url': url}).eq('business_id', businessId);
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
                    ? const Icon(Icons.add_a_photo_outlined,
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
            decoration: const InputDecoration(labelText: 'Business Name *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _financeName,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [TitleCaseTextFormatter()],
            decoration:
                const InputDecoration(labelText: 'Registered Finance Name *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Business Address'),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Business Phone'),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Business Email'),
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
  final _pinCode = TextEditingController();
  final _villageSearch = TextEditingController();
  String? _selectedVillageId;
  String? _selectedVillage; // display label
  List<Map<String, dynamic>> _villageResults = [];
  bool _villageSearchAttempted = false;
  bool _manualVillageEntry = false;
  final _manualVillageName = TextEditingController();
  final _manualMandal = TextEditingController();
  final _manualDistrict = TextEditingController();
  final _manualState = TextEditingController();
  String _manualAreaType = 'Village';
  bool _savingManualVillage = false;

  Future<void> _searchVillages(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _villageResults = [];
        _villageSearchAttempted = false;
      });
      return;
    }
    final pin = _pinCode.text.trim();
    if (pin.length != 6) {
      setState(() {
        _villageResults = [];
        _villageSearchAttempted = false;
      });
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('locations')
          .select('location_id, village_town_name, mandal, district, state')
          .eq('status', 'Active')
          .eq('pin_code', pin)
          .ilike('village_town_name', '%${query.trim()}%')
          .limit(10);
      if (!mounted) return;
      setState(() {
        _villageResults = (rows as List).cast<Map<String, dynamic>>();
        _villageSearchAttempted = true;
      });
    } catch (e) {
      // A failed search must still unlock the "add if not found" fallback
      // — silently swallowing this here (no catch, pre-fix) meant
      // _villageSearchAttempted never flipped true, so NEITHER the
      // results list NOR the manual-add prompt ever appeared: the person
      // was stuck with no visible next step at all.
      if (!mounted) return;
      setState(() {
        _villageResults = [];
        _villageSearchAttempted = true;
      });
    }
  }

  Future<void> _saveManualVillage() async {
    if (_manualVillageName.text.trim().isEmpty ||
        _manualMandal.text.trim().isEmpty ||
        _manualDistrict.text.trim().isEmpty ||
        _manualState.text.trim().isEmpty ||
        _pinCode.text.trim().length != 6) {
      return;
    }
    setState(() => _savingManualVillage = true);
    final result = await NetworkErrorHandler.run(context, () async {
      final rows = await Supabase.instance.client
          .schema('app')
          .rpc('add_location_if_missing', params: {
        'p_pin_code': _pinCode.text.trim(),
        'p_village_town_name': _manualVillageName.text.trim(),
        'p_area_type': _manualAreaType,
        'p_mandal': _manualMandal.text.trim(),
        'p_district': _manualDistrict.text.trim(),
        'p_state': _manualState.text.trim(),
      });
      return (rows as List).first as Map<String, dynamic>;
    });
    if (!mounted) return;
    setState(() => _savingManualVillage = false);
    if (result == null) return;

    final label =
        '${_manualVillageName.text.trim()} — ${_manualMandal.text.trim()}, ${_manualDistrict.text.trim()}, ${_manualState.text.trim()}';
    setState(() {
      _selectedVillageId = result['location_id'] as String;
      _selectedVillage = label;
      _villageSearch.text = _manualVillageName.text.trim();
      _villageResults = [];
      _manualVillageEntry = false;
    });
    if (mounted) {
      final wasExisting = result['was_existing'] as bool? ?? false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(wasExisting
                ? 'That village already existed — selected it.'
                : 'Village added and selected.')),
      );
    }
  }

  Future<void> _addArea() async {
    if (_pinCode.text.trim().length != 6 || _selectedVillageId == null) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(businessSetupProvider.notifier).addOperatingArea(
            pinCode: _pinCode.text.trim(),
            villageId: _selectedVillageId!,
            villageName: _selectedVillage!,
          );
    });
    if (ok == true) {
      setState(() {
        _pinCode.clear();
        _villageSearch.clear();
        _selectedVillageId = null;
        _selectedVillage = null;
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
          TextField(
            controller: _pinCode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
                labelText: 'PIN Code',
                helperText:
                    'Enter PIN code first — villages shown are limited to this PIN'),
            onChanged: (_) {
              setState(() {
                _selectedVillageId = null;
                _selectedVillage = null;
              });
              _searchVillages(_villageSearch.text);
            },
          ),
          TextField(
            controller: _villageSearch,
            decoration: const InputDecoration(labelText: 'Search Village/Town'),
            onChanged: (v) {
              setState(() {
                _selectedVillageId = null;
                _selectedVillage = null;
                _manualVillageEntry = false;
              });
              _searchVillages(v);
            },
          ),
          if (_villageResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              margin: const EdgeInsets.only(top: ManaSpacing.xs),
              decoration: BoxDecoration(
                  border: Border.all(color: ManaColors.surfaceSunken)),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _villageResults.length,
                itemBuilder: (_, i) {
                  final v = _villageResults[i];
                  final label =
                      '${v['village_town_name']} — ${v['mandal']}, ${v['district']}, ${v['state']}';
                  return ListTile(
                    dense: true,
                    title: ManaText.raw(label,
                        style: const TextStyle(fontSize: 13)),
                    onTap: () => setState(() {
                      _selectedVillageId = v['location_id'] as String;
                      _selectedVillage = label;
                      _villageSearch.text = v['village_town_name'] as String;
                      _villageResults = [];
                    }),
                  );
                },
              ),
            ),
          if (_villageSearchAttempted &&
              _villageResults.isEmpty &&
              _selectedVillageId == null &&
              !_manualVillageEntry)
            Padding(
              padding: const EdgeInsets.only(top: ManaSpacing.xs),
              child: TextButton(
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                onPressed: () => setState(() {
                  _manualVillageEntry = true;
                  _manualVillageName.text = _villageSearch.text.trim();
                }),
                child:
                    Text('"${_villageSearch.text.trim()}" not found — add it'),
              ),
            ),
          if (_manualVillageEntry)
            Container(
              margin: const EdgeInsets.only(top: ManaSpacing.sm),
              padding: const EdgeInsets.all(ManaSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: ManaColors.surfaceSunken),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText('add new village',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: ManaSpacing.sm),
                  TextField(
                    controller: _manualVillageName,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Village/Town Name *'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: ManaSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: _manualAreaType,
                    decoration: const InputDecoration(labelText: 'Area Type *'),
                    items: const [
                      DropdownMenuItem(
                          value: 'Village', child: Text('Village')),
                      DropdownMenuItem(value: 'Town', child: Text('Town')),
                    ],
                    onChanged: (v) =>
                        setState(() => _manualAreaType = v ?? 'Village'),
                  ),
                  const SizedBox(height: ManaSpacing.sm),
                  TextField(
                    controller: _manualMandal,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Mandal *'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: ManaSpacing.sm),
                  TextField(
                    controller: _manualDistrict,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'District *'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: ManaSpacing.sm),
                  TextField(
                    controller: _manualState,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'State *'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: ManaSpacing.sm),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _savingManualVillage
                            ? null
                            : () => setState(() => _manualVillageEntry = false),
                        child: const ManaText('cancel'),
                      ),
                      const SizedBox(width: ManaSpacing.sm),
                      ElevatedButton(
                        onPressed: (_savingManualVillage ||
                                _manualVillageName.text.trim().isEmpty ||
                                _manualMandal.text.trim().isEmpty ||
                                _manualDistrict.text.trim().isEmpty ||
                                _manualState.text.trim().isEmpty ||
                                _pinCode.text.trim().length != 6)
                            ? null
                            : _saveManualVillage,
                        child: _savingManualVillage
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const ManaText('save & select'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_selectedVillage != null) ...[
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw('Selected: $_selectedVillage',
                style: const TextStyle(
                    fontSize: 13, color: ManaColors.textSecondary)),
          ],
          const SizedBox(height: ManaSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: (_pinCode.text.trim().length == 6 &&
                      _selectedVillageId != null)
                  ? _addArea
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: const ManaText('add area'),
            ),
          ),
          const SizedBox(height: ManaSpacing.lg),
          if (state.operatingAreas.isEmpty)
            const ManaText.raw('No Operating Areas added yet.',
                style: TextStyle(color: ManaColors.textSecondary))
          else
            ...state.operatingAreas.map((a) => Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.location_on, color: ManaColors.brass),
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

class _Step3AccountCycle extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  const _Step3AccountCycle({required this.onBack, required this.onNext});

  @override
  ConsumerState<_Step3AccountCycle> createState() => _Step3AccountCycleState();
}

class _Step3AccountCycleState extends ConsumerState<_Step3AccountCycle> {
  Future<void> _configure(OperatingAreaDraft area) async {
    final duration = await showDialog<int>(
      context: context,
      builder: (_) => const _DurationPickerDialog(),
    );
    if (duration == null) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessSetupProvider.notifier).configureAccountCycle(
            areaLocalId: area.localId,
            durationDays: duration,
            submissionTime: '18:00',
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessSetupProvider);
    return _StepScaffold(
      title: 'configure account cycle',
      subtitle:
          'Set Duration and Submission Time for each Operating Area — one '
          'configuration per area.',
      nextEnabled: state.step3Complete,
      submitting: state.submitting,
      onBack: widget.onBack,
      onNext: widget.onNext,
      child: Column(
        children: state.operatingAreas
            .map((a) => Card(
                  child: ListTile(
                    leading: Icon(
                      a.cycleConfigured
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: a.cycleConfigured
                          ? ManaColors.statusGood
                          : ManaColors.textSecondary,
                    ),
                    title: ManaText.raw(a.villageName),
                    subtitle: ManaText.raw(
                      a.cycleConfigured
                          ? '${a.accountCycleDurationDays} days · submit by ${a.accountCycleSubmissionTime}'
                          : 'Not configured',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _configure(a),
                          child: ManaText(
                              a.cycleConfigured ? 'edit' : 'configure'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove area',
                          onPressed: () => ref
                              .read(businessSetupProvider.notifier)
                              .removeOperatingArea(a.localId),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _DurationPickerDialog extends StatefulWidget {
  const _DurationPickerDialog();
  @override
  State<_DurationPickerDialog> createState() => _DurationPickerDialogState();
}

class _DurationPickerDialogState extends State<_DurationPickerDialog> {
  int _days = 30;
  late final _controller = TextEditingController(text: '30');

  void _setDays(int value) {
    final clamped = value.clamp(1, 365);
    setState(() {
      _days = clamped;
      _controller.text = '$clamped';
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const ManaText('account cycle duration'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              onPressed: () => _setDays(_days - 1),
              icon: const Icon(Icons.remove)),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontWeight: FontWeight.bold),
              decoration:
                  const InputDecoration(isDense: true, suffixText: 'days'),
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null) _days = parsed.clamp(1, 365);
              },
            ),
          ),
          IconButton(
              onPressed: () => _setDays(_days + 1),
              icon: const Icon(Icons.add)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const ManaText('cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, _days),
            child: const ManaText('save')),
      ],
    );
  }
}

// --- Step 4 — Add Existing Members (optional) -------------------------------

class _Step4ExistingMembers extends ConsumerWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  const _Step4ExistingMembers(
      {required this.onBack, required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StepScaffold(
      title: 'add existing members',
      subtitle:
          'Optional — migrate pre-existing customers/agents/investors via the '
          'Pre-Existing Member workflow (OW-014). Skip if there are none to migrate.',
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
              const Icon(Icons.group_add_outlined, color: ManaColors.brass),
          title: const ManaText('start pre-existing member migration'),
          subtitle: const ManaText.raw('Launches OW-014 Global Workflow.',
              style: TextStyle(fontSize: 13)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'OW-014 Global Workflow — not yet built in this pass.')),
            );
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
          return Card(
            child: ListTile(
              leading: Icon(
                  created ? Icons.check_circle : Icons.description_outlined,
                  color: created ? ManaColors.statusGood : ManaColors.brass),
              title: ManaText.raw('$type Agreement'),
              trailing: TextButton(
                onPressed: created ? null : () => _create(context, ref, type),
                child: ManaText(created ? 'created' : 'upload / create'),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// --- Step 6 — Assign Operating Areas to Agents -------------------------------

class _Step6AssignAreas extends ConsumerWidget {
  final VoidCallback onBack;
  const _Step6AssignAreas({required this.onBack});

  Future<void> _markOwnerRun(
      BuildContext context, WidgetRef ref, OperatingAreaDraft a) async {
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(businessSetupProvider.notifier)
          .markAreaOwnerRun(areaLocalId: a.localId);
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
      subtitle: 'Mark at least one area Owner-Run to start your business. '
          'Assigning specific areas to Agents happens after your business is created, '
          'via Business Management — agents can\'t be added to a business that doesn\'t exist yet.',
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
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: ManaSpacing.xs),
                  ManaText.raw(
                    a.ownerRun
                        ? 'Owner-Run'
                        : a.assignedAgentId != null
                            ? 'Assigned to ${a.assignedAgentName}'
                            : 'Not yet resolved',
                    style: TextStyle(
                      fontSize: 13,
                      color: a.resolved
                          ? ManaColors.statusGood
                          : ManaColors.statusWarn,
                    ),
                  ),
                  const SizedBox(height: ManaSpacing.sm),
                  Row(
                    children: [
                      const Expanded(
                        child: Tooltip(
                          message:
                              'Assign to an Agent after your business is created, via Business Management.',
                          child: OutlinedButton(
                            onPressed:
                                null, // Was a stub (fake agent picker) — see subtitle above for why this is genuinely disabled here, not a bug.
                            child: ManaText('assign agent'),
                          ),
                        ),
                      ),
                      const SizedBox(width: ManaSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _markOwnerRun(context, ref, a),
                          child: const ManaText('owner-run'),
                        ),
                      ),
                    ],
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
