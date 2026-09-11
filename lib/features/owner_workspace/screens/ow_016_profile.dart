import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/stored_file.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_identity_header.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/live_face_capture_screen.dart';
import '../../../shared/live_photo_upload.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/location_api_service.dart';
import '../../../shared/widgets/village_search_field.dart';

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
      if (!mounted) return;
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
      builder: (_) => _AddressEditDialog(initialPinCode: _address?['pin_code'] as String?),
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
      appBar: ManaAppBar(title: ref.t('my_profile'), homeRoute: '/ow-001'),
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
                      // The column holds an object path now, so the link is
                      // minted here and dies in minutes. Opened once, on
                      // demand, which is exactly the shape a face photo
                      // taken as fraud evidence should have.
                      content: FutureBuilder<String?>(
                        future: ManaStoredFile.signedUrl(
                            bucket: 'live-photos', stored: liveUrl),
                        builder: (_, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const SizedBox(
                              height: 64,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final url = snapshot.data;
                          if (url == null) {
                            return ManaText.raw(ref.t('photo_unavailable'));
                          }
                          return Image.network(
                            url,
                            errorBuilder: (_, __, ___) =>
                                ManaText.raw(ref.t('photo_unavailable')),
                          );
                        },
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

    // The Owner's half of the shared header. onChangePhoto is non-null here,
    // which is the whole role difference: this is the only place a profile
    // photo can be set after registration, and the Agent's screen passes
    // null so no control is drawn at all.
    //
    // The literal "RED"/"GREEN" word pill that used to sit at the end of this
    // row is gone and stays gone: it restated the ring in words, and shouting
    // a raw enum value at the Owner is not a status anybody needs to read.
    return ManaIdentityHeader(
      fullName: person['full_name'] as String? ?? '',
      mlid: person['mlid'] as String? ?? '',
      photoUrl: photoUrl,
      isVerified: (person['verification_ring'] as String?) == 'GREEN',
      photoActionLabel:
          ref.t(photoUrl == null ? 'add_profile_photo' : 'change_profile_photo'),
      savingPhoto: savingPhoto,
      onChangePhoto: () => _photoMenu(context, ref, liveUrl),
      fields: [
        ManaIdentityField(
          label: ref.t('mobile_number'),
          value: person['mobile_number'] as String? ?? '',
        ),
      ],
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
    super.dispose();
  }
  late final _doorNo = TextEditingController();
  ManaVillage? _selectedVillage;
  bool _resolving = false;

  /// A picked reference row has no `location_id` until it is resolved — same
  /// contract [ManaVillagePickerField] documents: it does not write anything,
  /// so a caller that needs the id resolves it. Resolved on pick, not on
  /// confirm, so Save only ever has a real id to send.
  ///
  /// The picked village's own `pinCode` is what gets submitted — there is no
  /// screen-level PIN box any more. ManaVillageSearchField's PIN mode embeds
  /// ManaVillagePickerField, which renders the PIN field; a second, unlinked
  /// box here would just go stale the moment a village is picked.
  Future<void> _onVillagePicked(ManaVillage? v) async {
    if (v == null) {
      setState(() => _selectedVillage = null);
      return;
    }
    if (v.locationId.isNotEmpty) {
      setState(() => _selectedVillage = v);
      return;
    }
    setState(() => _resolving = true);
    final id = await ref.read(locationApiServiceProvider).resolveId(v);
    if (!mounted) return;
    setState(() {
      _resolving = false;
      _selectedVillage = ManaVillage(
        locationId: id,
        name: v.name,
        pinCode: v.pinCode,
        mandal: v.mandal,
        district: v.district,
        state: v.state,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _doorNo.text.trim().isNotEmpty &&
        _selectedVillage != null &&
        !_resolving;
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
              ManaVillageSearchField(
                label: ref.t('search_village_town_field'),
                onPicked: _onVillagePicked,
                initialPin: widget.initialPinCode,
              ),
              if (_selectedVillage != null) ...[
                const SizedBox(height: 6),
                ManaText.raw(
                  ref.t('selected_note').replaceAll(
                      '{value}', '${_selectedVillage!.name} — ${_selectedVillage!.placeLabel}'),
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
                      pinCode: _selectedVillage!.pinCode,
                      villageId: _selectedVillage!.locationId,
                      mandal: _selectedVillage!.mandal,
                      district: _selectedVillage!.district,
                      state: _selectedVillage!.state,
                    ),
                  )
              : null,
          child: ManaText.raw(ref.t('save')),
        ),
      ],
    );
  }
}
