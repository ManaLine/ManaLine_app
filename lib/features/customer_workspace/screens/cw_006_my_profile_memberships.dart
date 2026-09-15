import 'package:flutter/material.dart';
import '../../../design/components/mana_stored_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/business_suspension_gate.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_card.dart';
import '../../../shared/network_error_handler.dart';
import '../state/customer_profile_state.dart';
import '../../../shared/location_api_service.dart';
import '../../../shared/widgets/village_search_field.dart';

/// CW-006 — My Profile / Business Memberships. Entry: CW-001 Customer
/// Dashboard → My Profile / Memberships. Direct Customer-side
/// counterpart of IW-005 — same Previous Data/BR-238 note-only
/// display, same Aadhaar-locked/BR-239 no-edit-UI rule, same
/// cross-role membership list. The one deliberate difference: tapping
/// a Customer-role membership opens CW-004 My Loans directly (scoped
/// to that business) rather than a generic dashboard.
class MyProfileMembershipsScreen extends ConsumerStatefulWidget {
  final String personId;

  /// Where back goes when there is nothing to pop.
  ///
  /// Defaults to the Customer dashboard, which is right when this is reached
  /// from CW-001. It is a parameter because the screen is NOT actually
  /// customer-scoped despite its ID: it takes a personId and reads `persons`,
  /// `person_addresses` and `locations` — no `customers` row anywhere. That is
  /// what lets `/profile` reuse it for somebody who belongs to no business
  /// yet, where sending them "home" to a Customer dashboard they have no
  /// membership for would be wrong.
  final String homeRoute;

  const MyProfileMembershipsScreen({
    super.key,
    required this.personId,
    this.homeRoute = '/cw-001',
  });

  @override
  ConsumerState<MyProfileMembershipsScreen> createState() => _MyProfileMembershipsScreenState();
}

