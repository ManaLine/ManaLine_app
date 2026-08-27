import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_label_value_row.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_filter_row.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_member_roster.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/widgets/use_my_location_button.dart';
import '../../../shared/soft_delete_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../../../shared/document_viewer.dart';
import '../../../shared/customer_row.dart';
import '../../../shared/customer_collections_tab.dart';
import '../../../shared/translation_service.dart';
import 'ow_001_owner_home_dashboard.dart' show UniversalSearchScreen;
import '../state/customer_state.dart';
import '../../../design/components/mana_info_hint.dart';
import '../../../design/components/mana_call_button.dart';


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
  // The search controller and focus node went with the hand-rolled header —
  // ManaMemberRoster owns the search field now.

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

  void _reload() => ref.read(customerListProvider.notifier).load(widget.businessId);

  /// The three ways to add a customer, in one sheet behind one FAB.
  ///
  /// These were three separate AppBar icon buttons — a person-add glyph, a
  /// badge glyph and a history glyph — which is three unlabelled icons
  /// competing for the same corner and no way to tell them apart without
  /// long-pressing each. As sheet rows they carry their names.
  List<MemberAction> _addActions() => [
        MemberAction(
          label: ref.t('add_customer'),
          icon: Icons.person_add_alt_1_outlined,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => _AddCustomerSheet(businessId: widget.businessId),
          ).then((_) => _reload()),
        ),
        // Locked to search-and-link: a customer who already holds a MANA LINE
        // ID must never be re-registered as a new person, which is what the
        // shared sheet does when a search comes back empty.
        MemberAction(
          label: ref.t('existing_customers'),
          icon: Icons.badge_outlined,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => _AddCustomerSheet(businessId: widget.businessId, existingOnly: true),
          ).then((_) => _reload()),
        ),
        MemberAction(
          label: ref.t('pre_existing_customer'),
          icon: Icons.history_edu_outlined,
          onTap: () => context
              .push('/ow-014?type=customer', extra: widget.businessId)
              .then((_) => _reload()),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerListProvider);

    return Scaffold(
      appBar: ManaAppBar(
        // Explicit leading, not the AppBar-implied one: this screen is
        // reached both via Quick Actions (context.push — canPop is true,
        // default back arrow would appear on its own) AND via the footer
        // nav's "Customers" tab (context.go — REPLACES history, so
        // canPop is false and AppBar quietly omits the back arrow
        // entirely, dead-ending here). Always fall back to Home so
        // there's a way out either way.
        homeRoute: '/ow-001', homeExtra: widget.businessId,
        // The three add-paths moved out of here and into the roster's single
        // Add FAB — see _addActions.
        title: ref.t('customer_management'),
        actions: [
          // Search is an ICON, not a box holding a third of the header.
          //
          // It opens the same global search the rest of the app uses, which
          // finds a person across every workspace rather than filtering this
          // one list -- an Owner looking for somebody usually does not know
          // which screen they are on.
          IconButton(
            tooltip: ref.t('search'),
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    UniversalSearchScreen(businessId: widget.businessId),
              ),
            ),
          ),
        ],
        // Village, order and status live in the header now.
        //
        // They were the first four things in the body, so on a real handset a
        // fifth of the screen went to controls before the first customer
        // appeared, and every one of them scrolled away with the list the
        // moment the Owner started looking. In the header they stay put, and
        // the body is customers.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                ManaSpacing.md, 0, ManaSpacing.md, ManaSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The same row the collection round uses: where, in what
                // order, and which of them. The two screens filter the same
                // book and had drifted into different shapes -- and the sort
                // was a line of grey text nobody could change.
                ManaFilterRow(
                  village: _VillageFilterDropdown(state: state),
                  sort: _SortDropdown(state: state),
                  third: _StatusFilterDropdown(state: state),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: state.loading && state.customers.isEmpty
            ? const ManaSkeletonList(itemHeight: 96)
            : RefreshIndicator(
                onRefresh: () => ref.read(customerListProvider.notifier).load(widget.businessId),
                // CONTROLLED roster: this screen's notifier already filters
                // AND sorts (customer_state's `sorted`), so the roster renders
                // state.filtered as-is and reports search/status changes back
                // rather than re-filtering. Letting the widget filter would
                // duplicate that logic and silently drop the ordering.
                child: ManaMemberRoster(
                  // Drawn in the app bar instead — see `bottom:` above.
                  showControls: false,
                  heading: ref.t('customers'),
                  members: [
                    for (final c in state.filtered)
                      MemberEntry(
                        id: c.customerId,
                        name: c.fullName,
                        subtitle: [c.mlid, c.village].where((s) => s.isNotEmpty).join(' · '),
                        status: c.membershipStatus,
                      ),
                  ],
                  filterLabels: [ref.t('all'), ref.t('active'), ref.t('suspended')],
                  statusValues: const ['Active', 'Suspended'],
                  statusValue: state.customerStatusFilter,
                  onStatusChanged: (v) =>
                      ref.read(customerListProvider.notifier).setCustomerStatusFilter(v),
                  onSearchChanged: (v) =>
                      ref.read(customerListProvider.notifier).setSearchQuery(v),
                  searchHint: ref.t('search_by_name_mlid_phone'),
                  emptyLabel: ref.t('no_customers_match_view'),
                  extraFilter: _VillageFilterDropdown(state: state),
                  footnote: ref.t('sorted_by_note_customers'),
                  addLabel: ref.t('add_a_customer'),
                  addActions: _addActions(),
                  // The customer row carries money — outstanding amount and a
                  // due date — and is deliberately not a ListTile: that
                  // trailing slot stopped fitting a two-line amount column at
                  // raised text scale, which this screen's first layout test
                  // caught. Keeping its own row rather than losing the money
                  // to the default one.
                  rowBuilder: (entry, _) {
                    final c = state.filtered.firstWhere((x) => x.customerId == entry.id);
                    return ManaCustomerRow(
                      customer: c,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CustomerProfileScreen(businessId: widget.businessId, customer: c),
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

/// What the list is ordered by.
///
/// This used to be a line of grey text -- "Sorted by: village -> highest
/// outstanding -> today's due -> name" -- describing an order nobody could
/// change. Village stays the default, because a round is walked one village
/// at a time; the rest answer questions asked at a desk.
class _SortDropdown extends ConsumerWidget {
  final CustomerListState state;
  const _SortDropdown({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaFilterDropdown<CustomerSort>(
      label: ref.t('sorted_by'),
      value: state.sort,
      items: [
        DropdownMenuItem(
            value: CustomerSort.village, child: ManaText.raw(ref.t('village'))),
        DropdownMenuItem(
            value: CustomerSort.outstanding,
            child: ManaText.raw(ref.t('outstanding'))),
        DropdownMenuItem(
            value: CustomerSort.todaysDue,
            child: ManaText.raw(ref.t('todays_due'))),
        DropdownMenuItem(
            value: CustomerSort.name, child: ManaText.raw(ref.t('name_field'))),
      ],
      onChanged: (v) => ref
          .read(customerListProvider.notifier)
          .setSort(v ?? CustomerSort.village),
    );
  }
}

/// Active / Suspended, or everybody.
///
/// Lifted out of the roster's heading row so it can sit beside the village
/// picker in the header. Same three values the roster offered; the difference
/// is only where it is drawn and that it reports to the notifier, which is
/// what actually filters this screen.
class _StatusFilterDropdown extends ConsumerWidget {
  final CustomerListState state;
  const _StatusFilterDropdown({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonFormField<String?>(
      initialValue: state.customerStatusFilter,
      isExpanded: true,
      decoration: InputDecoration(labelText: ref.t('status'), isDense: true),
      items: [
        DropdownMenuItem(
            value: null,
            child: ManaText.raw(ref.t('all'),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        for (final v in const ['Active', 'Suspended'])
          DropdownMenuItem(
              value: v,
              child: ManaText.raw(v, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) =>
          ref.read(customerListProvider.notifier).setCustomerStatusFilter(v),
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
    // Counted, not just listed. Village is the axis this book is organised on
    // -- a round is a village, a customer is placed by one -- and the count is
    // what makes the filter answerable at a glance: "Uranduru has 12" is the
    // question the Owner is actually asking when they open this.
    final counts = <String, int>{};
    for (final c in state.customers) {
      if (c.village.isNotEmpty) counts[c.village] = (counts[c.village] ?? 0) + 1;
    }
    final villages = counts.keys.toList()..sort();
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
            child: ManaText.raw('${ref.t('all_villages')} · ${state.customers.length}',
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        ...villages.map((v) => DropdownMenuItem(
            value: v,
            child: ManaText.raw('$v · ${counts[v]}',
                maxLines: 1, overflow: TextOverflow.ellipsis))),
      ],
      onChanged: (v) => ref.read(customerListProvider.notifier).setVillageFilter(v),
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

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _query.dispose();
    _fullName.dispose();
    _fatherHusband.dispose();
    _mobile.dispose();
    _aadhaar.dispose();
    _doorNo.dispose();
    _pinCode.dispose();
    _villageSearch.dispose();
    _manualVillageName.dispose();
    _manualPinCode.dispose();
    _manualMandal.dispose();
    _manualDistrict.dispose();
    _manualState.dispose();
    super.dispose();
  }
  _AddCustomerStage _stage = _AddCustomerStage.search;
  final _query = TextEditingController();
  CustomerSummary? _foundIdentity;

  /// Every person the search matched. A name is not unique, so this is
  /// routinely more than one — see CustomerApiService.searchIdentity.
  List<CustomerSummary> _results = const [];
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
      final matches = result ?? const <CustomerSummary>[];
      _results = matches;
      // Auto-select only when there is exactly one — with several people
      // called Sai, picking the first for the Owner is how the wrong person
      // gets linked to a business.
      _foundIdentity = matches.length == 1 ? matches.first : null;
      if (matches.isNotEmpty) {
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

  /// What the SERVER actually requires, and nothing more.
  ///
  /// This asked for seven fields at a doorstep. register_new_customer needs
  /// three: persons is NOT NULL on full_name, father_husband_name and
  /// gender_digit, and that is the whole of it. Mobile is NULLIF'd to null
  /// inside the RPC, door_no likewise, and the entire address INSERT sits
  /// behind `IF p_village_id IS NOT NULL` -- a customer with no address is a
  /// row the server is happy to write.
  ///
  /// The form was refusing registrations the database would have accepted.
  /// At a doorstep that means the customer does not get created, so the loan
  /// does not get issued, so the round moves on without them.
  ///
  /// The optional fields are still THERE and still validated when filled --
  /// a half-typed mobile or a five-digit PIN is still refused. They just no
  /// longer block a customer who has neither.
  bool get _canCreateNew =>
      _fullName.text.trim().length >= 2 &&
      _fatherHusband.text.trim().length >= 2 &&
      _gender != null &&
      // Filled or empty, never half-typed.
      (_mobile.text.trim().isEmpty || _mobile.text.trim().length == 10) &&
      (_aadhaar.text.trim().isEmpty || _aadhaar.text.trim().length == 12) &&
      // An address is all-or-nothing: the RPC writes person_addresses only
      // when it has both a village and a PIN, so half of one is not a state
      // worth allowing.
      ((_pinCode.text.trim().isEmpty && _villageId == null) ||
          (_pinCode.text.trim().length == 6 && _villageId != null));

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
                  style: ManaType.sheetTitle),
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
          style: ManaType.note,
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
            style: ManaType.noteBad,
          ),
        ],
      ];

  List<Widget> _foundStage() => [
        ManaText.raw(
          _results.length == 1
              ? ref.t('identity_found')
              : '${_results.length} matches — choose one',
          style: ManaType.strong,
        ),
        const SizedBox(height: ManaSpacing.sm),
        // One card per match, selectable. Father/husband name is shown
        // because it is frequently the only thing distinguishing two people
        // with the same name in the same village.
        for (final person in _results)
          Card(
            color: person.personId == _foundIdentity?.personId
                ? ManaColors.brandFaint
                : null,
            child: ListTile(
              leading: const ManaVerificationRing(isVerified: true, size: 40),
              title: ManaText.raw(person.fullName),
              subtitle: ManaText.raw(
                [person.mlid, if (person.fatherHusbandName.isNotEmpty) person.fatherHusbandName]
                    .join(' · '),
              ),
              trailing: person.personId == _foundIdentity?.personId
                  ? Icon(Icons.check_circle, color: ManaColors.statusGood)
                  : null,
              onTap: () => setState(() => _foundIdentity = person),
            ),
          ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: (_submitting || _foundIdentity == null) ? null : _linkExisting,
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
        ManaText.raw(ref.t('no_match_create_new_identity'), style: ManaType.strong),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('new_customer_present_note'),
          style: ManaType.note,
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
          // isExpanded: a DropdownButton sizes to its widest item and
          // overflows rather than shrinking -- measured at 1.0x on OW-002.
          isExpanded: true,
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
          decoration: InputDecoration(labelText: ref.t('mobile_number')),
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
          decoration: InputDecoration(labelText: ref.t('pin_code'), suffixIcon: ManaInfoHint(ref.t('pin_code_helper')),),
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
          decoration: InputDecoration(labelText: ref.t('door_house_no')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _villageSearch,
          decoration: InputDecoration(labelText: ref.t('search_village_town')),
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
                  title: ManaText.raw(label, style: ManaType.small),
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
                  // isExpanded: a DropdownButton sizes to its widest item and
                  // overflows rather than shrinking -- measured at 1.0x on OW-002.
                  isExpanded: true,
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
              style: ManaType.note),
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
        appBar: ManaAppBar(
          homeRoute: '/ow-004',
          title: customer.fullName,
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
              CustomerCollectionsTab(profile: profile),
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
                ManaText.raw(customer.fullName, style: ManaType.sheetTitle)),
        Center(child: ManaText.raw(customer.mlid, style: ManaType.secondary)),
        const SizedBox(height: ManaSpacing.lg),
        ManaLabelValueRow(label: ref.t('father_husband_name'), value: customer.fatherHusbandName),
        ManaLabelValueRow(label: ref.t('village'), value: customer.village),
        // Opens the dialer with the number in it; the Owner presses call.
        ManaLabelValueRow(
          label: ref.t('phone_number'),
          value: customer.phoneNumber,
          trailing: ManaCallButton(customer.phoneNumber),
        ),
        ManaLabelValueRow(label: ref.t('occupation'), value: profile.occupation ?? '—'),
        ManaLabelValueRow(label: ref.t('address'), value: profile.address ?? '—'),
        ManaLabelValueRow(label: ref.t('customer_since'), value: DateFormat('d MMM yyyy').format(profile.customerSince)),
        ManaLabelValueRow(label: ref.t('current_agent'), value: profile.currentAgent ?? '—'),
        ManaLabelValueRow(label: ref.t('current_status'), value: customer.membershipStatus),
        ManaLabelValueRow(label: ref.t('line_repayment_index'), value: '${customer.lineRepaymentIndex}'),
        ManaLabelValueRow(label: ref.t('loan_count'), value: '${customer.activeLoanCount}'),
        ManaLabelValueRow(label: ref.t('outstanding_balance'), value: manaRupees(customer.outstandingBalance)),
      ],
    );
  }


}

class _LoansTab extends ConsumerWidget {
  final CustomerProfile profile;
  const _LoansTab({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profile.loans.isEmpty) {
      return Center(
        child: ManaText.raw(ref.t('no_loans_yet_period'), style: ManaType.secondary),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: profile.loans
          .map((l) => Card(
                child: ListTile(
                  title: ManaText.raw(l.loanNumber, style: ManaType.emphasis),
                  subtitle: ManaText.raw(
                    ref
                        .t('issued_outstanding_note')
                        .replaceAll('{date}', DateFormat('d MMM yyyy').format(l.issueDate))
                        .replaceAll('{amount}', manaRupees(l.outstanding)),
                    style: const TextStyle(fontSize: 16),
                  ),
                  trailing: ManaTrailingStatus(
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

  // Disposed with the State that owns them -- see the sweep note elsewhere.
  @override
  void dispose() {
    _remark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            children: widget.profile.remarks.isEmpty
                ? [ManaText.raw(ref.t('no_remarks_yet'), style: ManaType.secondary)]
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
          style: ManaType.secondary,
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
          style: ManaType.secondary,
        ),
      ),
    );
  }
}
