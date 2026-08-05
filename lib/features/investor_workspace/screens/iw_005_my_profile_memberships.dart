import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/investor_profile_state.dart';

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
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/iw-001')),
        title: const ManaText('my profile / memberships'),
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
                        ManaText('business memberships', style: Theme.of(context).textTheme.titleMedium),
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
          .read(investorProfileProviderIW005.notifier)
          .updatePhone(personId: personId, phoneNumber: newPhone);
      if (!ok) throw Exception('Could not update phone');
      return ok;
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phone updated. Previous value kept in history; Owner(s) notified.')),
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
              // via OW-003 Investor Management).
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
              ManaText(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              ManaText.raw(value, style: Theme.of(context).textTheme.bodyMedium),
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
        trailing: ManaStatusPill(label: membership.membershipStatus, status: _pillStatus),
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

class _VillageSelectorDialog extends StatefulWidget {
  final String? initialPinCode;
  const _VillageSelectorDialog({this.initialPinCode});

  @override
  State<_VillageSelectorDialog> createState() => _VillageSelectorDialogState();
}

class _VillageSelectorDialogState extends State<_VillageSelectorDialog> {
  late final _pinCode = TextEditingController(text: widget.initialPinCode ?? '');
  final _villageSearch = TextEditingController();
  Map<String, dynamic>? _selectedVillage; // real row: location_id, village_town_name, mandal, district, state
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
    Map<String, dynamic>? result;
    try {
      final rows = await Supabase.instance.client.schema('app').rpc('add_location_if_missing', params: {
        'p_pin_code': _pinCode.text.trim(),
        'p_village_town_name': _manualVillageName.text.trim(),
        'p_area_type': _manualAreaType,
        'p_mandal': _manualMandal.text.trim(),
        'p_district': _manualDistrict.text.trim(),
        'p_state': _manualState.text.trim(),
      });
      result = (rows as List).first as Map<String, dynamic>;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add village: $e')),
        );
      }
    }
    if (!mounted) return;
    setState(() => _savingManualVillage = false);
    if (result == null) return;

    setState(() {
      _selectedVillage = {
        'location_id': result!['location_id'],
        'village_town_name': _manualVillageName.text.trim(),
        'mandal': _manualMandal.text.trim(),
        'district': _manualDistrict.text.trim(),
        'state': _manualState.text.trim(),
      };
      _villageSearch.text = _manualVillageName.text.trim();
      _villageResults = [];
      _manualVillageEntry = false;
    });
  }

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
            decoration: const InputDecoration(labelText: 'PIN Code', helperText: 'Enter PIN code first — villages shown are limited to this PIN'),
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
            decoration: const InputDecoration(labelText: 'Search Village/Town'),
            onChanged: (v) {
              setState(() {
                _selectedVillage = null;
                _manualVillageEntry = false;
              });
              _searchVillages(v);
            },
          ),
          if (_villageSearchAttempted && _villageResults.isEmpty && _selectedVillage == null && !_manualVillageEntry)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                onPressed: () => setState(() {
                  _manualVillageEntry = true;
                  _manualVillageName.text = _villageSearch.text.trim();
                }),
                child: Text('"${_villageSearch.text.trim()}" not found — add it'),
              ),
            ),
          if (_manualVillageEntry)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: ManaColors.surfaceSunken)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _manualVillageName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Village/Town Name *', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _manualAreaType,
                    decoration: const InputDecoration(labelText: 'Area Type *', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'Village', child: Text('Village')),
                      DropdownMenuItem(value: 'Town', child: Text('Town')),
                    ],
                    onChanged: (v) => setState(() => _manualAreaType = v ?? 'Village'),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _manualMandal,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Mandal *', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _manualDistrict,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'District *', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _manualState,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'State *', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _savingManualVillage ? null : () => setState(() => _manualVillageEntry = false),
                        child: const ManaText('cancel'),
                      ),
                      const SizedBox(width: 8),
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
                            ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const ManaText('save & select'),
                      ),
                    ],
                  ),
                ],
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
                    title: ManaText.raw(label, style: const TextStyle(fontSize: 13)),
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
              style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ],
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
                      villageId: _selectedVillage!['location_id'] as String,
                      villageName: _selectedVillage!['village_town_name'] as String,
                      mandal: _selectedVillage!['mandal'] as String,
                      district: _selectedVillage!['district'] as String,
                      state: _selectedVillage!['state'] as String,
                    ),
                  )
              : null,
          child: const ManaText('save'),
        ),
      ],
    );
  }
}
