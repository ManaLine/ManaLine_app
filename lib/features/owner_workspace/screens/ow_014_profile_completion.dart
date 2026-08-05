import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/live_photo_upload.dart';
import '../state/global_workflow_state.dart';

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
            title: const ManaText('document type'),
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
          final url = await storage.createSignedUrl(path, 60 * 60 * 24 * 365);
          await ref
              .read(globalWorkflowApiServiceProvider)
              .submitDocument(personId: widget.personId, documentType: type, fileUrl: url);
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
      appBar: AppBar(title: const ManaText('complete profile')),
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
                  'Could not load this profile.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ManaColors.statusBad, fontSize: 13),
                ),
              );
            }
            final c = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              children: [
                ManaText.raw(c.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                ManaText.raw('${c.mlid} · ${c.profileStatus}',
                    style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                const SizedBox(height: ManaSpacing.lg),
                const ManaText('owner captured', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: ManaSpacing.sm),
                _StepTile(
                  done: c.hasPhoto,
                  icon: Icons.camera_alt_outlined,
                  title: 'Profile Photo',
                  subtitle: c.hasPhoto ? 'Captured — tap to retake' : 'Required',
                  onTap: _busy ? null : _capturePhoto,
                ),
                _StepTile(
                  done: c.hasAddress,
                  icon: Icons.home_outlined,
                  title: 'Address · PIN Code · Village',
                  subtitle: c.addressSummary ?? 'Required',
                  onTap: _busy ? null : _editAddress,
                ),
                _StepTile(
                  done: c.hasDocument,
                  icon: Icons.description_outlined,
                  title: 'Identity Documents',
                  subtitle: c.hasDocument ? 'On file — tap to add another' : 'Required',
                  onTap: _busy ? null : _uploadDocument,
                ),
                _StepTile(
                  done: c.hasMobile,
                  icon: Icons.badge_outlined,
                  title: 'Mobile · DOB · Aadhaar',
                  subtitle: c.hasMobile ? 'Mobile on file — tap to edit' : 'Optional, but needed for SMS/OTP',
                  onTap: _busy ? null : _editContact,
                ),
                const SizedBox(height: ManaSpacing.lg),
                const ManaText('member completes these', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: ManaSpacing.xs),
                const ManaText.raw(
                  'These cannot be done on the member\'s behalf — the credential is theirs to set and the '
                  'OTP goes to their phone.',
                  style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                ),
                const SizedBox(height: ManaSpacing.sm),
                _StepTile(
                  done: c.hasCredential,
                  icon: Icons.lock_outline,
                  title: 'Password / PIN',
                  subtitle: c.hasCredential ? 'Set by the member' : 'Member sets this at First Login',
                  onTap: null,
                ),
                _StepTile(
                  done: c.termsAccepted,
                  icon: Icons.gavel_outlined,
                  title: 'OTP Verification · Terms Acceptance',
                  subtitle: c.termsAccepted ? 'Accepted by the member' : 'Requires the member\'s own verified OTP',
                  onTap: null,
                ),
                const SizedBox(height: ManaSpacing.xl),
                FilledButton(
                  onPressed: _busy || !c.ownerStepsDone ? null : _markComplete,
                  child: const ManaText('mark profile complete'),
                ),
                if (!c.ownerStepsDone) ...[
                  const SizedBox(height: ManaSpacing.sm),
                  const ManaText.raw(
                    'Photo, address and at least one identity document are required first.',
                    style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
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
        subtitle: ManaText.raw(subtitle, style: const TextStyle(fontSize: 13)),
        trailing: done
            ? const Icon(Icons.check_circle, color: ManaColors.statusGood, size: 20)
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

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
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
  String _manualAreaType = 'Village';
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
    setState(() => _savingManual = true);
    try {
      final rows = await Supabase.instance.client.schema('app').rpc('add_location_if_missing', params: {
        'p_pin_code': _pinCode.text.trim(),
        'p_village_town_name': _manualName.text.trim(),
        'p_area_type': _manualAreaType,
        'p_mandal': _manualMandal.text.trim(),
        'p_district': _manualDistrict.text.trim(),
        'p_state': _manualState.text.trim(),
      });
      final result = (rows as List).first as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _selectedVillage = {
          'location_id': result['location_id'],
          'village_town_name': _manualName.text.trim(),
          'mandal': _manualMandal.text.trim(),
          'district': _manualDistrict.text.trim(),
          'state': _manualState.text.trim(),
        };
        _villageSearch.text = _manualName.text.trim();
        _villageResults = [];
        _manualEntry = false;
        _savingManual = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingManual = false);
    }
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
      title: const ManaText('address'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _doorNo,
                decoration: const InputDecoration(labelText: 'Door / House No *', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.sm),
              TextField(
                controller: _pinCode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'PIN Code *',
                  isDense: true,
                  helperText: 'Villages shown are limited to this PIN',
                ),
                onChanged: (_) {
                  setState(() => _selectedVillage = null);
                  _searchVillages(_villageSearch.text);
                },
              ),
              TextField(
                controller: _villageSearch,
                decoration: const InputDecoration(labelText: 'Search Village/Town *', isDense: true),
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
                          style: const TextStyle(fontSize: 13),
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
                  child: Text('"${_villageSearch.text.trim()}" not found — add it'),
                ),
              if (_manualEntry) ...[
                const SizedBox(height: ManaSpacing.xs),
                TextField(
                  controller: _manualName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Village/Town Name *', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.xs),
                DropdownButtonFormField<String>(
                  initialValue: _manualAreaType,
                  decoration: const InputDecoration(labelText: 'Area Type *', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'Village', child: Text('Village')),
                    DropdownMenuItem(value: 'Town', child: Text('Town')),
                  ],
                  onChanged: (v) => setState(() => _manualAreaType = v ?? 'Village'),
                ),
                const SizedBox(height: ManaSpacing.xs),
                TextField(
                  controller: _manualMandal,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Mandal *', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.xs),
                TextField(
                  controller: _manualDistrict,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'District *', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.xs),
                TextField(
                  controller: _manualState,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'State *', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _savingManual ? null : () => setState(() => _manualEntry = false),
                      child: const ManaText('cancel'),
                    ),
                    ElevatedButton(
                      onPressed: _savingManual || !_manualComplete ? null : _saveManualVillage,
                      child: _savingManual
                          ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const ManaText('save & select'),
                    ),
                  ],
                ),
              ],
              if (_selectedVillage != null) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(
                  'Selected: ${_selectedVillage!['village_town_name']} — ${_selectedVillage!['mandal']}, '
                  '${_selectedVillage!['district']}, ${_selectedVillage!['state']}',
                  style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const ManaText('cancel')),
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
          child: const ManaText('save'),
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

class _ContactDialog extends StatefulWidget {
  const _ContactDialog();

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
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
      title: const ManaText('contact & identity'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText.raw(
              'Blank fields are left unchanged.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                isDense: true,
                errorText: mobileValid ? null : 'Must be 10 digits',
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
                labelText: 'Aadhaar Number',
                isDense: true,
                errorText: aadhaarValid ? null : 'Must be 12 digits',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: ManaText.raw(
                    _dob == null
                        ? 'Date of Birth — not set'
                        : 'Date of Birth — ${_dob!.toIso8601String().split('T').first}',
                    style: const TextStyle(fontSize: 13),
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
                    if (picked != null) setState(() => _dob = picked);
                  },
                  child: const ManaText('pick'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const ManaText('cancel')),
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
          child: const ManaText('save'),
        ),
      ],
    );
  }
}
