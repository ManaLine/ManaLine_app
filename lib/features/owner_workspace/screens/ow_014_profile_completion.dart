import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/add_village_if_missing.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/live_photo_upload.dart';
import '../state/global_workflow_state.dart';
import '../../../design/components/mana_info_hint.dart';

/// OW-014 Profile Completion sub-flow — the destination for the "Complete
/// Profile" tile on OW-014's Incomplete step, which previously fired a
/// SnackBar saying the sub-flow was out of scope.
///
/// Splits the tile's own list of fields by who is actually able to supply
/// them. Owner-capturable (real writes, all via migration-0053 RPCs since
/// 0012's RLS makes the equivalent raw-table writes self-only):
///   Photo · Address + PIN Code + Village · Identity Documents · Mobile
///   · DOB · Aadhaar
/// Member-only, shown read-only rather than faked:
///   Password / PIN — set by the member at LR-007 First Login
///   OTP Verification — otp_verifications is self-only by design
///   Terms Acceptance — agreement_acceptances.otp_id is NOT NULL, i.e. the
///   schema itself requires the member's own verified OTP
///
/// The terminal action reports back whichever status the server applied:
/// 'Complete' when the member-side steps are done too, otherwise
/// 'Pending Verification'.
class ProfileCompletionScreen extends ConsumerStatefulWidget {
  final String personId;
  final String membershipId;

  const ProfileCompletionScreen({
    super.key,
    required this.personId,
    required this.membershipId,
  });

