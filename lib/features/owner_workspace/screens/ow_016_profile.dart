import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../login_registration/state/auth_flow_state.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
              'full_name, mlid, mobile_number, verification_ring, father_husband_name')
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
    if (personId == null) return;

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
        'from_date': DateTime.now().toIso8601String().split('T').first,
      });
      return true;
    });
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const ManaText('my profile'),
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
                      child: ManaText.raw(_error ?? 'Could not load profile.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: ManaColors.statusBad)),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    children: [
                      _IdentityCard(person: _person!),
                      const SizedBox(height: ManaSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const ManaText('address',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          TextButton.icon(
                            onPressed: _editAddress,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const ManaText('edit'),
                          ),
                        ],
                      ),
                      _AddressCard(address: _address),
                      const SizedBox(height: ManaSpacing.xl),
                      const ManaText('businesses owned',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: ManaSpacing.sm),
                      if (_businesses.isEmpty)
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: ManaSpacing.lg),
                          child: ManaText.raw('No businesses found.',
                              style:
                                  TextStyle(color: ManaColors.textSecondary)),
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
                          context.go('/lr-003');
                        },
                        icon: const Icon(Icons.logout,
                            color: ManaColors.statusBad),
                        label: const ManaText.raw('logout',
                            style: TextStyle(color: ManaColors.statusBad)),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final Map<String, dynamic> person;
  const _IdentityCard({required this.person});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Row(
          children: [
            const CircleAvatar(radius: 28, child: Icon(Icons.person, size: 28)),
            const SizedBox(width: ManaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText.raw(person['full_name'] as String? ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  ManaText.raw(person['mlid'] as String? ?? '',
                      style: const TextStyle(
                          color: ManaColors.textSecondary, fontSize: 13)),
                  ManaText.raw(person['mobile_number'] as String? ?? '',
                      style: const TextStyle(
                          color: ManaColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            _VerificationBadge(ring: person['verification_ring'] as String?),
          ],
        ),
      ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  final String? ring;
  const _VerificationBadge({required this.ring});
  @override
  Widget build(BuildContext context) {
    final color = ring == 'GREEN'
        ? ManaColors.statusGood
        : (ring == 'RED' ? ManaColors.statusBad : ManaColors.statusWarn);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12)),
      child: ManaText.raw(ring ?? '—',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final Map<String, dynamic>? address;
  const _AddressCard({required this.address});

  @override
  Widget build(BuildContext context) {
    if (address == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: ManaSpacing.md),
        child: ManaText.raw('No address on file.',
            style: TextStyle(color: ManaColors.textSecondary)),
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
class _AddressEditDialog extends StatefulWidget {
  final String? initialPinCode;
  const _AddressEditDialog({this.initialPinCode});
  @override
  State<_AddressEditDialog> createState() => _AddressEditDialogState();
}

class _AddressEditDialogState extends State<_AddressEditDialog> {
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
      title: const ManaText('edit address'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _doorNo,
                decoration: const InputDecoration(
                    labelText: 'Door / House No *', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pinCode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                    labelText: 'PIN Code *',
                    isDense: true,
                    helperText: 'Villages shown are limited to this PIN'),
                onChanged: (_) {
                  setState(() {
                    _selectedVillage = null;
                  });
                  _searchVillages(_villageSearch.text);
                },
              ),
              TextField(
                controller: _villageSearch,
                decoration: const InputDecoration(
                    labelText: 'Search Village/Town *', isDense: true),
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
                            style: const TextStyle(fontSize: 12)),
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
                  child: Text(
                      '"${_villageSearch.text.trim()}" not found — add it'),
                ),
              if (_manualVillageEntry) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _manualVillageName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Village/Town Name *', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _manualAreaType,
                  decoration: const InputDecoration(
                      labelText: 'Area Type *', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'Village', child: Text('Village')),
                    DropdownMenuItem(value: 'Town', child: Text('Town')),
                  ],
                  onChanged: (v) =>
                      setState(() => _manualAreaType = v ?? 'Village'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _manualMandal,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Mandal *', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _manualDistrict,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'District *', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _manualState,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'State *', isDense: true),
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
                      child: const ManaText('cancel'),
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
                          : const ManaText('save & select'),
                    ),
                  ],
                ),
              ],
              if (_selectedVillage != null) ...[
                const SizedBox(height: 6),
                ManaText.raw(
                  'Selected: ${_selectedVillage!['village_town_name']} — ${_selectedVillage!['mandal']}, ${_selectedVillage!['district']}, ${_selectedVillage!['state']}',
                  style: const TextStyle(
                      fontSize: 12, color: ManaColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const ManaText('cancel')),
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
          child: const ManaText('save'),
        ),
      ],
    );
  }
}
