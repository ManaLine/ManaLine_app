import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../../../shared/location_api_service.dart';
import '../../../shared/widgets/village_search_field.dart';

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
    _doorNo.dispose();
    _aadhaar.dispose();
    _confirmAadhaar.dispose();
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
  String? _villageId; // set by ManaVillageSearchField below (locations table)
  /// The PIN the geocoder last read back, seeded into the village search.
  String? _geocodedPin;
  String? _selectedVillageLabel;
  // The submitted pin_code comes from the picked village's directory row,
  // not a screen-typed box — ManaVillageSearchField owns PIN entry now (its
  // PIN mode embeds ManaVillagePickerField, which renders the PIN field).
  // See _onVillagePicked.
  String? _villagePinCode;
  // Re-keyed after a GPS fix so the search field starts over from the fresh
  // PIN, rather than keep a search typed against wherever it was before.
  Key _villageFieldKey = UniqueKey();
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
    if (_villageId == null || _villagePinCode == null) missing.add('Village');
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
      // BR-036: camera capture only, no gallery upload, on Android/iOS —
      // this also gates capture on on-device face detection there. Web has
      // no camera plugin to open at all, so LiveFaceCaptureScreen shows a
      // file picker instead on that platform only; see its own doc comment
      // for why that is not a relaxation of BR-036.
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
    // Non-null because _missingRequirements gates on it, the same way _dob!
    // below is. The `?? '0'` that used to be here defaulted an unanswered
    // question to Female; harmless while unreachable, and exactly the shape
    // of default that becomes a wrong permanent MLID digit the moment
    // somebody relaxes the gate.
    final genderDigit = _gender!;

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
                'pin_code': _villagePinCode ?? '',
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
    // auth-register deliberately does NOT send the OTP. Its own header says so:
    // identity creation is kept decoupled from the SMS gateway, so a gateway
    // outage can never block account creation. It always answers
    // `otp_id: null` and expects this caller to make the send call.
    //
    // That call was never written. The guard below read `if (otpId != null)`,
    // found null every single time, skipped silently, and pushed to LR-005
    // anyway — where the screen found no pending OTP and blamed a page refresh:
    // "Your verification session was lost — this happens if the page was
    // refreshed or reopened directly." On a phone there is no page to refresh.
    // The message was describing a browser failure mode for a bug that hit
    // every registrant on every platform, which is why it read as unrelated.
    //
    // NOBODY COULD REGISTER, and the error explained a cause that could not
    // have occurred.
    final otpId = result!.otpId ??
        await NetworkErrorHandler.run(
          context,
          () => ref.read(authApiServiceProvider).sendOtp(
                personId: result!.personId,
                // A real otp_purpose_enum label, read from enum_range.
                purpose: 'Registration',
              ),
        );
    if (!mounted) return;

    // A failed send does NOT go back to the form. The account already exists,
    // so pressing Submit again registers the same person a second time and
    // collides with the one just created (SP-001 blocks it outright). LR-005
    // still has the personId, so its Resend is a working way out — and its
    // no-otp message now says so instead of blaming a refresh.
    if (otpId != null) {
      ref.read(authFlowProvider.notifier).setPendingOtpId(otpId);
    }
    if (_livePhotoBytes != null) {
      ref.read(authFlowProvider.notifier).setPendingProfilePhoto(_livePhotoBytes!);
    }

    if (!mounted) return;
    context.push('/lr-005');
  }

  /// A picked reference row has no `location_id` until it is resolved — same
  /// contract [ManaVillagePickerField] documents: it does not write anything,
  /// so a caller that needs the id resolves it. `resolveId` writes with
  /// source 'Directory', the same provenance this screen's own manual resolve
  /// used to record — chosen from the reference, not typed.
  Future<void> _onVillagePicked(ManaVillage? v) async {
    if (v == null) {
      setState(() {
        _villageId = null;
        _selectedVillageLabel = null;
        _villagePinCode = null;
      });
      return;
    }
    var id = v.locationId;
    if (id.isEmpty) {
      final result = await NetworkErrorHandler.run(
          context, () => ref.read(locationApiServiceProvider).resolveId(v));
      if (result == null || !mounted) return; // network failure — already shown
      id = result;
    }
    if (!mounted) return;
    final label = [v.name, v.mandal, v.district, v.state]
        .where((s) => s.trim().isNotEmpty)
        .join(' — ');
    setState(() {
      _villageId = id;
      _selectedVillageLabel = label;
      if (v.pinCode.isNotEmpty) _villagePinCode = v.pinCode;
    });
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
                // isExpanded: a DropdownButton sizes to its widest item and
                // overflows rather than shrinking -- measured at 1.0x on OW-002.
                isExpanded: true,
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender *'),
                // The VALUES are translated, unlike the field labels around
                // them: a person choosing their own gender is choosing
                // between these three words, and 'Male'/'Female' in English
                // on a Telugu handset is a choice made blind. 1 Male,
                // 0 Female, 2 Others -- the digit goes into the MLID.
                items: [
                  DropdownMenuItem(value: '1', child: ManaText.raw(ref.t('male'))),
                  DropdownMenuItem(value: '0', child: ManaText.raw(ref.t('female'))),
                  DropdownMenuItem(value: '2', child: ManaText.raw(ref.t('others'))),
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
                    // The geocoder's name is not typed into the village box.
                    // At a doorstep it usually returns the colony, which is
                    // not in the directory under any PIN, so a typed name
                    // could never match. The PIN, however, IS carried in:
                    // the search field has taken an `initialPin` since before
                    // this comment claimed it had no hook for one.
                    //
                    // It fills the PIN and stops. A PIN alone does not search
                    // -- the village still needs three letters typed, which
                    // village_search_rule_test guards -- because one PIN can
                    // carry fifty villages.
                    _villageId = null;
                    _selectedVillageLabel = null;
                    _villagePinCode = null;
                    _geocodedPin = place.pinCode;
                    _villageFieldKey = UniqueKey();
                  });
                },
              ),
              TextFormField(
                controller: _doorNo,
                decoration: const InputDecoration(labelText: 'Door / House No *'),
              ),
              const SizedBox(height: ManaSpacing.md),
              ManaVillageSearchField(
                key: _villageFieldKey,
                label: 'Search Village/Town *',
                initialPin: _geocodedPin,
                onPicked: _onVillagePicked,
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

              // The "still needed to register" checklist is gone, at the
              // Owner's instruction: the button simply stays disabled until
              // every required field is filled.
              //
              // WHAT THAT COSTS, written down rather than discovered later:
              // the block it replaces existed to answer "the button is
              // disabled, guess why". The form's own asterisks are now the
              // only thing saying which fields are required, and nothing
              // names the one that is still empty. _missingRequirements is
              // KEPT and still gates _canSubmit, so if that question ever
              // comes back the answer is already computed -- as per-field
              // error text, which is where it belongs, rather than a warning
              // block stacked under the form.
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