  @override
  ConsumerState<ProfileCompletionScreen> createState() => _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends ConsumerState<ProfileCompletionScreen> {
  late Future<MemberProfileChecklist> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MemberProfileChecklist> _load() {
    return ref.read(globalWorkflowApiServiceProvider).fetchProfileChecklist(personId: widget.personId);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- Photo ---------------------------------------------------------------
  // Bucket path '<person_id>/photo.jpg' matches 0040's convention exactly;
  // 0053 adds the Owner-on-member policies that let this Owner write into
  // another person's folder (0040's own policies are self-scoped).
  Future<void> _capturePhoto() => _guard(() async {
        final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
        if (picked == null || !mounted) return;
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        final ok = await NetworkErrorHandler.run(context, () async {
          // Signed, not public — the bucket is private and holds photos of
          // real people. Same 1-year expiry + re-sign caveat as
          // LivePhotoUpload; see that class's doc comment.
          final url = await ProfilePhotoUpload.upload(
            bytes: bytes,
            personId: widget.personId,
          );
          await ref
              .read(globalWorkflowApiServiceProvider)
              .updateMemberIdentity(personId: widget.personId, profilePhotoUrl: url);
          return true;
        });
        if (ok == true) _reload();
      });

  // --- Address -------------------------------------------------------------
  Future<void> _editAddress() => _guard(() async {
        final result = await showDialog<_AddressResult>(
          context: context,
          builder: (_) => const _AddressDialog(),
        );
        if (result == null || !mounted) return;
        final ok = await NetworkErrorHandler.run(context, () async {
          await ref.read(globalWorkflowApiServiceProvider).submitAddress(
                personId: widget.personId,
                doorNo: result.doorNo,
                pinCode: result.pinCode,
                villageId: result.villageId,
              );
          return true;
        });
        if (ok == true) _reload();
      });

  // --- Identity document ---------------------------------------------------
  Future<void> _uploadDocument() => _guard(() async {
        final type = await showDialog<String>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: ManaText.raw(ref.t('document_type')),
            children: [
              // Exactly identity_document_type_enum (migration 0001) — the
              // RPC param is that enum, so an off-list value is a 22P02.
              for (final t in const ['Aadhaar', 'Photo', 'Address Proof', 'Other'])
                SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(t),
                  child: ManaText.raw(t),
                ),
            ],
          ),
        );
        if (type == null || !mounted) return;
        final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked == null || !mounted) return;
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        final ok = await NetworkErrorHandler.run(context, () async {
          final storage = Supabase.instance.client.storage.from('member-documents');
          final slug = type.toLowerCase().replaceAll(' ', '-');
          final path = '${widget.personId}/$slug-${DateTime.now().millisecondsSinceEpoch}.jpg';
          await storage.uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
          // The path, not a year-long signed URL. These are identity
          // documents -- see ManaStoredFile.
          await ref
              .read(globalWorkflowApiServiceProvider)
              .submitDocument(personId: widget.personId, documentType: type, fileUrl: path);
          return true;
        });
        if (ok == true) _reload();
      });

  // --- Contact / identity fields ------------------------------------------
  Future<void> _editContact() => _guard(() async {
        final result = await showDialog<_ContactResult>(
          context: context,
          builder: (_) => const _ContactDialog(),
        );
        if (result == null || !mounted) return;
        final ok = await NetworkErrorHandler.run(context, () async {
          await ref.read(globalWorkflowApiServiceProvider).updateMemberIdentity(
                personId: widget.personId,
                mobileNumber: result.mobileNumber,
                dob: result.dob,
                aadhaarNumber: result.aadhaarNumber,
              );
          return true;
        });
        if (ok == true) _reload();
      });

  // --- Terminal step -------------------------------------------------------
  Future<void> _markComplete() => _guard(() async {
        final status = await NetworkErrorHandler.run(context, () async {
          return ref
              .read(globalWorkflowApiServiceProvider)
              .markProfileComplete(personId: widget.personId, membershipId: widget.membershipId);
        });
        if (status == null || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'Complete'
                ? 'Profile marked Complete.'
                : 'Owner-side capture done — profile is now Pending Verification until the member '
                    'sets a password/PIN and accepts the terms on their own device.'),
          ),
        );
        _reload();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('complete_profile')),
      body: SafeArea(
        child: FutureBuilder<MemberProfileChecklist>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                child: ManaText.raw(
                  ref.t('could_not_load_profile_note').replaceAll('{error}', '${snapshot.error}'),
                  textAlign: TextAlign.center,
                  style: ManaType.noteBad,
                ),
              );
            }
            final c = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              children: [
                ManaText.raw(c.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                ManaText.raw('${c.mlid} · ${c.profileStatus}',
                    style: ManaType.note),
                const SizedBox(height: ManaSpacing.lg),
                ManaText.raw(ref.t('owner_captured'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: ManaSpacing.sm),
                _StepTile(
                  done: c.hasPhoto,
                  icon: Icons.camera_alt_outlined,
                  title: ref.t('profile_photo'),
                  subtitle: c.hasPhoto ? ref.t('captured_tap_retake') : ref.t('required_label'),
                  onTap: _busy ? null : _capturePhoto,
                ),
                _StepTile(
                  done: c.hasAddress,
                  icon: Icons.home_outlined,
                  title: ref.t('address_pin_village'),
                  subtitle: c.addressSummary ?? ref.t('required_label'),
                  onTap: _busy ? null : _editAddress,
                ),
                _StepTile(
                  done: c.hasDocument,
                  icon: Icons.description_outlined,
                  title: ref.t('identity_documents'),
                  subtitle: c.hasDocument ? ref.t('on_file_tap_add_another') : ref.t('required_label'),
                  onTap: _busy ? null : _uploadDocument,
                ),
                _StepTile(
                  done: c.hasMobile,
                  icon: Icons.badge_outlined,
                  title: ref.t('mobile_dob_aadhaar'),
                  subtitle: c.hasMobile ? ref.t('mobile_on_file_tap_edit') : ref.t('optional_needed_for_sms'),
                  onTap: _busy ? null : _editContact,
                ),
                const SizedBox(height: ManaSpacing.lg),
                ManaText.raw(ref.t('member_completes_these'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(
                  ref.t('member_completes_note'),
                  style: ManaType.note,
                ),
                const SizedBox(height: ManaSpacing.sm),
                _StepTile(
                  done: c.hasCredential,
                  icon: Icons.lock_outline,
                  title: ref.t('password_pin'),
                  subtitle: c.hasCredential ? ref.t('set_by_member') : ref.t('member_sets_at_first_login'),
                  onTap: null,
                ),
                _StepTile(
                  done: c.termsAccepted,
                  icon: Icons.gavel_outlined,
                  title: ref.t('otp_terms_acceptance'),
                  subtitle: c.termsAccepted ? ref.t('accepted_by_member') : ref.t('requires_member_own_otp'),
                  onTap: null,
                ),
                const SizedBox(height: ManaSpacing.xl),
                FilledButton(
                  onPressed: _busy || !c.ownerStepsDone ? null : _markComplete,
                  child: ManaText.raw(ref.t('mark_profile_complete')),
                ),
                if (!c.ownerStepsDone) ...[
                  const SizedBox(height: ManaSpacing.sm),
                  ManaText.raw(
                    ref.t('owner_steps_required_note'),
                    style: ManaType.note,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final bool done;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _StepTile({
    required this.done,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        leading: Icon(icon, color: done ? ManaColors.statusGood : ManaColors.brand),
        title: ManaText.raw(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: ManaText.raw(subtitle, style: ManaType.small),
        trailing: done
            ? Icon(Icons.check_circle, color: ManaColors.statusGood, size: 20)
            : (onTap == null ? null : const Icon(Icons.chevron_right)),
        onTap: onTap,
      ),
    );
  }
}

// --- Address dialog ---------------------------------------------------------
// Same PIN -> village -> "not found, add it" flow as OW-016's address editor
// (ow_016_profile.dart), including the add_location_if_missing fallback
// (migration 0038) so an unlisted village doesn't dead-end the Owner.

class _AddressResult {
  final String doorNo;
  final String pinCode;
  final String villageId;
  const _AddressResult({required this.doorNo, required this.pinCode, required this.villageId});
}

class _AddressDialog extends ConsumerStatefulWidget {
  const _AddressDialog();

  @override
  ConsumerState<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends ConsumerState<_AddressDialog> {

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _doorNo.dispose();
    _pinCode.dispose();
    _villageSearch.dispose();
    _manualName.dispose();
    _manualMandal.dispose();
    _manualDistrict.dispose();
    _manualState.dispose();
    super.dispose();
  }
  final _doorNo = TextEditingController();
  final _pinCode = TextEditingController();
  final _villageSearch = TextEditingController();

  Map<String, dynamic>? _selectedVillage;
  List<Map<String, dynamic>> _villageResults = [];
  bool _searchAttempted = false;
  bool _manualEntry = false;
  final _manualName = TextEditingController();
  final _manualMandal = TextEditingController();
  final _manualDistrict = TextEditingController();
  final _manualState = TextEditingController();
  bool _savingManual = false;

  Future<void> _searchVillages(String query) async {
    final pin = _pinCode.text.trim();
    if (query.trim().length < 2 || pin.length != 6) {
      setState(() {
        _villageResults = [];
        _searchAttempted = false;
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
        _searchAttempted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _villageResults = [];
        _searchAttempted = true;
      });
    }
  }

  Future<void> _saveManualVillage() async {
    // No inline guard here, unlike the other three copies: this screen gates
    // validity at the button with _manualComplete, so reaching this method
    // already means the fields are filled.
    setState(() => _savingManual = true);

    // Shared, so the four copies of this cannot drift apart again -- and so
    // that a failure is always SAID. The catch here used to be `catch (_)`
    // with nothing but the spinner clearing.
    final locationId = await manaAddVillageIfMissing(
      context,
      ref,
      pinCode: _pinCode.text.trim(),
      villageTownName: _manualName.text.trim(),
      // Always a village. The dropdown that used to ask offered Village or
      // Town, changed nothing anywhere in the app, and every directory pick
      // hardcoded 'Village' regardless.
      areaType: 'Village',
      mandal: _manualMandal.text.trim(),
      district: _manualDistrict.text.trim(),
      state: _manualState.text.trim(),
    );

    if (!mounted) return;
    setState(() => _savingManual = false);
    if (locationId == null) return;

    setState(() {
      _selectedVillage = {
        'location_id': locationId,
        'village_town_name': _manualName.text.trim(),
        'mandal': _manualMandal.text.trim(),
        'district': _manualDistrict.text.trim(),
        'state': _manualState.text.trim(),
      };
      _villageSearch.text = _manualName.text.trim();
      _villageResults = [];
      _manualEntry = false;
    });
  }

  bool get _manualComplete =>
      _manualName.text.trim().isNotEmpty &&
      _manualMandal.text.trim().isNotEmpty &&
      _manualDistrict.text.trim().isNotEmpty &&
      _manualState.text.trim().isNotEmpty &&
      _pinCode.text.trim().length == 6;

  @override
  Widget build(BuildContext context) {
    final canSave =
        _doorNo.text.trim().isNotEmpty && _pinCode.text.trim().length == 6 && _selectedVillage != null;
    return AlertDialog(
      title: ManaText.raw(ref.t('address')),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _doorNo,
                decoration: InputDecoration(labelText: ref.t('door_house_no_field'), isDense: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.sm),
              TextField(
                controller: _pinCode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: ref.t('pin_code_required_field'),
                  isDense: true,
                  suffixIcon: ManaInfoHint(ref.t('villages_limited_to_pin_helper')),
                ),
                onChanged: (_) {
                  setState(() => _selectedVillage = null);
                  _searchVillages(_villageSearch.text);
                },
              ),
              TextField(
                controller: _villageSearch,
                decoration: InputDecoration(labelText: ref.t('search_village_town_field'), isDense: true),
                onChanged: (v) {
                  setState(() {
                    _selectedVillage = null;
                    _manualEntry = false;
                  });
                  _searchVillages(v);
                },
              ),
              if (_villageResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  margin: const EdgeInsets.only(top: ManaSpacing.xs),
                  decoration: BoxDecoration(border: Border.all(color: ManaColors.surfaceSunken)),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _villageResults.length,
                    itemBuilder: (_, i) {
                      final v = _villageResults[i];
                      return ListTile(
                        dense: true,
                        title: ManaText.raw(
                          '${v['village_town_name']} — ${v['mandal']}, ${v['district']}, ${v['state']}',
                          style: ManaType.small,
                        ),
                        onTap: () => setState(() {
                          _selectedVillage = v;
                          _villageSearch.text = v['village_town_name'] as String;
                          _villageResults = [];
                        }),
                      );
                    },
                  ),
                ),
              if (_searchAttempted && _villageResults.isEmpty && _selectedVillage == null && !_manualEntry)
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                  onPressed: () => setState(() {
                    _manualEntry = true;
                    _manualName.text = _villageSearch.text.trim();
                  }),
                  child: ManaText.raw(
                      ref.t('village_not_found_add_it').replaceAll('{query}', _villageSearch.text.trim())),
                ),
              if (_manualEntry) ...[
                const SizedBox(height: ManaSpacing.xs),
                TextField(
                  controller: _manualName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('village_town_name_field'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.xs),
                TextField(
                  controller: _manualMandal,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('mandal_field'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.xs),
                TextField(
                  controller: _manualDistrict,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('district_field'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.xs),
                TextField(
                  controller: _manualState,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('state_field'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _savingManual ? null : () => setState(() => _manualEntry = false),
                      child: ManaText.raw(ref.t('cancel')),
                    ),
                    ElevatedButton(
                      onPressed: _savingManual || !_manualComplete ? null : _saveManualVillage,
                      child: _savingManual
                          ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : ManaText.raw(ref.t('save_and_select')),
                    ),
                  ],
                ),
              ],
              if (_selectedVillage != null) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(
                  ref.t('selected_note').replaceAll('{value}',
                      '${_selectedVillage!['village_town_name']} — ${_selectedVillage!['mandal']}, '
                      '${_selectedVillage!['district']}, ${_selectedVillage!['state']}'),
                  style: ManaType.note,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: ManaText.raw(ref.t('cancel'))),
        ElevatedButton(
          onPressed: canSave
              ? () => Navigator.pop(
                    context,
                    _AddressResult(
                      doorNo: _doorNo.text.trim(),
                      pinCode: _pinCode.text.trim(),
                      villageId: _selectedVillage!['location_id'] as String,
                    ),
                  )
              : null,
          child: ManaText.raw(ref.t('save')),
        ),
      ],
    );
  }
}

// --- Contact / identity dialog ---------------------------------------------
// All three fields are optional and NULL-skipped by
// app.owner_update_member_identity's COALESCE, so leaving one blank leaves
// the stored value alone rather than clearing it.

class _ContactResult {
  final String? mobileNumber;
  final String? dob;
  final String? aadhaarNumber;
  const _ContactResult({this.mobileNumber, this.dob, this.aadhaarNumber});
}

class _ContactDialog extends ConsumerStatefulWidget {
  const _ContactDialog();

  @override
  ConsumerState<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends ConsumerState<_ContactDialog> {

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _mobile.dispose();
    _aadhaar.dispose();
    super.dispose();
  }
  final _mobile = TextEditingController();
  final _aadhaar = TextEditingController();
  DateTime? _dob;

  @override
  Widget build(BuildContext context) {
    final mobile = _mobile.text.trim();
    final aadhaar = _aadhaar.text.trim();
    final mobileValid = mobile.isEmpty || mobile.length == 10;
    final aadhaarValid = aadhaar.isEmpty || aadhaar.length == 12;
    final anything = mobile.isNotEmpty || aadhaar.isNotEmpty || _dob != null;

    return AlertDialog(
      title: ManaText.raw(ref.t('contact_and_identity')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(
              ref.t('blank_fields_unchanged_note'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: ref.t('mobile_number_field'),
                isDense: true,
                errorText: mobileValid ? null : ref.t('must_be_10_digits'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _aadhaar,
              keyboardType: TextInputType.number,
              maxLength: 12,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: ref.t('aadhaar_number_field'),
                isDense: true,
                errorText: aadhaarValid ? null : ref.t('must_be_12_digits'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: ManaText.raw(
                    _dob == null
                        ? ref.t('dob_not_set')
                        : ref.t('dob_value_note').replaceAll(
                            '{date}', _dob!.toIso8601String().split('T').first),
                    style: ManaType.small,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dob ?? DateTime(now.year - 30),
                      firstDate: DateTime(now.year - 100),
                      lastDate: now,
                    );
                    if (!mounted) return;
                    if (picked != null) setState(() => _dob = picked);
                  },
                  child: ManaText.raw(ref.t('pick')),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: ManaText.raw(ref.t('cancel'))),
        ElevatedButton(
          onPressed: !anything || !mobileValid || !aadhaarValid
              ? null
              : () => Navigator.pop(
                    context,
                    _ContactResult(
                      mobileNumber: mobile.isEmpty ? null : mobile,
                      aadhaarNumber: aadhaar.isEmpty ? null : aadhaar,
                      dob: _dob?.toIso8601String().split('T').first,
                    ),
                  ),
          child: ManaText.raw(ref.t('save')),
        ),
      ],
    );
  }
}
