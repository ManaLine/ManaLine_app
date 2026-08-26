import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/live_face_capture_screen.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/title_case_formatter.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/mana_location.dart';
import '../../../shared/widgets/use_my_location_button.dart';
import '../../../shared/widgets/language_selector.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';
import '../../../shared/network_error_handler.dart';
import '../../../design/components/mana_info_hint.dart';

/// LR-004 — long single-scroll form, not a wizard. Register button
/// disabled until mandatory fields + both acknowledgement checkboxes
/// are valid, per spec's sticky-footer gate.
class RegistrationFormScreen extends ConsumerStatefulWidget {
  const RegistrationFormScreen({super.key});

  @override
  ConsumerState<RegistrationFormScreen> createState() => _RegistrationFormScreenState();
}

class _RegistrationFormScreenState extends ConsumerState<RegistrationFormScreen> {

  // Disposed, all of them.
  //
  // Every controller on this screen outlived it: a TextEditingController holds
  // a listener list and a ChangeNotifier, and a State that never disposes them
  // leaks one set per visit. On a low-end handset an Agent opens screens like
  // this forty times a round.
  @override
  void dispose() {
    _surname.dispose();
    _givenName.dispose();
    _fullNameLocal.dispose();
    _fatherHusbandName.dispose();
    _mobile.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _pinCode.dispose();
    _doorNo.dispose();
    _aadhaar.dispose();
    _confirmAadhaar.dispose();
    _villageSearch.dispose();
    _manualVillageName.dispose();
    _manualMandal.dispose();
    _manualDistrict.dispose();
    _manualState.dispose();
    super.dispose();
  }
  final _formKey = GlobalKey<FormState>();
  // Surname and given name are entered separately so the app knows which part
  // is the house name. Matching a person depends on that: "Karri Siri
  // Manikanta Reddy" and "K S M Reddy" are the same person, and nothing can
  // tell without knowing where the intiperu ends.
  final _surname = TextEditingController();
  final _givenName = TextEditingController();

  /// The Telugu spelling, optional, display only. Replaces the old
  /// "Full Name in English" field, which had the polarity backwards — it let
  /// the Telugu spelling be canonical and asked for English as an
  /// afterthought, then never submitted the answer (fixed here). The name on
  /// the Aadhaar card is the one that has to match, so that one is entered
  /// directly and this is the extra.
  final _fullNameLocal = TextEditingController();

  /// Surname + given name, exactly as it will be stored and printed. Shown
  /// live under the two fields so the person checks the WHOLE string against
  /// their card — Aadhaar has one name box, not two, so the split itself is
  /// this app's idea and they should never have to reason about it.
  String get _composedName =>
      '${_surname.text.trim()} ${_givenName.text.trim()}'.trim();

