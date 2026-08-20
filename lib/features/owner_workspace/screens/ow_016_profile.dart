import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/live_face_capture_screen.dart';
import '../../../shared/live_photo_upload.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../../shared/mana_time.dart';
import '../../../design/components/mana_info_hint.dart';

/// OW-016 — Owner Profile. NEW screen (extends beyond the original locked
/// 15-screen OW inventory) — the Owner workspace previously had no
/// profile screen at all; the header's "profile" menu item was a no-op
/// placeholder. Mirrors the identity/address display pattern already
/// established in CW-006/IW-005, self-contained (direct queries, no
/// separate state file) matching how several other screens in this
/// codebase are built rather than standing up a full parallel provider
/// layer for a single-screen read.
class OwnerProfileScreen extends ConsumerStatefulWidget {
  const OwnerProfileScreen({super.key});

  @override
  ConsumerState<OwnerProfileScreen> createState() => _OwnerProfileScreenState();
}

class _OwnerProfileScreenState extends ConsumerState<OwnerProfileScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _person;
  Map<String, dynamic>? _address;
  List<Map<String, dynamic>> _businesses = [];

  bool _savingPhoto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Sets (or replaces) the profile photo.
  ///
  /// LR-007 already tells people a failed registration-time upload can be
  /// retried "later via Profile" — but no such path existed on any profile
  /// screen, so anyone whose upload failed (or who registered before that
  /// step) was stuck with the silhouette permanently. That is the actual
  /// reason the welcome header shows no photo: the row's
  /// profile_photo_url is NULL, not a rendering bug.
  ///
  /// A gallery pick is allowed here now, which it deliberately was not
  /// before. The reason that changed: persons.live_photo_url now holds the
  /// registration capture permanently and separately, so identity evidence no
  /// longer depends on this column. profile_photo_url is the picture the
  /// person chooses to show; the live capture stays put and stays viewable.
  ///
  /// Before that column existed, a gallery pick here would have destroyed the
  /// only live photo of the person — which is why the old code forced the
  /// camera.
  Future<void> _changePhoto({required bool fromGallery}) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) return;

    Uint8List? bytes;
    if (fromGallery) {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Downscale at pick time as well as in ProfilePhotoUpload: a modern
        // phone camera roll image is 4-6 MB and decoding it whole on a 2 GB
        // handset is how this OOMs before compression ever runs.
        maxWidth: 1440,
        maxHeight: 1440,
      );
      if (picked == null) return;
      bytes = await picked.readAsBytes();
    } else {
      bytes = await LiveFaceCaptureScreen.capture(context);
    }
    if (bytes == null || !mounted) return;
    // Bound to a final before the closure below: `bytes` is reassigned across
    // the two branches above, so Dart will not promote it to non-null inside
    // a callback.
    final photoBytes = bytes;

    setState(() => _savingPhoto = true);
    // Through NetworkErrorHandler, not a silent try/catch — if this fails
    // the person needs to know it failed, otherwise they are back to
    // wondering why there is still no photo.
    final ok = await NetworkErrorHandler.run(context, () async {
      final db = Supabase.instance.client;
      // Through ProfilePhotoUpload so the photo is compressed on the way out.
      // Same bucket and path shape LR-007 writes, so a retry overwrites the
      // original rather than orphaning it.
      final url = await ProfilePhotoUpload.upload(
        bytes: photoBytes,
        personId: personId,
      );
      // profile_photo_url only. live_photo_url is written once at first login
      // and is deliberately not touched here — that is the whole point of the
      // split, and it is what keeps "View Live Photo" meaningful.
      await db.from('persons').update({'profile_photo_url': url}).eq('person_id', personId);
      return true;
    });
    if (!mounted) return;
    setState(() => _savingPhoto = false);
    if (ok == true) await _load();
  }

  Future<void> _load() async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      setState(() {
        _loading = false;
        _error = 'No logged-in identity found.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final person = await Supabase.instance.client
          .from('persons')
          .select(
              'full_name, mlid, mobile_number, verification_ring, father_husband_name, '
              'profile_photo_url, live_photo_url')
          .eq('person_id', personId)
          .single();

      final addressRows = await Supabase.instance.client
          .from('person_addresses')
          .select(
              'door_no, pin_code, mandal, district, state, locations(village_town_name)')
          .eq('person_id', personId)
          .eq('is_current', true)
          .limit(1);

      final businessRows = await Supabase.instance.client
          .from('businesses')
          .select('business_id, business_name, mlbi, business_status')
          .eq('owner_person_id', personId);

      if (!mounted) return;
      setState(() {
        _person = person;
        _address = (addressRows as List).isNotEmpty ? addressRows.first : null;
        _businesses = (businessRows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load profile.';
      });
    }
  }

  Future<void> _editAddress() async {
    final result = await showDialog<_AddressEditResult>(
      context: context,
      builder: (_) =>
          _AddressEditDialog(initialPinCode: _address?['pin_code'] as String?),
    );
    if (result == null) return;

    final personId = ref.read(authFlowProvider).personId;
    if (personId == null || !mounted) return;

    final ok = await NetworkErrorHandler.run(context, () async {
      // Prior current address, if any, is superseded — not deleted
      // (BR-127 pattern: history preserved, never hard-deleted).
      await Supabase.instance.client
          .from('person_addresses')
          .update({'is_current': false})
          .eq('person_id', personId)
          .eq('is_current', true);
      await Supabase.instance.client.from('person_addresses').insert({
        'person_id': personId,
        'door_no': result.doorNo,
        'pin_code': result.pinCode,
        'village_id': result.villageId,
        'mandal': result.mandal,
        'district': result.district,
        'state': result.state,
        'is_current': true,
        'from_date': manaBusinessDate(),
      });
      return true;
    });
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('my_profile')),
        leading: BackButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/ow-001')),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _person == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      child: ManaText.raw(_error ?? ref.t('could_not_load_profile_plain'),
                          textAlign: TextAlign.center,
                          style: ManaType.bad),
                    ),
                  )
                : RefreshIndicator(
                    // Verification ring, address and the business list all
                    // change from outside this screen, so it needs a way to
                    // ask again without being closed and reopened.
                    onRefresh: _load,
                    child: ListView(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    children: [
                      _IdentityCard(
                        person: _person!,
                        onChangePhoto: _changePhoto,
                        savingPhoto: _savingPhoto,
                      ),
                      const SizedBox(height: ManaSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: ManaText.raw(ref.t('address'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          const SizedBox(width: ManaSpacing.xs),
                          Flexible(
                            child: TextButton.icon(
                              onPressed: _editAddress,
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: ManaText.raw(ref.t('edit')),
                            ),
                          ),
                        ],
                      ),
                      _AddressCard(address: _address),
                      const SizedBox(height: ManaSpacing.xl),
                      ManaText.raw(ref.t('businesses_owned'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: ManaSpacing.sm),
                      if (_businesses.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: ManaSpacing.lg),
                          child: ManaText.raw(ref.t('no_businesses_found'),
                              style:
                                  ManaType.secondary),
                        )
                      else
                        ..._businesses.map((b) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.storefront_outlined),
                                title: ManaText.raw(
                                    b['business_name'] as String? ?? ''),
                                subtitle:
                                    ManaText.raw(b['mlbi'] as String? ?? ''),
                                trailing: ManaText.raw(
                                    b['business_status'] as String? ?? ''),
                                onTap: () => context.push('/ow-001',
                                    extra: b['business_id']),
                              ),
                            )),
                      const SizedBox(height: ManaSpacing.xl),
                      OutlinedButton.icon(
                        onPressed: () {
                          ref.read(authFlowProvider.notifier).reset();
                          context.go('/lr-009');
                        },
                        icon: Icon(Icons.logout,
                            color: ManaColors.statusBad),
                        label: ManaText.raw('logout',
                            style: ManaType.bad),
                      ),
                    ],
                  ),
                  ),
      ),
    );
  }
}

