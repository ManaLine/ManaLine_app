import 'package:flutter/material.dart';
import '../../../design/components/mana_stored_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/add_village_if_missing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/investor_profile_state.dart';
import '../../../design/components/mana_info_hint.dart';
import '../../../shared/location_api_service.dart';
import '../../../shared/widgets/add_village_sheet.dart';

/// IW-005 — My Profile / Business Memberships. Entry: IW-001 Investor
/// Dashboard → My Profile / Memberships.
class MyProfileMembershipsScreen extends ConsumerStatefulWidget {
  final String personId;
  const MyProfileMembershipsScreen({super.key, required this.personId});

  @override
  ConsumerState<MyProfileMembershipsScreen> createState() => _MyProfileMembershipsScreenState();
}

class _MyProfileMembershipsScreenState extends ConsumerState<MyProfileMembershipsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(investorProfileProviderIW005.notifier).load(widget.personId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(investorProfileProviderIW005);

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('my_profile_memberships_title'), homeRoute: '/iw-001'),
      body: SafeArea(
        child: state.loading && state.profile == null
            ? const Center(child: CircularProgressIndicator())
            : state.profile == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      child: ManaText.raw(
                        state.error ?? 'Could not load profile.',
                        textAlign: TextAlign.center,
                        style: ManaType.bad,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    // An Owner approving or removing this membership happens
                    // elsewhere; without a pull the screen shows yesterday's
                    // answer until it is closed and reopened.
                    onRefresh: () => ref
                        .read(investorProfileProviderIW005.notifier)
                        .load(widget.personId),
                    child: ListView(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      children: [
                        _SummaryCard(personId: widget.personId, profile: state.profile!),
                        const SizedBox(height: ManaSpacing.xl),
                        ManaText.raw(ref.t('business_memberships'), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: ManaSpacing.sm),
                        if (state.memberships.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.lg),
                            child: ManaText.raw(
                              'No Business Memberships found.',
                              style: ManaType.secondary,
                            ),
                          )
                        else
                          ...state.memberships.map((m) => _MembershipTile(membership: m)),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  final String personId;
  final InvestorProfileSummary profile;
  const _SummaryCard({required this.personId, required this.profile});

  Future<void> _editPhone(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: profile.phoneNumber ?? '');
    final newPhone = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('edit_phone')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: ref.t('phone_number_plain_field')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: ManaText.raw(ref.t('save')),
          ),
        ],
      ),
    );
    if (newPhone == null || newPhone.isEmpty || newPhone == profile.phoneNumber) return;
    if (!context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      final ok = await ref
          .read(investorProfileProviderIW005.notifier)
          .updatePhone(personId: personId, phoneNumber: newPhone);
      if (!ok) throw Exception('Could not update phone');
      return ok;
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(ref.t('phone_updated_note'))),
    );
  }

  // S2 — Editing Address. Village-only selector, from master `locations`
  // data (BR-130) — rebuilt locally here per this chat's file-ownership
  // boundary, matching OW-000/OW-012's PIN→Village interaction pattern
  // (PIN entry, then a "select village" action) without importing the
  // Owner Workspace's implementation.
  Future<void> _editAddress(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_VillageSelection>(
      context: context,
      builder: (_) => _VillageSelectorDialog(initialPinCode: profile.currentAddress?.pinCode),
    );
    if (result == null) return;
    if (!context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      final ok = await ref.read(investorProfileProviderIW005.notifier).updateAddress(
            personId: personId,
            addressId: profile.currentAddress?.addressId ?? 'new',
            villageId: result.villageId,
            villageName: result.villageName,
            doorNo: profile.currentAddress?.doorNo,
            areaLocality: profile.currentAddress?.areaLocality,
            pinCode: result.pinCode,
          );
      if (!ok) throw Exception('Could not update address');
      return ok;
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(ref.t('address_updated_note'))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVerified = profile.verificationRing == VerificationRing.green;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ManaStoredImage(
                  bucket: 'profile-photos',
                  stored: profile.profilePhotoUrl,
                  builder: (context, image) => ManaVerificationRing(
                    isVerified: isVerified,
                    photo: image,
                    size: 56,
                  ),
                ),
                const SizedBox(width: ManaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(profile.fullName, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 2),
                      ManaText.raw(profile.mlid,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                ManaStatusPill(
                  label: isVerified ? 'Verified' : 'Not Verified',
                  status: isVerified ? ManaStatus.good : ManaStatus.bad,
                ),
              ],
            ),
            const Divider(height: ManaSpacing.xl),
            _FieldRow(
              label: ref.t('phone'),
              value: profile.phoneNumber ?? '—',
              onEdit: () => _editPhone(context, ref),
            ),
            const SizedBox(height: ManaSpacing.sm),
            _FieldRow(
              label: ref.t('aadhaar_id_reference'),
              value: profile.aadhaarLast4 != null ? '•••• •••• ${profile.aadhaarLast4}' : '—',
              // No edit UI at all here (BR-239) — permanent once
              // captured; only the Owner can correct it (PIN + reason,
              // via OW-003 Investor Management).
              locked: true,
            ),
            const SizedBox(height: ManaSpacing.sm),
            _FieldRow(
              label: ref.t('address'),
              value: profile.currentAddress != null
                  ? '${profile.currentAddress!.villageName}, ${profile.currentAddress!.mandal}, ${profile.currentAddress!.district}'
                  : 'Not set',
              onEdit: () => _editAddress(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends ConsumerWidget {
  final String label;
  final String value;
  final VoidCallback? onEdit;
  final bool locked;
  const _FieldRow({required this.label, required this.value, this.onEdit, this.locked = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              ManaText.raw(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        if (locked)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.lock_outline, size: 16, color: ManaColors.textDisabled),
          )
        else if (onEdit != null)
          TextButton(onPressed: onEdit, child: ManaText.raw(ref.t('edit'))),
      ],
    );
  }
}

class _MembershipTile extends StatelessWidget {
  final BusinessMembership membership;
  const _MembershipTile({required this.membership});

  ManaStatus get _pillStatus => switch (membership.membershipStatus) {
        'Active' => ManaStatus.good,
        'Suspended' || 'Removed' => ManaStatus.bad,
        _ => ManaStatus.warn,
      };

  // S3 — Switching Role. Per IW-005.md NAVIGATION: Owner → OW-001,
  // Agent → AG-001, Investor → IW-001 for a different Business,
  // Customer → CW-001 — EXCEPT an Investor-role membership specifically,
  // where tapping goes straight to IW-003 (scoped to that business)
  // rather than IW-001, per the locked distinction in the spec.
  void _switchRole(BuildContext context) {
    switch (membership.role) {
      case MembershipRole.owner:
        context.go('/ow-001', extra: membership.businessId.toString());
        break;
      case MembershipRole.agent:
        context.go('/ag-001', extra: membership.businessId.toString());
        break;
      case MembershipRole.investor:
        // Straight to IW-003 My Investments, scoped to this business —
        // not the generic IW-001 dashboard (IW-005.md BUSINESS
        // MEMBERSHIPS section, locked this session).
        context.go('/iw-003', extra: membership.businessId.toString());
        break;
      case MembershipRole.customer:
        context.go('/cw-001', extra: membership.businessId.toString());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        title: ManaText.raw(membership.businessName),
        subtitle: ManaText(membership.role.label),
        trailing: ManaTrailingStatus(
            label: membership.membershipStatus, status: _pillStatus),
        onTap: () => _switchRole(context),
      ),
    );
  }
}

// --- Village selector (S2) — local rebuild of the OW-000/OW-012
// PIN→Village pattern, per this chat's file-ownership boundary. -------------

class _VillageSelection {
  final String pinCode;
  final String villageId;
  final String villageName;
  final String mandal;
  final String district;
  final String state;
  const _VillageSelection({
    required this.pinCode,
    required this.villageId,
    required this.villageName,
    required this.mandal,
    required this.district,
    required this.state,
  });
}

class _VillageSelectorDialog extends ConsumerStatefulWidget {
  final String? initialPinCode;
  const _VillageSelectorDialog({this.initialPinCode});

  @override
  ConsumerState<_VillageSelectorDialog> createState() => _VillageSelectorDialogState();
}

class _VillageSelectorDialogState extends ConsumerState<_VillageSelectorDialog> {

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _villageSearch.dispose();
    _pinCode.dispose();
    super.dispose();
  }
  late final _pinCode = TextEditingController(text: widget.initialPinCode ?? '');
  final _villageSearch = TextEditingController();
  Map<String, dynamic>? _selectedVillage; // real row: location_id, village_town_name, mandal, district, state
  List<Map<String, dynamic>> _villageResults = [];
  bool _villageSearchAttempted = false;

  Future<void> _searchVillages(String query) async {
    // Three letters and a full PIN, the same rule every other village picker
    // uses. LocationApiService enforces it too; this is the early return that
    // keeps the "searched yet?" flag honest.
    if (query.trim().length < 3) {
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
      // Through LocationApiService, which merges the villages already in use
      // with the LGD reference. This searched `locations` ALONE, and that table
      // holds only villages some business already operates in — so a person
      // editing their own address could never reach a village nobody had used
      // yet, and fell through to typing mandal, district and state by hand.
      // A reference row carries an empty id; manaResolvePickedVillage writes
      // the real one when they confirm.
      final villages = await ref
          .read(locationApiServiceProvider)
          .searchByPin(pinCode: pin, query: query.trim(), limit: 15);
      if (!mounted) return;
      setState(() {
        _villageResults = [
          for (final v in villages)
            {
              'location_id': v.locationId.isEmpty ? null : v.locationId,
              'village_town_name': v.name,
              'mandal': v.mandal,
              'district': v.district,
              'state': v.state,
            },
        ];
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

  /// Opens the shared Add New Village sheet.
  ///
  /// Was ~60 lines of inline form here asking for village, mandal, district and
  /// state as free text — one of SEVEN copies of the same four boxes, and the
  /// reason a village once recorded its state as "Andhrapradesh" and then
  /// narrowed every picker to nothing.
  ///
  /// The sheet derives mandal and district from the PIN (99.8% of pincodes mean
  /// one state) and asks whether a near-matching village was meant before
  /// creating a second row for one place.
  Future<void> _openAddVillage() async {
    final picked = await manaShowAddVillageSheet(
      context,
      ref,
      pinCode: _pinCode.text.trim(),
      initialName: _villageSearch.text.trim(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedVillage = {
        'location_id': picked.locationId,
        'village_town_name': picked.name,
        'mandal': picked.mandal,
        'district': picked.district,
        'state': picked.state,
      };
      _villageSearch.text = picked.name;
      _villageResults = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _pinCode.text.trim().length == 6 && _selectedVillage != null;
    return AlertDialog(
      // Scrolls if it does not fit -- see ow_011_day_closure.dart.
      scrollable: true,
      title: ManaText.raw(ref.t('edit_address_select_village')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _pinCode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(labelText: ref.t('pin_code_plain_field'), suffixIcon: ManaInfoHint(ref.t('pin_code_first_helper')),),
            onChanged: (_) {
              setState(() {
                _selectedVillage = null;
              });
              _searchVillages(_villageSearch.text);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _villageSearch,
            decoration: InputDecoration(labelText: ref.t('search_village_town_plain_field')),
            onChanged: (v) {
              setState(() => _selectedVillage = null);
              _searchVillages(v);
            },
          ),
          if (_villageSearchAttempted && _villageResults.isEmpty && _selectedVillage == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                onPressed: _openAddVillage,
                child: Text('"${_villageSearch.text.trim()}" not found — add it'),
              ),
            ),
          if (_villageResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.only(top: 4),
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
                    onTap: () => setState(() {
                      _selectedVillage = v;
                      _villageSearch.text = v['village_town_name'] as String;
                      _villageResults = [];
                    }),
                  );
                },
              ),
            ),
          if (_selectedVillage != null) ...[
            const SizedBox(height: 4),
            ManaText.raw(
              'Selected: ${_selectedVillage!['village_town_name']} — ${_selectedVillage!['mandal']}, ${_selectedVillage!['district']}, ${_selectedVillage!['state']}',
              style: ManaType.note,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: ManaText.raw(ref.t('cancel'))),
        ElevatedButton(
          onPressed: canConfirm
              ? () async {
                  // A reference pick has no id until now.
                  final id = await manaResolvePickedVillage(context, ref,
                      row: _selectedVillage!, pinCode: _pinCode.text.trim());
                  if (id == null || !context.mounted) return;
                  Navigator.pop(
                    context,
                    _VillageSelection(
                      pinCode: _pinCode.text.trim(),
                      villageId: id,
                      villageName: _selectedVillage!['village_town_name'] as String,
                      mandal: _selectedVillage!['mandal'] as String,
                      district: _selectedVillage!['district'] as String,
                      state: _selectedVillage!['state'] as String,
                    ),
                  );
                }
              : null,
          child: ManaText.raw(ref.t('save')),
        ),
      ],
    );
  }
}
