import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/widgets/use_my_location_button.dart';
import '../../../shared/soft_delete_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../../../shared/document_viewer.dart';
import '../../../shared/translation_service.dart';
import '../state/customer_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// OW-004 — Customer Management. List is the default landing state (C2);
/// row click opens Customer Profile directly (C3 RESOLVED — no per-row
/// context menu); "Add Customer" is a header action (C4 sub-flow).
class CustomerManagementScreen extends ConsumerStatefulWidget {
  final String businessId;
  /// 'register' opens the Add Customer sheet straight away, so the
  /// dashboard's Register Customer tile lands on the form rather than on a
  /// list the person then has to find a button in. Registration on the
  /// doorstep is a two-tap job or it does not get done.
  final String? initialAction;

  const CustomerManagementScreen({
    super.key,
    required this.businessId,
    this.initialAction,
  });

  @override
  ConsumerState<CustomerManagementScreen> createState() => _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends ConsumerState<CustomerManagementScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerListProvider.notifier).load(widget.businessId);
      if (widget.initialAction == 'register') {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _AddCustomerSheet(businessId: widget.businessId),
        ).then((_) => ref.read(customerListProvider.notifier).load(widget.businessId));
      }
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerListProvider);

    return Scaffold(
      appBar: AppBar(
        // Explicit leading, not the AppBar-implied one: this screen is
        // reached both via Quick Actions (context.push — canPop is true,
        // default back arrow would appear on its own) AND via the footer
        // nav's "Customers" tab (context.go — REPLACES history, so
        // canPop is false and AppBar quietly omits the back arrow
        // entirely, dead-ending here). Always fall back to Home so
        // there's a way out either way.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).canPop()
              ? Navigator.of(context).pop()
              : context.go('/ow-001', extra: widget.businessId),
        ),
        title: ManaText.raw(ref.t('customer_management')),
        actions: [
          IconButton(
            tooltip: ref.t('add_customer'),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => _AddCustomerSheet(businessId: widget.businessId),
            ).then((_) => ref.read(customerListProvider.notifier).load(widget.businessId)),
          ),
          // Item 4.2 — mirrors OW-002's "Add Existing Agent" header action.
          // Same sheet, but locked to the search-and-link path: a customer
          // who already holds a MANA LINE ID must never be re-registered as
          // a new person, which is exactly what the shared sheet does today
          // when a search comes back empty.
          IconButton(
            tooltip: ref.t('existing_customers'),
            icon: const Icon(Icons.badge_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => _AddCustomerSheet(businessId: widget.businessId, existingOnly: true),
            ).then((_) => ref.read(customerListProvider.notifier).load(widget.businessId)),
          ),
          // OW-014 Global Workflow — for a customer who was already on the
          // books before this business joined MANA LINE. The screen was
          // fully built but had no link from anywhere in the app.
          IconButton(
            tooltip: ref.t('pre_existing_customer'),
            icon: const Icon(Icons.history_edu_outlined),
            onPressed: () => context
                .push('/ow-014?type=customer', extra: widget.businessId)
                .then((_) => ref.read(customerListProvider.notifier).load(widget.businessId)),
          ),
        ],
      ),
      body: SafeArea(
        child: state.loading && state.customers.isEmpty
            ? const ManaSkeletonList(itemHeight: 96)
            // A fixed non-scrolling header above an Expanded list overflows
            // vertically once the search field + filter chips + village
            // dropdown + sorted-by note grow taller than the screen at large
            // text scale (a real bug this screen's own first layout test
            // caught — it never had one before). Folding the header into
            // index 0 of the same scrollable list — same pattern already
            // used for the transaction-history screens — lets it scroll
            // away with everything else instead of demanding fixed space.
            : RefreshIndicator(
                onRefresh: () => ref.read(customerListProvider.notifier).load(widget.businessId),
                child: ListView.builder(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  itemCount: 1 + (state.filtered.isEmpty ? 1 : state.filtered.length),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: ManaSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _search,
                              focusNode: _searchFocus,
                              decoration: InputDecoration(
                                hintText: ref.t('search_by_name_mlid_phone'),
                                prefixIcon: const Icon(Icons.search),
                              ),
                              onChanged: (v) => ref.read(customerListProvider.notifier).setSearchQuery(v),
                            ),
                            const SizedBox(height: ManaSpacing.sm),
                            _StatusFilterChips(state: state),
                            const SizedBox(height: ManaSpacing.sm),
                            _VillageFilterDropdown(state: state),
                            const SizedBox(height: ManaSpacing.xs),
                            ManaText.raw(
                              ref.t('sorted_by_note_customers'),
                              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    }
                    if (state.filtered.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw(ref.t('no_customers_match_view'),
                              style: TextStyle(color: ManaColors.textSecondary)),
                        ),
                      );
                    }
                    final c = state.filtered[i - 1];
                    return _CustomerRow(
                      customer: c,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CustomerProfileScreen(businessId: widget.businessId, customer: c),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _StatusFilterChips extends ConsumerWidget {
  final CustomerListState state;
  const _StatusFilterChips({required this.state});

  static const _statuses = ['Active', 'Suspended', 'Removed'];
  static const _statusKeys = {'Active': 'active', 'Suspended': 'suspended', 'Removed': 'removed'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: ManaSpacing.xs,
      children: [
        ChoiceChip(
          label: ManaText.raw(ref.t('all')),
          selected: state.customerStatusFilter == null,
          onSelected: (_) => ref.read(customerListProvider.notifier).setCustomerStatusFilter(null),
        ),
        ..._statuses.map((s) => ChoiceChip(
              label: ManaText.raw(ref.t(_statusKeys[s]!)),
              selected: state.customerStatusFilter == s,
              onSelected: (_) => ref.read(customerListProvider.notifier).setCustomerStatusFilter(s),
            )),
      ],
    );
  }
}