class _MyProfileMembershipsScreenState extends ConsumerState<MyProfileMembershipsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerProfileProvider.notifier).load(widget.personId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerProfileProvider);

    return Scaffold(
      appBar: ManaAppBar(
          title: ref.t('my_profile_memberships_title'),
          homeRoute: widget.homeRoute),
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
                    // Memberships change from the Owner's side — an approval
                    // or a removal happens elsewhere and this screen would
                    // otherwise show yesterday's answer until it is left and
                    // reopened.
                    onRefresh: () =>
                        ref.read(customerProfileProvider.notifier).load(widget.personId),
                    child: ListView(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    children: [
                      _SummaryCard(personId: widget.personId, profile: state.profile!),
                      const SizedBox(height: ManaSpacing.xl),
                      ManaText.raw(ref.t('business_memberships'), style: ManaType.cardTitle),
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
                        ...manaGroupMemberships(state.memberships)
                            .map((b) => _BusinessMembershipCard(business: b)),
                    ],
                  ),
                  ),
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  final String personId;
  final CustomerProfileSummary profile;
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
          .read(customerProfileProvider.notifier)
          .updatePhone(personId: personId, phoneNumber: newPhone);
      if (!ok) throw Exception('Could not update phone');
      return ok;
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(ref.t('phone_updated_note'))),
    );
  }

  // S2 — Editing Address. Village-only selector, from master
  // `locations` data (BR-130) — rebuilt locally here per this chat's
  // file-ownership boundary, matching OW-000/OW-012/IW-005's
  // PIN→Village interaction pattern (PIN entry, then a "select
  // village" action) without importing another workspace's version.
  Future<void> _editAddress(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_VillageSelection>(
      context: context,
      builder: (_) => _VillageSelectorDialog(initialPinCode: profile.currentAddress?.pinCode),
    );
    if (result == null) return;
    if (!context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      final ok = await ref.read(customerProfileProvider.notifier).updateAddress(
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
                      ManaText.raw(profile.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 2),
                      ManaText.raw(profile.mlid, style: ManaType.note),
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
              // via OW-004 Customer Management).
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
              ManaText(label, style: TextStyle(fontSize: 13, color: ManaColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              ManaText.raw(value, style: const TextStyle(fontSize: 14)),
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
  final CustomerBusinessMembership membership;
  const _MembershipTile({required this.membership});

  ManaStatus get _pillStatus => switch (membership.membershipStatus) {
        'Active' => ManaStatus.good,
        'Suspended' || 'Removed' => ManaStatus.bad,
        _ => ManaStatus.warn,
      };

  // S3 — Switching Role. Per CW-006.md NAVIGATION: Owner → OW-001,
  // Agent → AG-001, Investor → IW-001, Customer → CW-001 for a
  // different Business — EXCEPT a Customer-role membership
  // specifically, where tapping opens CW-004 My Loans directly
  // (scoped to that business) rather than the generic CW-001
  // dashboard, per the locked distinction in CW-006's own BUSINESS
  // MEMBERSHIPS section. This is the one deliberate deviation from
  // IW-005's otherwise-identical pattern (there, Investor-role tap
  // goes to IW-003; here, Customer-role tap goes to CW-004).
  /// SP-001. These cards switch into a DIFFERENT business than the one the
  /// session is in, so they bypass LR-012 and LR-013 and their gates entirely.
  ///
  /// This one takes a round trip, unlike the entry-path gates: the membership
  /// model behind this screen does not carry `business_status`, only
  /// `membership_status`. That is acceptable here and would not be on the
  /// collection path -- switching workspaces is a rare, deliberate tap, not
  /// something an agent does between two doors. Fail-closed on error, per the
  /// standing decision.
  Future<void> _switchRole(BuildContext context) async {
    if (await BusinessSuspensionGate.checkAndRedirect(
        context, membership.businessId)) {
      return;
    }
    if (!context.mounted) return;
    switch (membership.role) {
      case MembershipRole.owner:
        context.go('/ow-001', extra: membership.businessId);
        break;
      case MembershipRole.agent:
        context.go('/ag-001', extra: membership.businessId);
        break;
      case MembershipRole.investor:
        context.go('/iw-001', extra: membership.businessId);
        break;
      case MembershipRole.customer:
        // Straight to CW-004 My Loans, scoped to this business — not
        // the generic CW-001 dashboard (CW-006.md BUSINESS
        // MEMBERSHIPS section, locked this session). SPEC GAP: CW-004
        // requires customerId as well as businessId (per that chat's
        // own constructor) — this membership row only carries
        // businessId per CW-006's own DATA MODEL TOUCHED
        // (business_members has no separate customerId surfaced to
        // this screen). Passing personId-as-customerId here assumes a
        // 1:1 person↔customer_id mapping within a given business;
        // flagged for master chat to confirm/remap at the route
        // builder if customer_id is actually distinct.
        context.go('/cw-004', extra: membership.businessId);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // One role inside a business card. Tapping it switches to that workspace.
    return InkWell(
      onTap: () => _switchRole(context),
      borderRadius: BorderRadius.circular(ManaRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xs),
        child: Row(
          children: [
            Expanded(child: ManaText(membership.role.label)),
            ManaTrailingStatus(
                label: membership.membershipStatus, status: _pillStatus),
          ],
        ),
      ),
    );
  }
}

/// One business, with every role the person holds in it.
///
/// Was one card per membership row, so a person who is Owner, Agent and
/// Customer of the same shop saw that shop three times and had to read the
/// heading each time to tell the cards apart. The business is the thing being
/// listed; the roles are what you hold in it.
class _BusinessMembershipCard extends StatelessWidget {
  final ManaBusinessMemberships business;
  const _BusinessMembershipCard({required this.business});

  @override
  Widget build(BuildContext context) {
    return ManaCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(business.businessName,
                style: ManaType.emphasis),
            const SizedBox(height: ManaSpacing.xs),
            for (final m in business.roles) _MembershipTile(membership: m),
          ],
        ),

    );
  }
}

// --- Village selector (S2) — local rebuild of the OW-000/OW-012/IW-005
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
    final canConfirm = _selectedVillage != null && !_resolving;
    return AlertDialog(
      // Scrolls if it does not fit -- see ow_011_day_closure.dart.
      scrollable: true,
      title: ManaText.raw(ref.t('edit_address_select_village')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaVillageSearchField(
            label: ref.t('search_village_town_plain_field'),
            onPicked: _onVillagePicked,
            initialPin: widget.initialPinCode,
          ),
          if (_selectedVillage != null) ...[
            const SizedBox(height: 4),
            ManaText.raw(
              'Selected: ${_selectedVillage!.name} — ${_selectedVillage!.placeLabel}',
              style: ManaType.note,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: ManaText.raw(ref.t('cancel'))),
        ElevatedButton(
          onPressed: canConfirm
              ? () => Navigator.pop(
                    context,
                    _VillageSelection(
                      pinCode: _selectedVillage!.pinCode,
                      villageId: _selectedVillage!.locationId,
                      villageName: _selectedVillage!.name,
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
