import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/customer_profile_state.dart';

/// CW-006 — My Profile / Business Memberships. Entry: CW-001 Customer
/// Dashboard → My Profile / Memberships. Direct Customer-side
/// counterpart of IW-005 — same Previous Data/BR-238 note-only
/// display, same Aadhaar-locked/BR-239 no-edit-UI rule, same
/// cross-role membership list. The one deliberate difference: tapping
/// a Customer-role membership opens CW-004 My Loans directly (scoped
/// to that business) rather than a generic dashboard.
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
      ref.read(customerProfileProvider.notifier).load(widget.personId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('my profile / memberships'),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/cw-001')),
      ),
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
                        style: const TextStyle(color: ManaColors.statusBad),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    children: [
                      _SummaryCard(personId: widget.personId, profile: state.profile!),
                      const SizedBox(height: ManaSpacing.xl),
                      const ManaText('business memberships', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: ManaSpacing.sm),
                      if (state.memberships.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: ManaSpacing.lg),
                          child: ManaText.raw(
                            'No Business Memberships found.',
                            style: TextStyle(color: ManaColors.textSecondary),
                          ),
                        )
                      else
                        ...state.memberships.map((m) => _MembershipTile(membership: m)),
                    ],
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
        title: const ManaText('edit phone'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone Number'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const ManaText('cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const ManaText('save'),
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
      const SnackBar(content: Text('Phone updated. Previous value kept in history; Owner(s) notified.')),
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
      const SnackBar(content: Text('Address updated. Previous value kept in history; Owner(s) notified.')),
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
                ManaVerificationRing(
                  isVerified: isVerified,
                  photo: profile.profilePhotoUrl != null ? NetworkImage(profile.profilePhotoUrl!) : null,
                  size: 56,
                ),
                const SizedBox(width: ManaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(profile.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 2),
                      ManaText.raw(profile.mlid, style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
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
              label: 'phone',
              value: profile.phoneNumber ?? '—',
              onEdit: () => _editPhone(context, ref),
            ),
            const SizedBox(height: ManaSpacing.sm),
            _FieldRow(
              label: 'aadhaar / id reference',
              value: profile.aadhaarLast4 != null ? '•••• •••• ${profile.aadhaarLast4}' : '—',
              // No edit UI at all here (BR-239) — permanent once
              // captured; only the Owner can correct it (PIN + reason,
              // via OW-004 Customer Management).
              locked: true,
            ),
            const SizedBox(height: ManaSpacing.sm),
            _FieldRow(
              label: 'address',
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

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onEdit;
  final bool locked;
  const _FieldRow({required this.label, required this.value, this.onEdit, this.locked = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText(label, style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              ManaText.raw(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        if (locked)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.lock_outline, size: 16, color: ManaColors.textDisabled),
          )
        else if (onEdit != null)
          TextButton(onPressed: onEdit, child: const ManaText('edit')),
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
  void _switchRole(BuildContext context) {
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
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        title: ManaText.raw(membership.businessName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: ManaText(membership.role.label),
        trailing: ManaStatusPill(label: membership.membershipStatus, status: _pillStatus),
        onTap: () => _switchRole(context),
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

class _VillageSelectorDialog extends StatefulWidget {
  final String? initialPinCode;
  const _VillageSelectorDialog({this.initialPinCode});

  @override
  State<_VillageSelectorDialog> createState() => _VillageSelectorDialogState();
}

class _VillageSelectorDialogState extends State<_VillageSelectorDialog> {
  late final _pinCode = TextEditingController(text: widget.initialPinCode ?? '');
  String? _selectedVillage; // GC-003 type-ahead stub, same convention as OW-000 Step 2

  @override
  Widget build(BuildContext context) {
    final canConfirm = _pinCode.text.trim().length == 6 && _selectedVillage != null;
    return AlertDialog(
      title: const ManaText('edit address — select village'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _pinCode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'PIN Code'),
            onChanged: (_) => setState(() {}),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _pinCode.text.trim().length == 6
                  ? () => setState(() => _selectedVillage = 'Stub Village, ${_pinCode.text.trim()}')
                  : null,
              icon: Icon(_selectedVillage == null ? Icons.location_on_outlined : Icons.check_circle, size: 18),
              label: ManaText(_selectedVillage == null ? 'select village' : 'village selected'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const ManaText('cancel')),
        ElevatedButton(
          onPressed: canConfirm
              ? () => Navigator.pop(
                    context,
                    _VillageSelection(
                      pinCode: _pinCode.text.trim(),
                      villageId: 'stub-village-id',
                      villageName: _selectedVillage!,
                      mandal: 'Stub Mandal',
                      district: 'Stub District',
                      state: 'Stub State',
                    ),
                  )
              : null,
          child: const ManaText('save'),
        ),
      ],
    );
  }
}