// BUG FIXED this pass: setVillageFilter()/villageFilter's `filtered`
// predicate were both fully implemented in customer_state.dart, but no
// screen ever exposed a way to actually set one.
class _VillageFilterDropdown extends ConsumerWidget {
  final CustomerListState state;
  const _VillageFilterDropdown({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final villages = state.customers.map((c) => c.village).where((v) => v.isNotEmpty).toSet().toList()..sort();
    if (villages.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String?>(
      initialValue: state.villageFilter,
      // isExpanded: without it, the button sizes itself to the selected
      // item's intrinsic width — a long village name (or a wide Telugu
      // translation of "All Villages") then overflows the Row DropdownButton
      // lays its selected-value + arrow out in, since that Row has nothing
      // to constrain it to the field's actual width.
      isExpanded: true,
      decoration: InputDecoration(labelText: ref.t('village'), isDense: true),
      items: [
        DropdownMenuItem(
            value: null,
            child: ManaText.raw(ref.t('all_villages'), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ...villages.map((v) => DropdownMenuItem(
            value: v, child: ManaText.raw(v, maxLines: 1, overflow: TextOverflow.ellipsis))),
      ],
      onChanged: (v) => ref.read(customerListProvider.notifier).setVillageFilter(v),
    );
  }
}

class _CustomerRow extends ConsumerWidget {
  final CustomerSummary customer;
  final VoidCallback onTap;
  const _CustomerRow({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagged = customer.membershipStatus != 'Active';
    // NOT a ListTile — same bug/fix as OW-006/AG-002/AG-003's due-rows:
    // ListTile's trailing slot assumes a bounded width/height, which a
    // two-line trailing column (amount + "Due X") does not fit inside once
    // text scale grows or the amount/village strings run long (a real
    // failure this screen's own first layout test caught — it never had
    // one before). Amount + Due go on their own row below the name/village
    // instead of sharing horizontal space with them.
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ManaVerificationRing(isVerified: true, size: 40),
              const SizedBox(width: ManaSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: ManaText.raw(customer.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        if (flagged) ...[
                          const SizedBox(width: ManaSpacing.xs),
                          ManaStatusPill(label: customer.membershipStatus, status: ManaStatus.bad),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    ManaText.raw(
                      '${customer.village} · ${customer.mlid} · LRI ${customer.lineRepaymentIndex}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                    ),
                    const SizedBox(height: ManaSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: ManaText.raw(_currency.format(customer.outstandingBalance),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        if (customer.todaysDue > 0) ...[
                          const SizedBox(width: ManaSpacing.sm),
                          Flexible(
                            child: ManaText.raw(
                                ref.t('due_note').replaceAll('{amount}', _currency.format(customer.todaysDue)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 16, color: ManaColors.statusWarn)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- C4 Create Customer sub-flow ---------------------------------------

class _AddCustomerSheet extends ConsumerStatefulWidget {
  final String businessId;
  /// Opened from the "Existing Customers" header action — a miss stays on
  /// the search stage instead of falling through to Create New.
  final bool existingOnly;
  const _AddCustomerSheet({required this.businessId, this.existingOnly = false});

  @override
  ConsumerState<_AddCustomerSheet> createState() => _AddCustomerSheetState();
}

enum _AddCustomerStage { search, found, createNew }

class _AddCustomerSheetState extends ConsumerState<_AddCustomerSheet> {
  _AddCustomerStage _stage = _AddCustomerStage.search;
  final _query = TextEditingController();
  CustomerSummary? _foundIdentity;
  bool _searching = false;
  bool _notFound = false;

  // Create New fields (reuses LR-004 field set per spec)
  final _fullName = TextEditingController();
  final _fatherHusband = TextEditingController();
  final _mobile = TextEditingController();
  final _aadhaar = TextEditingController();
  final _doorNo = TextEditingController();
  final _pinCode = TextEditingController();
  String? _gender;
  bool _submitting = false;
  String? _villageId;
  String? _selectedVillageLabel;
  List<Map<String, dynamic>> _villageResults = [];
  final _villageSearch = TextEditingController();
  bool _villageSearchAttempted = false;
  bool _manualVillageEntry = false;
  final _manualVillageName = TextEditingController();
  final _manualPinCode = TextEditingController();
  final _manualMandal = TextEditingController();
  final _manualDistrict = TextEditingController();
  final _manualState = TextEditingController();
  String _manualAreaType = 'Village';
  bool _savingManualVillage = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    // The single box is labeled "Search by Phone, Aadhaar, MANA LINE ID, or
    // Full Name" but searchIdentity() takes each as a separate named param
    // routed to a different owner_search_person() branch server-side — this
    // was previously ALWAYS sent as `fullName:`, so typing an MLID (e.g.
    // "MLTI067066774") queried full_name ILIKE '%MLTI067066774%' and never
    // matched, even for a person who genuinely exists. Classify by shape
    // (MLIDs are always "ML" + 2 letters + digits, per BR-181/182's MLPI/
    // MLTI scheme; Aadhaar is 12 digits; mobile is 10) and route to the
    // matching param instead of guessing everything is a name.
    final query = _query.text.trim();
    final isMlid = RegExp(r'^ML[A-Za-z]{2}\d+$').hasMatch(query);
    final digitsOnly = RegExp(r'^\d+$').hasMatch(query);
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).searchIdentity(
            mlid: isMlid ? query : null,
            aadhaar: !isMlid && digitsOnly && query.length == 12 ? query : null,
            phone: !isMlid && digitsOnly && query.length == 10 ? query : null,
            fullName: isMlid || digitsOnly ? null : query,
          );
    });
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (result != null) {
        _foundIdentity = result;
        _notFound = false;
        _stage = _AddCustomerStage.found;
      } else if (widget.existingOnly) {
        _notFound = true;
      } else {
        _stage = _AddCustomerStage.createNew;
      }
    });
  }

  Future<void> _linkExisting() async {
    if (_foundIdentity == null || _foundIdentity!.personId == null) return;
    setState(() => _submitting = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).linkExisting(widget.businessId, _foundIdentity!.personId!);
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _searchVillages(String query) async {
    final pin = _pinCode.text.trim();
    if (pin.length != 6) {
      setState(() {
        _villageResults = [];
        _villageSearchAttempted = false;
      });
      return;
    }
    if (query.trim().length < 2) {
      setState(() {
        _villageResults = [];
        _villageSearchAttempted = false;
      });
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('locations')
          .select('location_id, village_town_name, mandal, district, state, pin_code')
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
      // A failed search must still unlock the "add if not found" fallback
      // — silently swallowing this here (no catch, pre-fix) meant
      // _villageSearchAttempted never flipped true, so NEITHER the
      // results list NOR the manual-add prompt ever appeared: the person
      // was stuck with no visible next step at all.
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
        _manualPinCode.text.trim().length != 6) {
      return;
    }
    setState(() => _savingManualVillage = true);
    final result = await NetworkErrorHandler.run(context, () async {
      final rows = await Supabase.instance.client.schema('app').rpc('add_location_if_missing', params: {
        'p_pin_code': _manualPinCode.text.trim(),
        'p_village_town_name': _manualVillageName.text.trim(),
        'p_area_type': _manualAreaType,
        'p_mandal': _manualMandal.text.trim(),
        'p_district': _manualDistrict.text.trim(),
        'p_state': _manualState.text.trim(),
      });
      return (rows as List).first as Map<String, dynamic>;
    });
    if (!mounted) return;
    setState(() => _savingManualVillage = false);
    if (result == null) return;

    final label =
        '${_manualVillageName.text.trim()} — ${_manualMandal.text.trim()}, ${_manualDistrict.text.trim()}, ${_manualState.text.trim()}';
    setState(() {
      _villageId = result['location_id'] as String;
      _selectedVillageLabel = label;
      _villageSearch.text = _manualVillageName.text.trim();
      _villageResults = [];
      _manualVillageEntry = false;
    });
    if (mounted) {
      final wasExisting = result['was_existing'] as bool? ?? false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(wasExisting ? ref.t('village_already_existed_note') : ref.t('village_added_note'))),
      );
    }
  }

  bool get _canCreateNew =>
      _fullName.text.trim().length >= 2 &&
      _fatherHusband.text.trim().length >= 2 &&
      _gender != null &&
      _mobile.text.trim().length == 10 &&
      (_aadhaar.text.trim().isEmpty || _aadhaar.text.trim().length == 12) &&
      _pinCode.text.trim().length == 6 &&
      _doorNo.text.trim().isNotEmpty &&
      _villageId != null;

  Future<void> _createNew() async {
    setState(() => _submitting = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).createNew(
            businessId: widget.businessId,
            fullName: _fullName.text.trim(),
            fatherHusbandName: _fatherHusband.text.trim(),
            genderDigit: _gender!,
            mobileNumber: _mobile.text.trim(),
            aadhaarNumber: _aadhaar.text.trim().isEmpty ? null : _aadhaar.text.trim(),
            doorNo: _doorNo.text.trim(),
            pinCode: _pinCode.text.trim(),
            villageId: _villageId!,
          );
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: ListView(
            controller: scrollController,
            children: [
              ManaText.raw(ref.t(widget.existingOnly ? 'existing_customers' : 'add_customer'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: ManaSpacing.lg),
              if (_stage == _AddCustomerStage.search) ..._searchStage(),
              if (_stage == _AddCustomerStage.found) ..._foundStage(),
              if (_stage == _AddCustomerStage.createNew) ..._createNewStage(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _searchStage() => [
        ManaText.raw(
          widget.existingOnly ? ref.t('find_link_customer_note') : ref.t('search_by_phone_aadhaar_mlid_name'),
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                decoration: InputDecoration(labelText: ref.t('search')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            ElevatedButton(
              onPressed: (_query.text.trim().isNotEmpty && !_searching) ? _search : null,
              child: _searching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('search')),
            ),
          ],
        ),
        // existingOnly never falls through to Create New — an already-
        // registered customer must be linked, not duplicated. Say so, and
        // point at the action that does register someone new.
        if (_notFound) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(
            ref.t('not_found_note'),
            style: TextStyle(fontSize: 13, color: ManaColors.statusBad),
          ),
        ],
      ];

  List<Widget> _foundStage() => [
        ManaText.raw(ref.t('identity_found'), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        Card(
          child: ListTile(
            leading: const ManaVerificationRing(isVerified: true, size: 40),
            title: ManaText.raw(_foundIdentity!.fullName),
            subtitle: ManaText.raw(_foundIdentity!.mlid),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: _submitting ? null : _linkExisting,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : ManaText.raw(ref.t('confirm_and_link_to_business')),
        ),
        TextButton(
          onPressed: () => setState(() => _stage = _AddCustomerStage.search),
          child: ManaText.raw(ref.t('search_again')),
        ),
      ];

  List<Widget> _createNewStage() => [
        ManaText.raw(ref.t('no_match_create_new_identity'), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('new_customer_present_note'),
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: '${ref.t("full_name")} *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _fatherHusband,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: '${ref.t("father_husband_name")} *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _gender,
          decoration: InputDecoration(labelText: '${ref.t("gender")} *'),
          items: [
            DropdownMenuItem(value: '1', child: ManaText.raw(ref.t('male'))),
            DropdownMenuItem(value: '0', child: ManaText.raw(ref.t('female'))),
          ],
          onChanged: (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: '${ref.t("mobile_number")} *'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _aadhaar,
          keyboardType: TextInputType.number,
          maxLength: 12,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: ref.t('aadhaar_optional_note')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        // Fills PIN and village from where the Owner is standing — which,
        // for this sheet, is the customer's doorstep. It does NOT capture
        // the coordinates: createNew already takes its own fix at save
        // time, and taking a second one here would record whichever was
        // earlier rather than where the address was actually confirmed.
        UseMyLocationButton(
          onCaptured: (place) {
            setState(() {
              if (place.pinCode != null) _pinCode.text = place.pinCode!;
              if (place.village != null) {
                _villageSearch.text = place.village!;
                _villageId = null;
                _selectedVillageLabel = null;
              }
            });
            if (_pinCode.text.trim().length == 6) _searchVillages(_villageSearch.text);
          },
        ),
        TextField(
          controller: _pinCode,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(labelText: '${ref.t("pin_code")} *', helperText: ref.t('pin_code_helper')),
          onChanged: (_) {
            setState(() {
              _villageId = null;
              _selectedVillageLabel = null;
            });
            _searchVillages(_villageSearch.text);
          },
        ),
        TextField(
          controller: _doorNo,
          decoration: InputDecoration(labelText: '${ref.t("door_house_no")} *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _villageSearch,
          decoration: InputDecoration(labelText: '${ref.t("search_village_town")} *'),
          onChanged: (v) {
            setState(() {
              _villageId = null;
              _selectedVillageLabel = null;
              _manualVillageEntry = false;
            });
            _searchVillages(v);
          },
        ),
        if (_villageResults.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.only(top: ManaSpacing.xs),
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
                    _villageId = v['location_id'] as String;
                    _selectedVillageLabel = label;
                    _villageSearch.text = v['village_town_name'] as String;
                    _villageResults = [];
                  }),
                );
              },
            ),
          ),
        if (_villageSearchAttempted && _villageResults.isEmpty && _villageId == null && !_manualVillageEntry)
          Padding(
            padding: const EdgeInsets.only(top: ManaSpacing.xs),
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () => setState(() {
                _manualVillageEntry = true;
                _manualVillageName.text = _villageSearch.text.trim();
                _manualPinCode.text = _pinCode.text.trim();
              }),
              child: ManaText.raw(ref.t('village_not_found_add_it').replaceAll('{query}', _villageSearch.text.trim())),
            ),
          ),
        if (_manualVillageEntry)
          Container(
            margin: const EdgeInsets.only(top: ManaSpacing.sm),
            padding: const EdgeInsets.all(ManaSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: ManaColors.surfaceSunken),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(ref.t('add_new_village'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: ManaSpacing.sm),
                TextField(
                  controller: _manualVillageName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('village_town_name_field')),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.sm),
                TextField(
                  controller: _manualPinCode,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(labelText: '${ref.t("pin_code")} *'),
                  onChanged: (_) => setState(() {}),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _manualAreaType,
                  decoration: InputDecoration(labelText: ref.t('area_type_field')),
                  items: [
                    DropdownMenuItem(value: 'Village', child: ManaText.raw(ref.t('village'))),
                    DropdownMenuItem(value: 'Town', child: ManaText.raw(ref.t('town'))),
                  ],
                  onChanged: (v) => setState(() => _manualAreaType = v ?? 'Village'),
                ),
                const SizedBox(height: ManaSpacing.sm),
                TextField(
                  controller: _manualMandal,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('mandal_field')),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.sm),
                TextField(
                  controller: _manualDistrict,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('district_field')),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.sm),
                TextField(
                  controller: _manualState,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('state_field')),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ManaSpacing.sm),
                Row(
                  children: [
                    TextButton(
                      onPressed: _savingManualVillage ? null : () => setState(() => _manualVillageEntry = false),
                      child: ManaText.raw(ref.t('cancel')),
                    ),
                    const SizedBox(width: ManaSpacing.sm),
                    ElevatedButton(
                      onPressed: (_savingManualVillage ||
                              _manualVillageName.text.trim().isEmpty ||
                              _manualMandal.text.trim().isEmpty ||
                              _manualDistrict.text.trim().isEmpty ||
                              _manualState.text.trim().isEmpty ||
                              _manualPinCode.text.trim().length != 6)
                          ? null
                          : _saveManualVillage,
                      child: _savingManualVillage
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : ManaText.raw(ref.t('save_and_select')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_selectedVillageLabel != null) ...[
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(ref.t('selected_note').replaceAll('{label}', _selectedVillageLabel!),
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
        ],
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: (_canCreateNew && !_submitting) ? _createNew : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : ManaText.raw(ref.t('create_and_link_to_business')),
        ),
      ];
}

// --- C5 Customer Profile (tabbed drill-in) ------------------------------

class CustomerProfileScreen extends ConsumerWidget {
  final String businessId;
  final CustomerSummary customer;
  const CustomerProfileScreen({super.key, required this.businessId, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(customerProfileProvider(customer.customerId));

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(customer.fullName),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: ref.t('summary')),
              Tab(text: ref.t('loans')),
              Tab(text: ref.t('collections')),
              Tab(text: ref.t('documents')),
              Tab(text: ref.t('remarks')),
              Tab(text: ref.t('history')),
              Tab(text: ref.t('audit')),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) => _handleAction(context, ref, v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'new_loan', child: ManaText.raw(ref.t('new_loan'))),
                PopupMenuItem(value: 'collect', child: ManaText.raw(ref.t('collect_payment'))),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'suspend', child: ManaText.raw(ref.t('suspend_customer'))),
                PopupMenuItem(value: 'archive', child: ManaText.raw(ref.t('archive_customer'))),
              ],
            ),
          ],
        ),
        body: asyncProfile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
              child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: ManaText.raw(ref.t('could_not_load_profile').replaceAll('{error}', '$e'), textAlign: TextAlign.center),
          )),
          data: (profile) => TabBarView(
            children: [
              _SummaryTab(customer: customer, profile: profile),
              _LoansTab(profile: profile),
              _CollectionsTab(profile: profile),
              _DocumentsTab(customerId: customer.customerId),
              _RemarksTab(customerId: customer.customerId, profile: profile),
              const _HistoryTab(),
              const _AuditTab(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'new_loan':
        // BUG FIXED this pass: router.dart's /ow-005 route now reads
        // businessId from `extra` (aligned with every other route this
        // session), with the prefilled customer as a query param —
        // this used to pass customerId as `extra`, which the route
        // read as businessId until prefilledCustomerId was activated.
        context.push('/ow-005?customerId=${customer.customerId}', extra: businessId);
      case 'collect':
        context.push('/ow-006', extra: customer.customerId);
      case 'suspend':
      case 'archive':
        final status = action == 'suspend' ? 'Suspended' : 'Removed';
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: ManaText.raw(ref
                .t('confirm_action_title')
                .replaceAll('{action}', action == 'suspend' ? ref.t('suspend_customer') : ref.t('archive_customer'))),
            content: ManaText.raw(
                ref.t('never_deletes_history_note').replaceAll('{name}', customer.fullName)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: ManaText.raw(ref.t('cancel'))),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: ManaText.raw(ref.t('confirm'))),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        await NetworkErrorHandler.run(context, () async {
          return ref.read(customerListProvider.notifier).updateStatus(businessId, customer.customerId, status);
        });
    }
  }
}

class _SummaryTab extends ConsumerWidget {
  final CustomerSummary customer;
  final CustomerProfile profile;
  const _SummaryTab({required this.customer, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const Center(child: ManaVerificationRing(isVerified: true, size: 72)),
        const SizedBox(height: ManaSpacing.md),
        Center(
            child:
                ManaText.raw(customer.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
        Center(child: ManaText.raw(customer.mlid, style: TextStyle(color: ManaColors.textSecondary))),
        const SizedBox(height: ManaSpacing.lg),
        _row(ref.t('father_husband_name'), customer.fatherHusbandName),
        _row(ref.t('village'), customer.village),
        _row(ref.t('phone_number'), customer.phoneNumber),
        _row(ref.t('occupation'), profile.occupation ?? '—'),
        _row(ref.t('address'), profile.address ?? '—'),
        _row(ref.t('customer_since'), DateFormat('d MMM yyyy').format(profile.customerSince)),
        _row(ref.t('current_agent'), profile.currentAgent ?? '—'),
        _row(ref.t('current_status'), customer.membershipStatus),
        _row(ref.t('line_repayment_index'), '${customer.lineRepaymentIndex}'),
        _row(ref.t('loan_count'), '${customer.activeLoanCount}'),
        _row(ref.t('outstanding_balance'), _currency.format(customer.outstandingBalance)),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: ManaText.raw(label, style: TextStyle(color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}

class _LoansTab extends ConsumerWidget {
  final CustomerProfile profile;
  const _LoansTab({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profile.loans.isEmpty) {
      return Center(
        child: ManaText.raw(ref.t('no_loans_yet_period'), style: TextStyle(color: ManaColors.textSecondary)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: profile.loans
          .map((l) => Card(
                child: ListTile(
                  title: ManaText.raw(l.loanNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: ManaText.raw(
                    ref
                        .t('issued_outstanding_note')
                        .replaceAll('{date}', DateFormat('d MMM yyyy').format(l.issueDate))
                        .replaceAll('{amount}', _currency.format(l.outstanding)),
                    style: const TextStyle(fontSize: 16),
                  ),
                  trailing: ManaStatusPill(
                    label: l.status,
                    status: l.status == 'Active'
                        ? ManaStatus.good
                        : l.status == 'Penalty'
                            ? ManaStatus.bad
                            : ManaStatus.neutral,
                  ),
                  // Stale comment fixed: OW-007 has been built for a
                  // while (reachable from ow_009_daily_record_book.dart)
                  // — this just never got updated to link to it.
                  onTap: () => context.push('/ow-007', extra: l.loanId),
                ),
              ))
          .toList(),
    );
  }
}

class _CollectionsTab extends ConsumerWidget {
  final CustomerProfile profile;
  const _CollectionsTab({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profile.collections.isEmpty) {
      return Center(
        child: ManaText.raw(ref.t('no_collections_yet'), style: TextStyle(color: ManaColors.textSecondary)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: profile.collections
          .map((c) => ListTile(
                leading: Icon(Icons.receipt_long_outlined, color: ManaColors.brand),
                title: ManaText.raw(_currency.format(c.amount)),
                subtitle: ManaText.raw('${c.paymentMode} · ${c.collector} · #${c.receiptNumber}'),
                trailing: ManaText.raw(DateFormat('d MMM').format(c.businessDate),
                    style: TextStyle(fontSize: 16, color: ManaColors.textSecondary)),
              ))
          .toList(),
    );
  }
}

class _DocumentsTab extends ConsumerWidget {
  final String customerId;
  const _DocumentsTab({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DocumentsListView(
      expectedTypes: const [
        'Aadhaar',
        'Photo',
        'Address Proof',
        'Customer Agreement',
        'Loan Agreement',
        'Guarantor Documents',
        'Other Documents',
      ],
      fetchDocuments: () => ref.read(customerApiServiceProvider).fetchCustomerDocuments(customerId: customerId),
    );
  }
}

class _RemarksTab extends ConsumerStatefulWidget {
  final String customerId;
  final CustomerProfile profile;
  const _RemarksTab({required this.customerId, required this.profile});

  @override
  ConsumerState<_RemarksTab> createState() => _RemarksTabState();
}

class _RemarksTabState extends ConsumerState<_RemarksTab> {
  final _remark = TextEditingController();
  bool _submitting = false;

  Future<void> _add() async {
    if (_remark.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    await NetworkErrorHandler.run(context, () async {
      return ref.read(customerProfileProvider(widget.customerId).notifier).addRemark(_remark.text.trim());
    });
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _remark.clear();
    });
  }

  /// A remark carries no money, so no balance moves — the dialog is told
  /// that rather than warning about a closing balance that will not change.
  Future<void> _deleteRemark(CustomerRemark r) async {
    final deleted = await ConfirmDeleteDialog.show(
      context,
      entity: DeletableEntity.customerRemark,
      recordId: r.remarkId,
      description: r.remark,
      affectsBalances: false,
    );
    if (deleted && mounted) ref.invalidate(customerProfileProvider(widget.customerId));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            children: widget.profile.remarks.isEmpty
                ? [ManaText.raw(ref.t('no_remarks_yet'), style: TextStyle(color: ManaColors.textSecondary))]
                : widget.profile.remarks
                    .map((r) => Card(
                          child: ListTile(
                            title: ManaText.raw(r.remark),
                            subtitle: ManaText.raw('${r.enteredBy} · ${DateFormat('d MMM yyyy').format(r.date)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Not Flexible: a flexible child in a
                                // MainAxisSize.min Row makes it claim the
                                // whole tile width, which ListTile.trailing
                                // rejects outright.
                                ManaStatusPill(
                                  label: r.priority,
                                  status: r.priority == 'High' ? ManaStatus.bad : ManaStatus.neutral,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  color: ManaColors.statusBad,
                                  tooltip: ref.t('delete'),
                                  onPressed: () => _deleteRemark(r),
                                ),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _remark,
                    decoration: InputDecoration(hintText: ref.t('add_a_remark_hint')),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                IconButton(
                  onPressed: _submitting ? null : _add,
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: ManaText.raw(
          ref.t('customer_history_tab_note'),
          textAlign: TextAlign.center,
          style: TextStyle(color: ManaColors.textSecondary),
        ),
      ),
    );
  }
}

class _AuditTab extends ConsumerWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: ManaText.raw(
          ref.t('customer_audit_tab_note'),
          textAlign: TextAlign.center,
          style: TextStyle(color: ManaColors.textSecondary),
        ),
      ),
    );
  }
}