  /// Detects Telugu, Devanagari (Hindi), Tamil, or Kannada script by
  /// Unicode code point range — real detection, not a heuristic guess.
  /// When true, the companion "in English" field is shown so the person
  /// provides the Latin-script spelling themselves (never auto-
  /// transliterated — see the field's own helper text for why).
  bool _containsNonLatinScript(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x0C00 && rune <= 0x0C7F) || // Telugu
          (rune >= 0x0900 && rune <= 0x097F) || // Devanagari (Hindi)
          (rune >= 0x0B80 && rune <= 0x0BFF) || // Tamil
          (rune >= 0x0C80 && rune <= 0x0CFF)) { // Kannada
        return true;
      }
    }
    return false;
  }
  final _fatherHusbandName = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _pinCode = TextEditingController();

  /// Set only when "Use My Location" actually got a fix. Null means the
  /// address was typed without one — see the register() call below.
  ManaFix? _gps;

  final _doorNo = TextEditingController();
  final _aadhaar = TextEditingController();
  final _confirmAadhaar = TextEditingController();

  String? _gender;
  // Mandatory at registration (see _missingRequirements). persons.dob stays
  // nullable in the schema because every pre-existing row has a null dob and
  // a NOT NULL would need a backfill nobody can supply; the requirement is
  // enforced here and again server-side in auth-register.
  DateTime? _dob;
  String? _villageId; // set by real village search below (locations table)
  String? _selectedVillageLabel;
  List<Map<String, dynamic>> _villageResults = [];
  final _villageSearch = TextEditingController();
  bool _villageSearchAttempted = false; // true once a real search has run and returned (even if empty)
  bool _manualVillageEntry = false;
  final _manualVillageName = TextEditingController();
  final _manualMandal = TextEditingController();
  final _manualDistrict = TextEditingController();
  final _manualState = TextEditingController();
  String _manualAreaType = 'Village';
  bool _savingManualVillage = false;
  bool _acceptTerms = false;
  bool _acceptPrivacy = false;
  bool _submitting = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscureAadhaar = true;
  bool _obscureConfirmAadhaar = true;

  Uint8List? _livePhotoBytes; // cross-platform (web + mobile) via bytes, not a file path
  String? _aadhaarError;

  // Per Global Rules Guide ADDENDUM v4 (2026-07-20): Aadhaar is now
  // mandatory at direct/self-service registration for every role,
  // superseding ADDENDUM v3's "Customer MLTI permitted" rule. The sole
  // surviving Aadhaar-exempt path is OW-014's Owner-only Pre-Existing
  // Member migration flow, which is a distinct screen — not this one.
  bool get _aadhaarValid {
    final firstDigitValid = _aadhaar.text.isNotEmpty &&
        _aadhaar.text[0] != '0' &&
        _aadhaar.text[0] != '1';
    return _aadhaar.text.length == 12 &&
        _confirmAadhaar.text.length == 12 &&
        _aadhaar.text == _confirmAadhaar.text &&
        firstDigitValid;
  }

  /// Every unmet requirement, in order — shown to the user instead of a
  /// silently-disabled button, so "why can't I submit" is never a mystery.
  List<String> get _missingRequirements {
    final missing = <String>[];
    if (_livePhotoBytes == null) missing.add('Capture live photo');
    if (_surname.text.trim().isEmpty) missing.add('Surname');
    // Given name may be empty — single-name people exist here. The composed
    // name is what has to be substantial.
    if (_composedName.length < 2) missing.add('Name');
    // The canonical name is the one that must match the Aadhaar card and the
    // one every match key is built from, so it is Latin script. Telugu goes in
    // its own field rather than being auto-transliterated into this one.
    if (_containsNonLatinScript(_surname.text) || _containsNonLatinScript(_givenName.text)) {
      missing.add('Surname and Name in English letters (use "Name in Telugu" below for తెలుగు)');
    }
    if (_fatherHusbandName.text.trim().length < 2) missing.add('Father / Husband Name');
    if (_gender == null) missing.add('Gender');
    if (_dob == null) missing.add('Date of Birth');
    if (_mobile.text.trim().length != 10) missing.add('Mobile Number (10 digits)');
    if (_password.text.length < 8) missing.add('Password (min 8 chars, letters + numbers)');
    if (_confirmPassword.text != _password.text || _confirmPassword.text.isEmpty) {
      missing.add('Confirm Password (must match)');
    }
    if (_doorNo.text.trim().isEmpty) missing.add('Door/House No');
    if (_pinCode.text.trim().length != 6) missing.add('PIN Code (6 digits)');
    if (_villageId == null) missing.add('Village');
    if (!_aadhaarValid) {
      missing.add('Aadhaar Number / Confirm Aadhaar (mandatory, 12 digits, matching, cannot start with 0 or 1)');
    }
    if (!_acceptTerms) missing.add('Accept Terms & Conditions');
    if (!_acceptPrivacy) missing.add('Accept Privacy Policy');
    return missing;
  }

  bool get _canSubmit => _missingRequirements.isEmpty;

  Future<void> _captureLivePhoto() async {
    try {
      // BR-036: camera capture only, no gallery upload — this screen never
      // exposes a gallery/file picker at all, on any platform. On top of
      // that base requirement, this now also gates capture on-device face
      // detection (Android/iOS only — see LiveFaceCaptureScreen's own doc
      // comment for the Flutter Web limitation).
      final bytes = await LiveFaceCaptureScreen.capture(context);
      if (bytes == null) return; // user backed out — not an error
      if (!mounted) return;
      setState(() => _livePhotoBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'Could not open camera. On desktop Chrome this needs a webcam and '
          'browser permission; on a phone check camera permission is granted. ($e)',
        )),
      );
    }
  }

  void _onAadhaarChanged() {
    setState(() {
      if (_aadhaar.text.isNotEmpty && (_aadhaar.text[0] == '0' || _aadhaar.text[0] == '1')) {
        _aadhaarError = 'Aadhaar Number cannot start with 0 or 1.';
      } else if (_aadhaar.text.length == 12 &&
          _confirmAadhaar.text.length == 12 &&
          _aadhaar.text != _confirmAadhaar.text) {
        _aadhaarError = 'Aadhaar numbers do not match. Please re-enter.';
      } else {
        _aadhaarError = null;
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);

    // registration_source: passed as 'System' — this screen is a direct
    // self-service registration with no inviting Owner/Agent membership
    // context yet (OW-000 First Business Setup, if any, happens AFTER
    // this). ASSUMPTION flagged for master chat: the
    // registration_source_enum's four values ('Owner','Agent','Migration',
    // 'System') describe who onboarded the person in the schema doc's
    // examples, none of which map cleanly onto "person self-registered via
    // the public app before any business exists" — 'System' is the closest
    // fit but confirm this against actual product intent.
    final genderDigit = _gender ?? '0';

    // RegistrationBlockedException (SP-001 409 collision) must show its
    // OWN generic message, not NetworkErrorHandler's connectivity-worded
    // snackbar. It's caught INSIDE the closure passed to
    // NetworkErrorHandler.run, not in a try/catch wrapped around that
    // call — NetworkErrorHandler.run has its own bare `catch (e)`
    // internally that would otherwise swallow this exception first and
    // convert it into a generic "Something went wrong" SnackBar before it
    // could ever reach an outer catch block, silently defeating the whole
    // point of this exception type. Same pattern already used in
    // lr_011_forgot_pin.dart for the analogous wrong-password case.
    RegisterResult? result;
    RegistrationBlockedException? blocked;
    final reached = await NetworkErrorHandler.run(context, () async {
      try {
        result = await ref.read(authApiServiceProvider).register(
              surname: _surname.text.trim(),
              givenName: _givenName.text.trim(),
              // The Telugu spelling was collected and thrown away before this
              // — the old field blocked the form until it was filled and then
              // never reached the server.
              fullNameLocal: _fullNameLocal.text.trim().isEmpty
                  ? null
                  : _fullNameLocal.text.trim(),
              fatherHusbandName: _fatherHusbandName.text.trim(),
              genderDigit: genderDigit,
              // Date only — persons.dob is a DATE column. Non-null here
              // because _canSubmit gates on it.
              dob: _dob!.toIso8601String().split('T').first,
              mobileNumber: _mobile.text.trim(),
              password: _password.text,
              aadhaarNumber: _aadhaar.text.trim(),
              address: {
                'door_no': _doorNo.text.trim(),
                'pin_code': _pinCode.text.trim(),
                'village_id': _villageId,
                // Only when "Use My Location" actually got a fix. Absent
                // means the address was typed without one, which
                // person_addresses records as NULL rather than pretending
                // to a position it never had.
                if (_gps != null && _gps!.hasPosition) ...{
                  'gps_latitude': _gps!.latitude,
                  'gps_longitude': _gps!.longitude,
                  'gps_accuracy_m': _gps!.accuracyM,
                },
              },
              registrationSource: 'System',
              customerType: 'New',
            );
      } on RegistrationBlockedException catch (e) {
        blocked = e;
      }
      return true; // reached the server either way — not a network failure
    });
    if (!mounted) return;
    if (reached == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown, stay on form
    }
    if (blocked != null) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blocked!.message)));
      return; // SP-001: stop here, never proceed to LR-005 on a real collision
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) return; // defensive


    // Per spec: the soft duplicate_flag (BR-228 fuzzy match) is NEVER
    // surfaced here — proceed to LR-005 exactly as if it weren't set. Only
    // a genuine hard collision (caught above) actually blocks the flow.
    ref.read(authFlowProvider.notifier).setRegistrationResult(
          personId: result!.personId,
          mlid: result!.mlid,
          mlidType: result!.mlidType,
        );
    if (result!.otpId != null) {
      ref.read(authFlowProvider.notifier).setPendingOtpId(result!.otpId!);
    }
    if (_livePhotoBytes != null) {
      ref.read(authFlowProvider.notifier).setPendingProfilePhoto(_livePhotoBytes!);
    }

    if (!mounted) return;
    context.push('/lr-005');
  }

  /// Villages already known for this PIN, from the LGD reference. Fetched once
  /// per PIN and filtered locally: a PIN averages about 45 villages and tops
  /// out at 358, so this is one query and then instant typing.
  final Map<String, List<Map<String, dynamic>>> _lgdByPin = {};

  /// Fill mandal, district and state from what the reference already knows
  /// about this PIN, so the person is not asked to re-type facts the app is
  /// holding.
  ///
  /// ONLY when the PIN's suggestions agree. 8.1% of PIN codes list two
  /// districts after the post-2022 splits, and this screen's whole village
  /// flow is built on "suggest, never decide" — picking one of two districts
  /// on the person's behalf writes a wrong address that nobody reviews.
  /// Never overwrites something already typed.
  void _prefillFromPin() {
    final lgd = _lgdByPin[_pinCode.text.trim()];
    if (lgd == null || lgd.isEmpty) return;

    String? agreed(String key) {
      final values = {
        for (final r in lgd)
          if ((r[key] as String? ?? '').trim().isNotEmpty) (r[key] as String).trim(),
      };
      return values.length == 1 ? values.first : null;
    }

    for (final (controller, key) in [
      (_manualMandal, 'mandal'),
      (_manualDistrict, 'district'),
      (_manualState, 'state'),
    ]) {
      final value = agreed(key);
      if (value != null && controller.text.trim().isEmpty) controller.text = value;
    }
  }

  Future<void> _searchVillages(String query) async {
    final pin = _pinCode.text.trim();
    if (pin.length != 6) {
      setState(() {
        _villageResults = [];
        _villageSearchAttempted = false;
      });
      return;
    }
    if (query.trim().length < 2) {
      setState(() {
        _villageResults = [];
        _villageSearchAttempted = false;
      });
      return;
    }
    try {
      // `locations` holds only the villages some business already operates in
      // — eleven rows for the whole app. Searching it alone is why typing a
      // real village name returned nothing and every registrant was pushed
      // into manual entry. lgd_villages is the reference for exactly this and
      // has 768,529 rows, so the two are merged: places already in use first,
      // because those carry a real location_id, then everything the reference
      // knows about this PIN.
      final known = await Supabase.instance.client
          .from('locations')
          .select('location_id, village_town_name, mandal, district, state')
          .eq('status', 'Active')
          .eq('pin_code', pin)
          .ilike('village_town_name', '%${query.trim()}%')
          .limit(10);

      var lgd = _lgdByPin[pin];
      if (lgd == null) {
        final rows = await Supabase.instance.client
            .schema('app')
            .rpc('suggest_villages', params: {'p_pincode': pin});
        lgd = (rows as List? ?? const []).cast<Map<String, dynamic>>();
        _lgdByPin[pin] = lgd;
      }

      final needle = query.trim().toLowerCase();
      final results = <Map<String, dynamic>>[
        for (final r in (known as List).cast<Map<String, dynamic>>()) r,
      ];
      final alreadyListed = {
        for (final r in results) (r['village_town_name'] as String? ?? '').toLowerCase(),
      };

      for (final r in lgd) {
        if (results.length >= 15) break;
        final name = (r['village'] as String? ?? '').trim();
        if (name.isEmpty || !name.toLowerCase().contains(needle)) continue;
        if (!alreadyListed.add(name.toLowerCase())) continue;
        results.add({
          // No location_id: this one is a suggestion, and the locations row is
          // created only if the person actually picks it.
          'location_id': null,
          'village_town_name': name,
          'mandal': r['mandal'],
          'district': r['district'],
          'state': r['state'],
        });
      }

      if (!mounted) return;
      setState(() {
        _villageResults = results;
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

  /// Turns a chosen row into a real `locations` id. A row that came from the
  /// LGD reference has none until now; `add_location_if_missing` is the same
  /// call the manual-entry path uses, so both routes converge on one row per
  /// (PIN, village) rather than two spellings of the same place.
  Future<void> _selectVillage(Map<String, dynamic> v, String label) async {
    final existing = v['location_id'] as String?;
    if (existing != null) {
      setState(() {
        _villageId = existing;
        _selectedVillageLabel = label;
        _villageSearch.text = v['village_town_name'] as String;
        _villageResults = [];
      });
      return;
    }

    setState(() => _savingManualVillage = true);
    final result = await NetworkErrorHandler.run(context, () async {
      final rows = await Supabase.instance.client.schema('app').rpc('add_location_if_missing', params: {
        'p_pin_code': _pinCode.text.trim(),
        'p_village_town_name': v['village_town_name'],
        'p_area_type': 'Village',
        'p_mandal': v['mandal'],
        'p_district': v['district'],
        'p_state': v['state'],
      });
      return (rows as List).first as Map<String, dynamic>;
    });
    if (!mounted) return;
    setState(() => _savingManualVillage = false);
    if (result == null) return; // network/RPC failure — SnackBar already shown

    setState(() {
      _villageId = result['location_id'] as String;
      _selectedVillageLabel = label;
      _villageSearch.text = v['village_town_name'] as String;
      _villageResults = [];
    });
  }

  Future<void> _saveManualVillage() async {
    if (_manualVillageName.text.trim().isEmpty ||
        _manualMandal.text.trim().isEmpty ||
        _manualDistrict.text.trim().isEmpty ||
        _manualState.text.trim().isEmpty ||
        _pinCode.text.trim().length != 6) {
      return; // button is gated on this too; defensive
    }
    setState(() => _savingManualVillage = true);
    final result = await NetworkErrorHandler.run(context, () async {
      final rows = await Supabase.instance.client.schema('app').rpc('add_location_if_missing', params: {
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
    if (result == null) return; // network/RPC failure — SnackBar already shown

    final label =
        '${_manualVillageName.text.trim()} — ${_manualMandal.text.trim()}, ${_manualDistrict.text.trim()}, ${_manualState.text.trim()}';
    setState(() {
      _villageId = result['location_id'] as String;
      _selectedVillageLabel = label;
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
              : 'Village added and selected.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    final lang = ref.watch(authFlowProvider).language;
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('create_your_account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              ManaSpacing.lg, ManaSpacing.lg, ManaSpacing.lg, 140,
            ),
            children: [
              const _SectionLabel('identity'),
              _LivePhotoCapture(photoBytes: _livePhotoBytes, onCapture: _captureLivePhoto),
              const SizedBox(height: ManaSpacing.md),
              // The notice sits ABOVE the fields, not as helper text under
              // them: it changes how the person fills both boxes in, so they
              // have to read it before typing, not after.
              _AadhaarNameNotice(),
              const SizedBox(height: ManaSpacing.sm),
              TextFormField(
                controller: _surname,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [TitleCaseTextFormatter()],
                decoration: InputDecoration(
                  labelText: ref.t('surname_field'),
                  suffixIcon: ManaInfoHint(ref.t('surname_helper')),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextFormField(
                controller: _givenName,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [TitleCaseTextFormatter()],
                decoration: InputDecoration(labelText: ref.t('name_field')),
                onChanged: (_) => setState(() {}),
              ),
              if (_composedName.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.sm),
                _ComposedNamePreview(name: _composedName),
              ],
              const SizedBox(height: ManaSpacing.md),
              TextFormField(
                controller: _fullNameLocal,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: ref.t('name_in_telugu_optional_field'),
                  suffixIcon: ManaInfoHint(ref.t('name_in_telugu_helper')),
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextFormField(
                controller: _fatherHusbandName,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [TitleCaseTextFormatter()],
                decoration: const InputDecoration(labelText: 'Father / Husband Name *'),
              ),
              const SizedBox(height: ManaSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender *'),
                items: const [
                  DropdownMenuItem(value: '1', child: Text('Male')),
                  DropdownMenuItem(value: '0', child: Text('Female')),
                ],
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: ManaSpacing.md),
              // Label left in English to match the other 16 field labels on
              // this screen, which are not translation-wired yet; wiring one
              // of seventeen would read as an oversight rather than progress.
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date of Birth *'),
                subtitle: Text(
                  _dob == null
                      ? 'Not set'
                      : '${_dob!.day.toString().padLeft(2, '0')}-'
                          '${_dob!.month.toString().padLeft(2, '0')}-${_dob!.year}',
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  // IST, not the handset clock — the same rule as every other
                  // date default in this app. See lib/shared/mana_time.dart.
                  final today = manaNowIst();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dob ?? DateTime(today.year - 30),
                    firstDate: DateTime(today.year - 120),
                    lastDate: today,
                  );
                  if (!mounted) return;
                  if (picked != null) setState(() => _dob = picked);
                },
              ),
              const SizedBox(height: ManaSpacing.xl),

              const _SectionLabel('contact & credentials'),
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: const InputDecoration(labelText: 'Mobile Number *'),
              ),
              TextFormField(
                controller: _password,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password *',
                  helperText: 'At least 8 characters, with letters and numbers.',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextFormField(
                controller: _confirmPassword,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm Password *',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ),
              ),
              const SizedBox(height: ManaSpacing.xl),

              const _SectionLabel('address'),
              // Fills PIN and village from where the person is standing, and
              // keeps the coordinates. Everything it writes stays editable —
              // the geocoder is often vague in a village, so it is a
              // shortcut, never the final word. See UseMyLocationButton.
              UseMyLocationButton(
                onCaptured: (place) {
                  setState(() {
                    _gps = place.fix;
                    if (place.pinCode != null) _pinCode.text = place.pinCode!;
                    if (place.village != null) {
                      _villageSearch.text = place.village!;
                      // A typed village id no longer matches the new name.
                      _villageId = null;
                      _selectedVillageLabel = null;
                    }
                  });
                  if (_pinCode.text.trim().length == 6) {
                    _searchVillages(_villageSearch.text);
                  }
                },
              ),
              TextFormField(
                controller: _doorNo,
                decoration: const InputDecoration(labelText: 'Door / House No *'),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextFormField(
                controller: _pinCode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'PIN Code *', suffixIcon: ManaInfoHint('Enter PIN code first — villages shown are limited to this PIN'),),
                onChanged: (_) {
                  setState(() {
                    _villageId = null;
                    _selectedVillageLabel = null;
                  });
                  _searchVillages(_villageSearch.text);
                },
              ),
              TextFormField(
                controller: _villageSearch,
                decoration: const InputDecoration(labelText: 'Search Village/Town *'),
                onChanged: (v) {
                  setState(() {
                    _villageId = null;
                    _selectedVillageLabel = null;
                    _manualVillageEntry = false;
                  });
                  _searchVillages(v);
                },
              ),
              if (_villageResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  margin: const EdgeInsets.only(top: ManaSpacing.xs),
                  decoration: BoxDecoration(border: Border.all(color: ManaColors.surfaceSunken)),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _villageResults.length,
                    itemBuilder: (_, i) {
                      final v = _villageResults[i];
                      final label = '${v['village_town_name']} — ${v['mandal']}, ${v['district']}, ${v['state']}';
                      return ListTile(
                        dense: true,
                        title: ManaText.raw(label, style: ManaType.small),
                        // A row from the LGD reference has no location_id yet.
                        // It gets one the moment it is chosen, not before —
                        // otherwise browsing the list would seed `locations`
                        // with every village someone scrolled past.
                        subtitle: v['location_id'] == null
                            ? ManaText.raw('From the village list',
                                style: TextStyle(fontSize: 11, color: ManaColors.textSecondary))
                            : null,
                        onTap: () => _selectVillage(v, label),
                      );
                    },
                  ),
                ),
              if (_villageSearchAttempted && _villageResults.isEmpty && _villageId == null && !_manualVillageEntry)
                Padding(
                  padding: const EdgeInsets.only(top: ManaSpacing.xs),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: ManaColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextButton(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                          onPressed: () => setState(() {
                            _manualVillageEntry = true;
                            _manualVillageName.text = _villageSearch.text.trim();
                            _prefillFromPin();
                          }),
                          child: Text('"${_villageSearch.text.trim()}" not found — add it'),
                        ),
                      ),
                    ],
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
                      ManaText.raw(ref.t('add_new_village'), style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: ManaSpacing.sm),
                      TextField(
                        controller: _manualVillageName,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Village/Town Name *'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      DropdownButtonFormField<String>(
                        initialValue: _manualAreaType,
                        decoration: const InputDecoration(labelText: 'Area Type *'),
                        items: const [
                          DropdownMenuItem(value: 'Village', child: Text('Village')),
                          DropdownMenuItem(value: 'Town', child: Text('Town')),
                        ],
                        onChanged: (v) => setState(() => _manualAreaType = v ?? 'Village'),
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
                      ManaText.raw(
                        'PIN Code above (${_pinCode.text.trim().isEmpty ? "not yet entered" : _pinCode.text.trim()}) will be used for this village.',
                        style: ManaType.note,
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _savingManualVillage ? null : () => setState(() => _manualVillageEntry = false),
                            child: ManaText.raw(ref.t('cancel')),
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
                                    height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : ManaText.raw(ref.t('save_and_select')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_selectedVillageLabel != null) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw('Selected: $_selectedVillageLabel',
                    style: ManaType.note),
              ],
              const SizedBox(height: ManaSpacing.xl),

              const _SectionLabel('verification'),
              TextFormField(
                controller: _aadhaar,
                obscureText: _obscureAadhaar,
                keyboardType: TextInputType.number,
                maxLength: 12,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _AadhaarFirstDigitFormatter(),
                ],
                onChanged: (_) => _onAadhaarChanged(),
                decoration: InputDecoration(
                  labelText: 'Aadhaar Number *',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureAadhaar ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureAadhaar = !_obscureAadhaar),
                  ),
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextFormField(
                controller: _confirmAadhaar,
                obscureText: _obscureConfirmAadhaar,
                keyboardType: TextInputType.number,
                maxLength: 12,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _onAadhaarChanged(),
                decoration: InputDecoration(
                  labelText: 'Confirm Aadhaar Number *',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmAadhaar ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirmAadhaar = !_obscureConfirmAadhaar),
                  ),
                ),
              ),
              if (_aadhaarError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ManaText.raw(_aadhaarError!,
                      style: ManaType.noteBad),
                ),
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(
                'Enter your Aadhaar Number carefully. Incorrect entry may result '
                'in account suspension until resolved.',
                style: ManaType.noteWarn,
              ),
              const SizedBox(height: ManaSpacing.lg),

              CheckboxListTile(
                value: _acceptTerms,
                onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                title: ManaText.raw(ref.t('accept_terms_conditions')),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _acceptPrivacy,
                onChanged: (v) => setState(() => _acceptPrivacy = v ?? false),
                title: ManaText.raw(ref.t('accept_privacy_policy')),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),

              // Visible checklist — replaces "button is silently disabled,
              // guess why" with an explicit list of what's left.
              if (_missingRequirements.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  decoration: BoxDecoration(
                    color: ManaColors.statusWarnFaint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(ref.t('still_needed_to_register'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      ..._missingRequirements.map(
                        (m) => ManaText.raw('• $m', style: ManaType.small),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: ManaSpacing.lg),
              Align(
                alignment: Alignment.center,
                child: ManaLanguageSelector(
                  current: lang,
                  onChanged: (l) => ref.read(authFlowProvider.notifier).setLanguage(l),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: ElevatedButton(
            onPressed: (_canSubmit && !_submitting) ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : ManaText.raw(ref.t('register')),
          ),
        ),
      ),
    );
  }
}

/// The Aadhaar warning that governs both name fields.
///
/// Worded "can lead to" rather than "leads to" on purpose: suspension is the
/// outcome of a human comparing the name to the document, not something the
/// app does on its own. Promising an automatic consequence that nothing
/// implements is how a notice becomes background noise.
class _AadhaarNameNotice extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.statusWarn.withValues(alpha: 0.10),
        border: Border.all(color: ManaColors.statusWarn),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.badge_outlined, size: 18, color: ManaColors.statusWarn),
          const SizedBox(width: ManaSpacing.sm),
          // Expanded, not a bare Text: this is a long translated string beside
          // a fixed-width icon, which is the exact shape that overflows here.
          Expanded(
            child: ManaText.raw(
              ref.t('aadhaar_name_notice'),
              style: ManaType.small,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows surname and given name joined exactly as they will be stored.
///
/// Aadhaar has ONE name box. Splitting it into two is this app's idea, so the
/// person is asked to check the joined result against their card rather than
/// to reason about where their own name divides.
class _ComposedNamePreview extends ConsumerWidget {
  final String name;
  const _ComposedNamePreview({required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.subdirectory_arrow_right,
            size: 16, color: ManaColors.textSecondary),
        const SizedBox(width: ManaSpacing.xs),
        Expanded(
          child: ManaText.raw(
            '${ref.t('will_be_saved_as')} $name',
            style: ManaType.note,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: ManaSpacing.sm),
        child: ManaText(label, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _LivePhotoCapture extends ConsumerWidget {
  final Uint8List? photoBytes;
  final VoidCallback onCapture;
  const _LivePhotoCapture({required this.photoBytes, required this.onCapture});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (photoBytes == null) {
      return OutlinedButton.icon(
        onPressed: onCapture,
        icon: const Icon(Icons.camera_alt),
        label: ManaText.raw(ref.t('capture_live_photo')),
      );
    }
    return Row(
      children: [
        CircleAvatar(radius: 28, backgroundImage: MemoryImage(photoBytes!)),
        const SizedBox(width: ManaSpacing.md),
        TextButton.icon(
          onPressed: onCapture,
          icon: const Icon(Icons.refresh, size: 18),
          label: ManaText.raw(ref.t('retake_photo')),
        ),
      ],
    );
  }
}

/// Blocks the very first digit of Aadhaar entry from being 0 or 1 —
/// rejects at the point of typing rather than letting it through and
/// showing an error message afterward. UIDAI allocation rule, locked
/// in Global Rules Guide ADDENDUM v4.
class _AadhaarFirstDigitFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isNotEmpty &&
        (newValue.text[0] == '0' || newValue.text[0] == '1')) {
      return oldValue; // reject the keystroke, keep the field as it was
    }
    return newValue;
  }
}
