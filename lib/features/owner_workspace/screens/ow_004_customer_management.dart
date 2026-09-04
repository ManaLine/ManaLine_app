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
import '../../../design/components/mana_filter_rail.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_member_roster.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/location_api_service.dart';
import '../../../shared/widgets/workspace_nav.dart';
import '../../../shared/widgets/use_my_location_button.dart';
import '../../../shared/mana_location.dart';
import '../../../shared/soft_delete_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../../../shared/document_viewer.dart';
import '../../../shared/customer_row.dart';
import '../../../shared/customer_collections_tab.dart';
import '../../../shared/translation_service.dart';
import '../state/customer_state.dart';
import '../../../design/components/mana_info_hint.dart';
import '../../../design/components/mana_call_button.dart';
import '../../../shared/widgets/add_village_sheet.dart';


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
          builder: (_) => ManaAddCustomerSheet(businessId: widget.businessId),
        ).then((_) => ref.read(customerListProvider.notifier).load(widget.businessId));
      }
    });
  }

  void _reload() => ref.read(customerListProvider.notifier).load(widget.businessId);

  /// Asks, then removes. Returns whether the row should actually go.
  ///
  /// The server is still the authority — it re-checks the loans and refuses —
  /// so a failure here puts the row back rather than leaving the list saying
  /// something the database does not.
  Future<bool> _confirmRemove(CustomerSummary c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: ManaText.raw(ref.t('remove_customer_question')),
        content: ManaText.raw(
            ref.t('remove_customer_note').replaceAll('{name}', c.fullName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: ManaText.raw(ref.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: ManaText.raw(ref.t('remove'),
                style: TextStyle(color: ManaColors.statusBad)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(customerApiServiceProvider)
          .removeCustomer(c.membershipId!);
      return true;
    });
    if (ok == true) _reload();
    return ok == true;
  }

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
            builder: (_) => ManaAddCustomerSheet(businessId: widget.businessId),
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
            builder: (_) => ManaAddCustomerSheet(businessId: widget.businessId, existingOnly: true),
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
      // Index 2 is Customers, which is this screen.
      bottomNavigationBar: ManaWorkspaceNav(
          workspace: ManaWorkspace.owner,
          businessId: widget.businessId,
          currentIndex: 2),
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
        // No search action here any more, and no notifications either: the
        // header carries the same three on every Owner screen now, installed
        // once. This screen's own search opened Universal Search -- the same
        // destination -- so keeping it would have drawn the magnifier twice
        // side by side.

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
                // Order, village, sort by, status -- the same rail the round
                // uses, so the two screens filter the same book through the
                // same control.
                ManaFilterRail(
                  filters: [
                    _OrderChip(state: state),
                    _VillageFilterDropdown(state: state),
                    _SortDropdown(state: state),
                    _StatusFilterDropdown(state: state),
                  ],
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
                  // Swipe left to remove — but only somebody who owes nothing.
                  // The row of a customer with a live loan does not move at
                  // all, rather than sliding open and then refusing: a gesture
                  // that starts and gets taken back reads as the app being
                  // broken, not as a rule being enforced.
                  //
                  // The rule itself is server-side in
                  // app.remove_customer_membership. This predicate only
                  // decides whether to offer the gesture.
                  removeLabel: ref.t('remove'),
                  canRemove: (entry) {
                    final c = state.filtered
                        .firstWhere((x) => x.customerId == entry.id);
                    return c.activeLoanCount == 0 && c.membershipId != null;
                  },
                  onRemove: (entry) => _confirmRemove(
                      state.filtered.firstWhere((x) => x.customerId == entry.id)),
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
/// Which way the chosen order runs.
///
/// New control. The list has always sorted one way per mode, so an Owner
/// wanting the smallest balances -- the ones close to closing -- had to read
/// to the bottom of the roster.
class _OrderChip extends ConsumerWidget {
  final CustomerListState state;
  const _OrderChip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaFilterChip<bool>(
      label: ref.t('sort_order'),
      value: state.ascending,
      active: !state.ascending,
      options: [
        ManaFilterOption(true, ref.t('lowest_first')),
        ManaFilterOption(false, ref.t('highest_first')),
      ],
      onChanged: (v) => ref.read(customerListProvider.notifier).setAscending(v),
    );
  }
}

class _SortDropdown extends ConsumerWidget {
  final CustomerListState state;
  const _SortDropdown({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaFilterChip<CustomerSort>(
      label: ref.t('sorted_by'),
      value: state.sort,
      active: state.sort != CustomerSort.village,
      options: [
        ManaFilterOption(CustomerSort.village, ref.t('village')),
        ManaFilterOption(CustomerSort.outstanding, ref.t('outstanding')),
        ManaFilterOption(CustomerSort.todaysDue, ref.t('todays_due')),
        ManaFilterOption(CustomerSort.name, ref.t('name_field')),
      ],
      onChanged: (v) => ref.read(customerListProvider.notifier).setSort(v),
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
    return ManaFilterChip<String?>(
      label: ref.t('status'),
      value: state.customerStatusFilter,
      active: state.customerStatusFilter != null,
      options: [
        ManaFilterOption(null, ref.t('all')),
        for (final v in const ['Active', 'Suspended'])
          ManaFilterOption(v, ref.t(v.toLowerCase())),
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
    // A chip rather than a dropdown in a fixed slot. The old control had to
    // ellipsize its own value to fit a quarter of the header -- and village is
    // the one filter whose value is a name that varies in length, so
    // "Srikalahasti — Uranduru Colony" was the thing being cut.
    return ManaFilterChip<String?>(
      label: ref.t('village'),
      value: state.villageFilter,
      active: state.villageFilter != null,
      options: [
        ManaFilterOption(
            null, '${ref.t('all_villages')} · ${state.customers.length}'),
        for (final v in villages) ManaFilterOption(v, '$v · ${counts[v]}'),
      ],
      onChanged: (v) => ref.read(customerListProvider.notifier).setVillageFilter(v),
    );
  }
}

// --- C4 Create Customer sub-flow ---------------------------------------

/// Adding somebody to this business, and deciding what happens next.
///
/// Pops with null when the caller should stop there, and with the new
/// customer's id when the person choosing asked to go straight on to a loan.
/// Public because three places need it and each had been going its own way:
/// OW-004's own FAB, the header's + on every Owner and Agent screen, and
/// AG-004, whose Create Customer was a snackbar reading "TODO: wire shared
/// sheet".
class ManaAddCustomerSheet extends ConsumerStatefulWidget {
  final String businessId;
  /// Opened from the "Existing Customers" header action — a miss stays on
  /// the search stage instead of falling through to Create New.
  final bool existingOnly;

  /// What was already typed wherever the sheet was opened from, so a search
  /// that found nobody is not retyped to create that person. Used by OW-001's
  /// global search, which otherwise dead-ends on "No Identity Found".
  final String? initialQuery;

  const ManaAddCustomerSheet({
    super.key,
    required this.businessId,
    this.existingOnly = false,
    this.initialQuery,
  });

  @override
  ConsumerState<ManaAddCustomerSheet> createState() => _AddCustomerSheetState();
}

enum _AddCustomerStage { search, found, createNew }

class _AddCustomerSheetState extends ConsumerState<ManaAddCustomerSheet> {

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
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    // Carried from wherever the sheet was opened, so the person who has
    // already typed a name into a search that found nobody does not type it
    // again to create them.
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _query.text = q;
      _fullName.text = q;
    }
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

  /// What the PIN code directory says exists at each PIN, cached per PIN.
  ///
  /// A PIN averages about 45 villages, so this is one query and then instant
  /// typing. It also feeds the mandal/district/state pickers below: those
  /// facts are already in the reference, and asking somebody at a doorstep to
  /// retype them is asking for a wrong address nobody reviews.
  final Map<String, List<Map<String, dynamic>>> _lgdByPin = {};

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

  Future<void> _linkExisting({bool thenLoan = false}) async {
    if (_foundIdentity == null || _foundIdentity!.personId == null) return;
    setState(() => _submitting = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).linkExisting(widget.businessId, _foundIdentity!.personId!);
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok != true || !mounted) return;

    // Linking does not hand back a customer_id, and the loan wizard needs
    // one. Looked up by the person just linked rather than by name: a
    // village where several people share one is exactly where guessing goes
    // wrong.
    String? customerId;
    if (thenLoan) {
      customerId = await NetworkErrorHandler.run<String?>(context, () async {
        return ref.read(customerListProvider.notifier).customerIdForPerson(
            widget.businessId, int.parse(_foundIdentity!.personId!));
      });
    }
    if (mounted) Navigator.of(context).pop(customerId);
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
    // A single character is too little to narrow anything, but NOTHING typed
    // is not: a PIN on its own already names a short list of villages, and
    // showing it is the whole answer to "which village am I in". This used to
    // demand two characters before it would show anything, so capturing a
    // location filled the PIN and then displayed an empty box.
    final needle = query.trim();
    if (needle.length == 1) {
      setState(() {
        _villageResults = [];
        _villageSearchAttempted = false;
      });
      return;
    }
    try {
      // Villages already in use by somebody. With nothing typed this is every
      // village the business already works at this PIN.
      var known = Supabase.instance.client
          .from('locations')
          .select('location_id, village_town_name, mandal, district, state, pin_code')
          .eq('status', 'Active')
          .eq('pin_code', pin);
      if (needle.isNotEmpty) {
        known = known.ilike('village_town_name', '%$needle%');
      }
      final rows = await known.limit(10);
      final existing = (rows as List).cast<Map<String, dynamic>>();

      // …and what the LGD reference says exists at this PIN, whether or not
      // anybody has used it yet.
      //
      // Without this the search could only ever find villages the business
      // had already typed in once. GPS prefills the box with a name the
      // reference knows and `locations` does not -- "Aphb Colony" -- which
      // matched nothing, so the only way forward on screen was Add New
      // Village. That is how "Panagal, Tirupati, Andhrapradesh" came to sit
      // beside the reference's own "Panagallu (Rural), Chittoor, Andhra
      // Pradesh": not a typo, a dead end.
      final lowered = needle.toLowerCase();
      final suggestions = await _referenceFor(pin);

      final seen = <String>{
        for (final e in existing)
          (e['village_town_name'] as String).toLowerCase(),
      };
      final offered = <Map<String, dynamic>>[...existing];
      for (final sug in suggestions) {
        // A PIN tops out at 358 villages in the reference. Long enough to
        // scroll past, so the untyped list is capped and typing narrows it.
        if (offered.length >= 25) break;
        // 'village', not 'village_town_name'. app.suggest_villages returns
        // TABLE(village, mandal, district, state); this read the name it has
        // in `locations` instead, so every suggestion came back empty and was
        // skipped. The directory was queried on every keystroke and its answer
        // thrown away -- which is why a real village never appeared and the
        // only way forward on screen was Add New Village.
        final name = (sug['village'] ?? '').toString();
        if (name.isEmpty) continue;
        // An empty needle matches everything, which is the point: a PIN on
        // its own is a short list worth showing.
        if (!name.toLowerCase().contains(lowered)) continue;
        // The reference carries the same village under both the old and new
        // district names, so a PIN answers twice for every village in it.
        if (!seen.add(name.toLowerCase())) continue;
        offered.add({
          // No location_id: this one does not exist yet. Picking it writes
          // it, with the reference's own mandal, district and state rather
          // than whatever somebody would have typed.
          'location_id': null,
          'village_town_name': name,
          'mandal': sug['mandal'],
          'district': sug['district'],
          'state': sug['state'],
          'pin_code': pin,
        });
      }

      if (!mounted) return;
      setState(() {
        _villageResults = offered;
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

  /// What a captured location actually means for the village field.
  ///
  /// Always offers the PIN's villages. If the geocoder's town name is one of
  /// them it is selected outright — that is the case worth saving a tap on —
  /// and if it is not, the list stands and nothing wrong has been typed
  /// anywhere.
  Future<void> _resolveVillageFromPlace(ManaPlace place) async {
    await _searchVillages('');
    final guess = place.village?.trim().toLowerCase();
    if (guess == null || guess.isEmpty || !mounted) return;

    final match = _villageResults.where(
        (v) => (v['village_town_name'] ?? '').toString().toLowerCase() == guess);
    if (match.isEmpty) return;

    final v = match.first;
    await _chooseVillage(v, _villageLabel(v));
  }

  /// The one label format for an offered village, so the search list and an
  /// auto-selection cannot describe the same place differently.
  String _villageLabel(Map<String, dynamic> v) =>
      '${v['village_town_name']} — ${v['mandal']}, ${v['district']}, ${v['state']}';

  /// The directory's rows for a PIN, fetched once.
  Future<List<Map<String, dynamic>>> _referenceFor(String pin) async {
    final cached = _lgdByPin[pin];
    if (cached != null) return cached;
    final rows =
        await ref.read(locationApiServiceProvider).suggestFromReference(pin);
    _lgdByPin[pin] = rows;
    return rows;
  }

  /// Picking one of the offered villages.
  ///
  /// An existing one is just an id. A reference one has none until somebody
  /// uses it, so this writes it first -- through add_location_if_missing,
  /// which is idempotent, so two Agents choosing the same village on the same
  /// morning end up pointing at one row rather than two.
  Future<void> _chooseVillage(Map<String, dynamic> v, String label) async {
    var id = v['location_id'] as String?;
    if (id == null) {
      final created = await NetworkErrorHandler.run(context, () async {
        final village = await ref.read(locationApiServiceProvider).addIfMissing(
              pinCode: (v['pin_code'] ?? '').toString(),
              villageTownName: (v['village_town_name'] ?? '').toString(),
              areaType: 'Village',
              mandal: (v['mandal'] ?? '').toString(),
              district: (v['district'] ?? '').toString(),
              state: (v['state'] ?? '').toString(),
            );
        return village.locationId;
      });
      if (created == null) return; // network failure — already reported
      id = created;
    }
    if (!mounted) return;
    setState(() {
      _villageId = id;
      _selectedVillageLabel = label;
      _villageSearch.text = (v['village_town_name'] ?? '').toString();
      _villageResults = [];
    });
  }

  /// Opens the shared Add New Village sheet.
  ///
  /// This was the MOST evolved of the seven copies: it already offered mandal
  /// and district from the PIN through ManaReferenceField rather than as free
  /// text. What it could not do is ask whether a near-matching village was
  /// meant before creating a second row for one place -- `ichapuram` and
  /// `Ichchapuram` are one town and score 0.83.
  ///
  /// So this loses nothing and gains the duplicate check, and the local
  /// implementation goes with it: _referenceOptions, _applyReferenceDefaults,
  /// _loadManualReference and five controllers existed only to serve this form.
  ///
  /// The PIN comes from the SEARCH field rather than a second manual one: two
  /// pin boxes on one form is two answers to one question.
  Future<void> _openAddVillage() async {
    final picked = await manaShowAddVillageSheet(
      context,
      ref,
      pinCode: _pinCode.text.trim(),
      initialName: _villageSearch.text.trim(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _villageId = picked.locationId;
      _selectedVillageLabel = [picked.name, picked.mandal, picked.district, picked.state]
          .where((v) => v.trim().isNotEmpty)
          .join(' — ');
      _villageSearch.text = picked.name;
      _villageResults = [];
    });
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

  Future<void> _createNew({bool thenLoan = false}) async {
    setState(() => _submitting = true);
    // createNewReturningId either way: the id costs nothing to receive and
    // is the difference between offering a loan next and asking the person
    // to find their own customer again.
    final id = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).createNewReturningId(
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
    if (id == null || !mounted) return;
    Navigator.of(context).pop(thenLoan ? id : null);
  }

  @override
  Widget build(BuildContext context) {
    // A plain scrolling sheet, NOT a DraggableScrollableSheet.
    //
    // It was draggable with initialChildSize 0.7 and no minChildSize, so the
    // default 0.25 applied: dragging down shrank the panel to a quarter of the
    // screen and left it there, form cut off mid-field, instead of dismissing.
    // On the handset that reads as a blocker sliding up and down over the
    // screen. showModalBottomSheet already handles drag-to-dismiss for the
    // whole sheet, which is the gesture people were reaching for.
    //
    // Capped at 90% of the height that is left once the keyboard has taken
    // its share, so a long form scrolls inside the sheet rather than growing
    // under the keyboard.
    final maxHeight = (MediaQuery.of(context).size.height -
            MediaQuery.of(context).viewInsets.bottom) *
        0.9;
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: ListView(
              shrinkWrap: true,
              children: [
                ManaText.raw(
                    ref.t(widget.existingOnly ? 'existing_customers' : 'add_customer'),
                    style: ManaType.sheetTitle),
                const SizedBox(height: ManaSpacing.lg),
                if (_stage == _AddCustomerStage.search) ..._searchStage(),
                if (_stage == _AddCustomerStage.found) ..._foundStage(),
                if (_stage == _AddCustomerStage.createNew) ..._createNewStage(),
              ],
            ),
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
              // Village included, and FIRST after the name it qualifies: with
              // "2 matches — choose one" the Owner was picking between two men
              // called Naresh on an MLID and a father's name, and linking the
              // wrong person to a business is not a mistake that announces
              // itself. Omitted entirely when there is no address on file, so
              // a missing one never renders as a real place.
              subtitle: ManaText.raw(
                [
                  if (person.village.isNotEmpty) person.village,
                  person.mlid,
                  if (person.fatherHusbandName.isNotEmpty) person.fatherHusbandName,
                ].join(' · '),
              ),
              trailing: person.personId == _foundIdentity?.personId
                  ? Icon(Icons.check_circle, color: ManaColors.statusGood)
                  : null,
              onTap: () => setState(() => _foundIdentity = person),
            ),
          ),
        const SizedBox(height: ManaSpacing.lg),
        // Two endings, because adding somebody and lending to them are two
        // decisions and the second one usually follows immediately. Making
        // it one button meant finding the customer again on another screen.
        _AddEndings(
          submitting: _submitting,
          enabled: _foundIdentity != null,
          onAddOnly: () => _linkExisting(),
          onAddAndLend: () => _linkExisting(thenLoan: true),
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
              // The geocoder's name is NOT typed into the village box. It used
              // to be, and what it usually returns at a doorstep is the colony
              // -- "Aphb Colony" -- which is not in the directory under any
              // PIN, so the box filled itself with a term that could never
              // match and the only offer left was Add New Village.
              //
              // The PIN is the reliable half. It is filled, the box is
              // cleared, and the PIN's own list of villages is offered to pick
              // from; _resolveVillageFromPlace then selects one outright if
              // the geocoder's name turns out to be one of them.
              _villageSearch.clear();
              _villageId = null;
              _selectedVillageLabel = null;
            });
            if (_pinCode.text.trim().length == 6) _resolveVillageFromPlace(place);
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
                final label = _villageLabel(v);
                final inUse = v['location_id'] != null;
                return ListTile(
                  dense: true,
                  title: ManaText.raw(label, style: ManaType.small),
                  // A village nobody has used yet is still a real place. It
                  // is offered the same way and marked, so choosing it is
                  // obviously safe rather than obviously new.
                  subtitle: inUse
                      ? null
                      : ManaText.raw(ref.t('from_the_pin_code_directory'),
                          style: ManaType.note),
                  onTap: () => _chooseVillage(v, label),
                );
              },
            ),
          ),
        if (_villageSearchAttempted && _villageResults.isEmpty && _villageId == null)
          Padding(
            padding: const EdgeInsets.only(top: ManaSpacing.xs),
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: _openAddVillage,
              child: ManaText.raw(ref.t('village_not_found_add_it').replaceAll('{query}', _villageSearch.text.trim())),
            ),
          ),
        if (_selectedVillageLabel != null) ...[
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(ref.t('selected_note').replaceAll('{label}', _selectedVillageLabel!),
              style: ManaType.note),
        ],
        const SizedBox(height: ManaSpacing.lg),
        _AddEndings(
          submitting: _submitting,
          enabled: _canCreateNew,
          onAddOnly: () => _createNew(),
          onAddAndLend: () => _createNew(thenLoan: true),
        ),
      ];
}

/// Add them, or add them and lend to them.
///
/// One button meant an Agent standing with somebody new had to add them,
/// leave, find them again in a list of fifty-six, and start the loan from
/// there. The second decision follows the first closely enough that the
/// screen should carry it.
class _AddEndings extends ConsumerWidget {
  final bool submitting;
  final bool enabled;
  final VoidCallback onAddOnly;
  final VoidCallback onAddAndLend;

  const _AddEndings({
    required this.submitting,
    required this.enabled,
    required this.onAddOnly,
    required this.onAddAndLend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (submitting) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(ManaSpacing.md),
          child: SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    // Stacked, not side by side: both labels are sentences in five
    // languages, and a Row of two would put each on three lines at 2.0x.
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: enabled ? onAddAndLend : null,
            child: ManaText.raw(ref.t('add_and_issue_loan')),
          ),
        ),
        const SizedBox(height: ManaSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: enabled ? onAddOnly : null,
            child: ManaText.raw(ref.t('add_only')),
          ),
        ),
      ],
    );
  }
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
        // The round, not a focused row: this menu knows a customer, and the
        // round focuses a LOAN. It used to pass the customer id as the loan
        // id, which matched nothing and quietly opened the plain round -- so
        // this is what it already did, said honestly. A customer with two
        // live loans has no single row to open anyway; the round's search
        // finds them by name.
        context.push('/ow-006', extra: businessId);
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
                  // Grace overrides the status shown here.
                  //
                  // loans.loan_status never says 'Grace Period' -- nothing
                  // writes it -- so a loan carrying granted grace read
                  // "Active" in this list while the loan detail, its pill and
                  // the round's tag all said otherwise.
                  trailing: ManaTrailingStatus(
                    label: l.inGrace ? ref.t('grace_period') : l.status,
                    status: l.inGrace
                        ? ManaStatus.warn
                        : l.status == 'Active'
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

/// The add-customer flow as a screen, for the header's + .
///
/// The sheet itself is unchanged — this only gives it somewhere to live that
/// a route can point at, so shared/ can open it by path instead of importing
/// a workspace screen. It hands back whatever the sheet popped with: null to
/// stop, or a customerId to carry on to a loan.
class ManaAddCustomerScreen extends ConsumerWidget {
  final String businessId;
  const ManaAddCustomerScreen({super.key, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('add_a_customer'), homeRoute: '/ow-004'),
      body: SafeArea(child: ManaAddCustomerSheet(businessId: businessId)),
    );
  }
}