class _IdentityCard extends ConsumerWidget {
  final Map<String, dynamic> person;
  final void Function({required bool fromGallery}) onChangePhoto;
  final bool savingPhoto;
  const _IdentityCard({
    required this.person,
    required this.onChangePhoto,
    required this.savingPhoto,
  });

  /// Offers the two sources, and the live photo when there is one to see.
  ///
  /// A sheet rather than going straight to the camera: uploading your own
  /// picture and re-taking the verification photo are different intentions,
  /// and the old tap silently assumed the second.
  Future<void> _photoMenu(BuildContext context, WidgetRef ref, String? liveUrl) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: ManaText.raw(ref.t('upload_photo')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onChangePhoto(fromGallery: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: ManaText.raw(ref.t('take_photo')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onChangePhoto(fromGallery: false);
              },
            ),
            // Only when a live capture exists. It is never overwritten by an
            // upload — see persons.live_photo_url — so this stays available
            // however many times the profile picture changes.
            if (liveUrl != null && liveUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: ManaText.raw(ref.t('view_live_photo')),
                subtitle: ManaText.raw(
                  ref.t('live_photo_from_registration_note'),
                  style: ManaType.fine,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showDialog<void>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: ManaText.raw(ref.t('view_live_photo')),
                      content: Image.network(
                        liveUrl,
                        errorBuilder: (_, __, ___) =>
                            ManaText.raw(ref.t('photo_unavailable')),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(d).pop(),
                          child: ManaText.raw(ref.t('close')),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrl = (person['profile_photo_url'] as String?)?.trim();
    final liveUrl = (person['live_photo_url'] as String?)?.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Row(
          children: [
            // The ring IS the verification signal (BR-191/GC-002) — green or
            // red edge around the photo. The literal "RED"/"GREEN" word pill
            // that used to sit at the end of this row is gone: it restated the
            // ring in words, and shouting a raw enum value at the Owner is not
            // a status anyone needs to read.
            //
            // The photo was never rendered at all because profile_photo_url
            // was not in the persons select above — hence the generic
            // silhouette. Falls back to that silhouette when the person has no
            // photo, or when the signed URL has expired (these are private-
            // bucket signed URLs with a 1-year expiry; see LivePhotoUpload).
            // Tappable: this is the only place a profile photo can be set
            // after registration. Labelled for a screen reader by the
            // ACTION, and sized past the 48dp floor by the badge below.
            Semantics(
              button: true,
              label: ref.t(photoUrl == null ? 'add_profile_photo' : 'change_profile_photo'),
              excludeSemantics: true,
              child: InkWell(
                onTap: savingPhoto ? null : () => _photoMenu(context, ref, liveUrl),
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    ManaVerificationRing(
                      isVerified: (person['verification_ring'] as String?) == 'GREEN',
                      size: 56,
                      photo: photoUrl == null ? null : NetworkImage(photoUrl),
                    ),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: ManaColors.brandDeep,
                        shape: BoxShape.circle,
                      ),
                      child: savingPhoto
                          ? SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: ManaColors.textOnDark),
                            )
                          : Icon(Icons.photo_camera,
                              size: 12, color: ManaColors.textOnDark),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText.raw(person['full_name'] as String? ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  ManaText.raw(person['mlid'] as String? ?? '',
                      style: TextStyle(
                          color: ManaColors.textSecondary, fontSize: 13)),
                  ManaText.raw(person['mobile_number'] as String? ?? '',
                      style: TextStyle(
                          color: ManaColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends ConsumerWidget {
  final Map<String, dynamic>? address;
  const _AddressCard({required this.address});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (address == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.md),
        child: ManaText.raw(ref.t('no_address_on_file'),
            style: ManaType.secondary),
      );
    }
    final village = (address!['locations']
        as Map<String, dynamic>?)?['village_town_name'] as String?;
    final line = [
      address!['door_no'],
      village,
      address!['mandal'],
      address!['district'],
      address!['state'],
      address!['pin_code'],
    ].where((v) => v != null && (v as String).isNotEmpty).join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: ManaText.raw(line),
      ),
    );
  }
}

class _AddressEditResult {
  final String doorNo;
  final String pinCode;
  final String villageId;
  final String mandal;
  final String district;
  final String state;
  _AddressEditResult({
    required this.doorNo,
    required this.pinCode,
    required this.villageId,
    required this.mandal,
    required this.district,
    required this.state,
  });
}

/// Address edit dialog — same real search + "add if not found" pattern
/// already established across LR-004/OW-000/OW-004/CW-006/IW-005.
class _AddressEditDialog extends ConsumerStatefulWidget {
  final String? initialPinCode;
  const _AddressEditDialog({this.initialPinCode});
  @override
  ConsumerState<_AddressEditDialog> createState() => _AddressEditDialogState();
}

class _AddressEditDialogState extends ConsumerState<_AddressEditDialog> {
  late final _doorNo = TextEditingController();
  late final _pinCode =
      TextEditingController(text: widget.initialPinCode ?? '');
  final _villageSearch = TextEditingController();
  Map<String, dynamic>? _selectedVillage;
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
    try {
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
      final result = (rows as List).first as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _selectedVillage = {
          'location_id': result['location_id'],
          'village_town_name': _manualVillageName.text.trim(),
          'mandal': _manualMandal.text.trim(),
          'district': _manualDistrict.text.trim(),
          'state': _manualState.text.trim(),
        };
        _villageSearch.text = _manualVillageName.text.trim();
        _villageResults = [];
        _manualVillageEntry = false;
        _savingManualVillage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingManualVillage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _doorNo.text.trim().isNotEmpty &&
        _pinCode.text.trim().length == 6 &&
        _selectedVillage != null;
    return AlertDialog(
      title: ManaText.raw(ref.t('edit_address')),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _doorNo,
                decoration: InputDecoration(
                    labelText: ref.t('door_house_no_field'), isDense: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pinCode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                    labelText: ref.t('pin_code_required_field'),
                    isDense: true,
                    suffixIcon: ManaInfoHint(ref.t('villages_limited_to_pin_helper')),),
                onChanged: (_) {
                  setState(() {
                    _selectedVillage = null;
                  });
                  _searchVillages(_villageSearch.text);
                },
              ),
              TextField(
                controller: _villageSearch,
                decoration: InputDecoration(
                    labelText: ref.t('search_village_town_field'), isDense: true),
                onChanged: (v) {
                  setState(() {
                    _selectedVillage = null;
                    _manualVillageEntry = false;
                  });
                  _searchVillages(v);
                },
              ),
              if (_villageResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  margin: const EdgeInsets.only(top: 4),
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
                            style: ManaType.small),
                        onTap: () => setState(() {
                          _selectedVillage = v;
                          _villageSearch.text =
                              v['village_town_name'] as String;
                          _villageResults = [];
                        }),
                      );
                    },
                  ),
                ),
              if (_villageSearchAttempted &&
                  _villageResults.isEmpty &&
                  _selectedVillage == null &&
                  !_manualVillageEntry)
                TextButton(
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft),
                  onPressed: () => setState(() {
                    _manualVillageEntry = true;
                    _manualVillageName.text = _villageSearch.text.trim();
                  }),
                  child: ManaText.raw(ref
                      .t('village_not_found_add_it')
                      .replaceAll('{query}', _villageSearch.text.trim())),
                ),
              if (_manualVillageEntry) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _manualVillageName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                      labelText: ref.t('village_town_name_field'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _manualAreaType,
                  decoration: InputDecoration(
                      labelText: ref.t('area_type_field'), isDense: true),
                  items: [
                    DropdownMenuItem(value: 'Village', child: ManaText.raw(ref.t('village'))),
                    DropdownMenuItem(value: 'Town', child: ManaText.raw(ref.t('town'))),
                  ],
                  onChanged: (v) =>
                      setState(() => _manualAreaType = v ?? 'Village'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _manualMandal,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                      labelText: ref.t('mandal_field'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _manualDistrict,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                      labelText: ref.t('district_field'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _manualState,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                      labelText: ref.t('state_field'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _savingManualVillage
                          ? null
                          : () => setState(() => _manualVillageEntry = false),
                      child: ManaText.raw(ref.t('cancel')),
                    ),
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
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : ManaText.raw(ref.t('save_and_select')),
                    ),
                  ],
                ),
              ],
              if (_selectedVillage != null) ...[
                const SizedBox(height: 6),
                ManaText.raw(
                  ref.t('selected_note').replaceAll('{value}',
                      '${_selectedVillage!['village_town_name']} — ${_selectedVillage!['mandal']}, ${_selectedVillage!['district']}, ${_selectedVillage!['state']}'),
                  style: TextStyle(
                      fontSize: 13, color: ManaColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: ManaText.raw(ref.t('cancel'))),
        ElevatedButton(
          onPressed: canSave
              ? () => Navigator.pop(
                    context,
                    _AddressEditResult(
                      doorNo: _doorNo.text.trim(),
                      pinCode: _pinCode.text.trim(),
                      villageId: _selectedVillage!['location_id'] as String,
                      mandal: _selectedVillage!['mandal'] as String,
                      district: _selectedVillage!['district'] as String,
                      state: _selectedVillage!['state'] as String,
                    ),
                  )
              : null,
          child: ManaText.raw(ref.t('save')),
        ),
      ],
    );
  }
}
