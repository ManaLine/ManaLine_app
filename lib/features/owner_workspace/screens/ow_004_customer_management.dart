import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
import '../../../shared/soft_delete_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../../../shared/document_viewer.dart';
import '../../../shared/customer_row.dart';
import '../../../shared/customer_collections_tab.dart';
import '../../../shared/mlti_upgrade_sheet.dart';
import '../../../shared/translation_service.dart';
import '../state/customer_state.dart';
import '../../../design/components/mana_call_button.dart';
import '../../../shared/widgets/village_search_field.dart';


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
        _openAddCustomer();
      }
    });
  }

  void _reload() => ref.read(customerListProvider.notifier).load(widget.businessId);

  /// Add a customer, and carry on to a loan when that is what was asked for.
  ///
  /// THE BUG THIS FIXES: the sheet ends with two buttons -- "Add & Issue Loan"
  /// and "Add Only" -- and signals which was pressed by what it pops:
  /// `Navigator.pop(thenLoan ? id : null)`. Both call sites on THIS screen
  /// discarded that value with `.then((_) => reload())`, so on the one screen
  /// whose whole job is customers, Add & Issue Loan added the customer and
  /// stopped. No loan screen, no error, nothing saying it had not happened.
  ///
  /// /customer-new forwarded it correctly, which is why the + in the header
  /// worked and this did not -- the same sheet behaving two different ways
  /// depending on which door opened it.
  Future<void> _openAddCustomer() async {
    final customerId = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ManaAddCustomerSheet(businessId: widget.businessId),
    );
    // Reload either way: a customer was added on both paths, and this list is
    // what the Owner comes back to.
    if (!mounted) return;
    _reload();
    if (customerId == null || !mounted) return;
    // Owner workspace issues loans from OW-005.
    context.push('/ow-005?customerId=$customerId', extra: widget.businessId);
  }

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

  /// ONE way to add a customer, at the Owner's instruction: search, and add.
  ///
  /// There were three, and all three already did search-and-add -- they
  /// differed only in which half they would refuse. "Existing Customers" was
  /// the same sheet locked against creating anybody; "Pre-Existing Customer"
  /// was OW-014, whose own name is Global Workflow (Pre-Existing Member
  /// Creation) and which searches by MLID or name and registers when there is
  /// no match. Three doors into one room, and the person adding a customer had
  /// to know which was which before they could start.
  ///
  /// The Owner's rule: somebody added while a book was being migrated stays as
  /// they are, but once the business is running in the app there is one path
  /// in. OW-018's migration form is untouched by this -- it keeps its own
  /// add-a-customer, because that is the migration, not the running business.
  ///
  /// The role is not asked for here. This screen's subject IS the customer,
  /// the same way the header's + reads its role from the screen it is drawn
  /// on; Universal Search asks, because a stranger found by phone number
  /// could be any of the three.
  List<MemberAction> _addActions() => [
        MemberAction(
          label: ref.t('add_customer'),
          icon: Icons.person_add_alt_1_outlined,
          onTap: _openAddCustomer,
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
            : Column(children: [
                // Counted off the roster already in hand -- an MLTI is what
                // the prefix says -- so this costs no query. It draws nothing
                // once every customer has a permanent ID.
                MltiUpgradeBanner(
                  count: state.customers
                      .where((c) => c.mlid.startsWith('MLTI'))
                      .length,
                  businessId: widget.businessId,
                ),
                Expanded(
            child: RefreshIndicator(
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
              ]),
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
/// What was typed into Add Customer, kept until it is used or thrown away.
///
/// THE FINDING, in the Owner's words: "i added a person and then mobile number
/// attached to other person error appeared, then pressed back entire form
/// which is filled gone and again on click add customer it shows new - but it
/// will be time waste so app needs to remember or show the last entered
/// details until discarded."
///
/// The sheet's State owns eight TextEditingControllers and dies when the sheet
/// pops, which is what a State is supposed to do -- so the fix is not to make
/// the widget live longer, it is to put the typing somewhere the widget is not.
///
/// IN MEMORY, AND NOT ON DISK, deliberately. This holds a mobile number and an
/// Aadhaar number. Persisting those to the handset would outlive the session,
/// the person and the reason -- a different decision from "do not retype what
/// you just typed", and not one a convenience feature gets to make. A draft
/// survives a back press and a wrong-number error; it does not survive the app
/// being closed.
///
/// PER BUSINESS, because the Owner of two books adding somebody to each should
/// not find one book's half-typed customer in the other's form.
class ManaAddCustomerDraft {
  static final Map<String, ManaAddCustomerDraft> _byBusiness = {};

  String fullName = '';
  String fatherHusband = '';
  String mobile = '';
  String aadhaar = '';
  String doorNo = '';
  String? gender;
  String? villageId;
  String? villagePinCode;
  String? villageLabel;

  /// Nothing has been typed. The difference between Discard and Close.
  bool get isEmpty =>
      fullName.trim().isEmpty &&
      fatherHusband.trim().isEmpty &&
      mobile.trim().isEmpty &&
      aadhaar.trim().isEmpty &&
      doorNo.trim().isEmpty &&
      gender == null &&
      villageId == null;

  static ManaAddCustomerDraft of(String businessId) =>
      _byBusiness.putIfAbsent(businessId, ManaAddCustomerDraft.new);

  static void clear(String businessId) => _byBusiness.remove(businessId);
}

class ManaAddCustomerSheet extends ConsumerStatefulWidget {
  final String businessId;
  /// Opened from the "Existing Customers" header action — a miss stays on
  /// the search stage instead of falling through to Create New.
  final bool existingOnly;

  /// What was already typed wherever the sheet was opened from, so a search
  /// that found nobody is not retyped to create that person. Used by OW-001's
  /// global search, which otherwise dead-ends on "No Identity Found".
  final String? initialQuery;

  /// Called the moment a person exists, with both ids, BEFORE the sheet pops.
  ///
  /// ADDITIVE ON PURPOSE. The sheet signals which button was pressed by what
  /// it pops -- the customerId for "Add & Issue Loan", null for "Add Only" --
  /// and null is also what cancelling gives. That ambiguity is fine for the
  /// four callers that only want to know whether to open a loan screen, and
  /// useless for a caller that needs to do something to the person regardless
  /// of which button ended the sheet.
  ///
  /// Changing the pop to carry a richer result would have rewritten the
  /// contract that /customer-new forwards as its own route result, and every
  /// caller with it. This adds a way to hear about the person without
  /// disturbing any of that.
  final void Function(String customerId, int personId, String mlid)?
      onCreated;

  /// True when this sheet is bringing a customer across from a paper book.
  ///
  /// A customer copied out of an existing ledger may have neither a phone nor
  /// an Aadhaar number. Everywhere else one of the two is required, and the
  /// requirement is enforced by app.register_new_customer rather than here,
  /// because the RPC is the only place that can also check the Owner and that
  /// the business's migration is still open.
  ///
  /// Defaults false, so OW-001 and OW-004 -- where a customer is being
  /// registered in person and can be asked for a number -- keep the stricter
  /// rule without naming it.
  final bool migrationEntry;

  const ManaAddCustomerSheet({
    super.key,
    required this.businessId,
    this.existingOnly = false,
    this.initialQuery,
    this.onCreated,
    this.migrationEntry = false,
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
    // The draft is copied out FIRST, because the controllers below are about
    // to be thrown away. dispose runs on a back press, on a drag-dismiss and
    // after a successful create alike -- and the success path clears the
    // draft before popping, so this finds nothing to put back there.
    _saveDraft();
    _query.dispose();
    _fullName.dispose();
    _fatherHusband.dispose();
    _mobile.dispose();
    _aadhaar.dispose();
    _doorNo.dispose();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVillages());
    _restoreDraft();
  }

  ManaAddCustomerDraft get _draft => ManaAddCustomerDraft.of(widget.businessId);

  /// A customer was created from this sheet, so there is nothing to remember.
  /// Read by [_saveDraft], which dispose calls after the pop.
  bool _created = false;

  /// Put back what was typed last time, and open on the form when there IS
  /// something to put back -- landing on the search stage over a half-filled
  /// Create New form would hide the thing being restored.
  void _restoreDraft() {
    final d = _draft;
    if (d.isEmpty) return;
    if (d.fullName.isNotEmpty) _fullName.text = d.fullName;
    _fatherHusband.text = d.fatherHusband;
    _mobile.text = d.mobile;
    _aadhaar.text = d.aadhaar;
    _doorNo.text = d.doorNo;
    _gender = d.gender;
    _villageId = d.villageId;
    _villagePinCode = d.villagePinCode;
    _selectedVillageLabel = d.villageLabel;
    _stage = _AddCustomerStage.createNew;
  }

  /// Copy the fields out before this State dies.
  ///
  /// Called from dispose, which runs on a back press, on a drag-dismiss and on
  /// a successful create alike -- so the successful path clears the draft
  /// first, and this finds nothing to save.
  void _saveDraft() {
    if (_created) return;
    final d = _draft;
    d.fullName = _fullName.text;
    d.fatherHusband = _fatherHusband.text;
    d.mobile = _mobile.text;
    d.aadhaar = _aadhaar.text;
    d.doorNo = _doorNo.text;
    d.gender = _gender;
    d.villageId = _villageId;
    d.villagePinCode = _villagePinCode;
    d.villageLabel = _selectedVillageLabel;
  }

  /// ITEM 13: the word depends on whether there is anything to lose.
  ///
  /// "Discard" over an untouched form is a threat about nothing, and it makes
  /// somebody stop and read a button that should have just closed. Enabled in
  /// both states -- it is the way out either way -- but the word changes.
  void _discardOrClose() {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _fullName.clear();
      _fatherHusband.clear();
      _mobile.clear();
      _aadhaar.clear();
      _doorNo.clear();
      _gender = null;
      _villageId = null;
      _villagePinCode = null;
      _selectedVillageLabel = null;
      _villageFieldKey = UniqueKey();
    });
    ManaAddCustomerDraft.clear(widget.businessId);
  }

  /// Anything typed, in the form or in the draft behind it.
  bool get _isDirty =>
      _fullName.text.trim().isNotEmpty ||
      _fatherHusband.text.trim().isNotEmpty ||
      _mobile.text.trim().isNotEmpty ||
      _aadhaar.text.trim().isNotEmpty ||
      _doorNo.text.trim().isNotEmpty ||
      _gender != null ||
      _villageId != null;

  /// ITEM 6: does this book work anywhere yet?
  ///
  /// A customer's address is a village, and a village only counts if it is in
  /// one of the business's operating areas -- that is what decides whose
  /// round they fall into and whether an agent ever reaches their door. This
  /// screen never asked. An Owner on a brand new book could fill seven fields
  /// and only then discover there was nowhere to put the person.
  ///
  /// Asked once, on open, and the answer drives two things: the gate below,
  /// and the shortlist of villages offered above the national search.
  List<ManaVillage>? _businessVillages;

  Future<void> _loadVillages() async {
    final villages = await NetworkErrorHandler.run(
      context,
      () => ref.read(locationApiServiceProvider).businessVillages(widget.businessId),
    );
    if (!mounted || villages == null) return;
    setState(() => _businessVillages = villages);
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
  String? _gender;
  bool _submitting = false;
  String? _villageId;
  // Submitted pin_code comes from the picked village's directory row, not a
  // screen-typed box — ManaVillageSearchField owns PIN entry now (its PIN
  // mode embeds ManaVillagePickerField, which renders the PIN field).
  String? _villagePinCode;
  String? _selectedVillageLabel;
  // Re-keyed after a GPS fix so the search field starts fresh with the new
  // PIN rather than keep a search typed against wherever it was before.
  Key _villageFieldKey = UniqueKey();

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
      // NOTHING IS SELECTED BY A SEARCH. This chose the match when there was
      // exactly one, which put a filled tick and an enabled "Add & Issue Loan"
      // on screen for a person the Owner had not yet looked at -- so the
      // screen had made the decision and was showing the confirmation. With a
      // village of repeated names the one row a query returns is not
      // necessarily the right person; it is the only person who matched the
      // letters typed.
      //
      // The result is shown either way. What changes is that linking somebody
      // to a business now needs a tap that means "this one", which is also the
      // moment the father's name and village on the card get read.
      //
      // The duplicate-warning path below keeps its own behaviour: there the
      // question is "are you about to make a second record of this person",
      // and highlighting who it means is the point of the warning.
      _foundIdentity = null;
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

  /// A picked reference row has no `location_id` until it is resolved — same
  /// contract [ManaVillagePickerField] documents: it does not write anything,
  /// so a caller that needs the id resolves it. Idempotent through
  /// `add_location_if_missing`, so two Agents choosing the same village on the
  /// same morning end up pointing at one row rather than two.
  Future<void> _onVillagePicked(ManaVillage? v) async {
    if (v == null) {
      setState(() {
        _villageId = null;
        _selectedVillageLabel = null;
        _villagePinCode = null;
      });
      return;
    }
    var id = v.locationId;
    if (id.isEmpty) {
      final result = await NetworkErrorHandler.run(
          context, () => ref.read(locationApiServiceProvider).resolveId(v));
      if (result == null || !mounted) return; // network failure — already reported
      id = result;
    }
    if (!mounted) return;
    final label = [v.name, v.mandal, v.district, v.state]
        .where((s) => s.trim().isNotEmpty)
        .join(' — ');
    setState(() {
      _villageId = id;
      _selectedVillageLabel = label;
      if (v.pinCode.isNotEmpty) _villagePinCode = v.pinCode;
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
  // An address used to be all-or-nothing here (a typed PIN without a picked
  // village, or vice versa, was refused). That half-typed state cannot occur
  // any more: the PIN comes from the picked village's own directory row
  // (_villagePinCode, set in _onVillagePicked), so a village pick and a
  // valid PIN arrive together or not at all. What replaces the old
  // all-or-nothing check is simpler: a village must be picked at all.
  // createNewReturningId's villageId parameter is non-nullable
  // (customer_state.dart), and _createNew below force-unwraps _villageId —
  // without this check that unwrap crashes on every customer added before a
  // village is chosen, which is the normal in-progress state of this form.
  /// The SAME rule as before, said out loud.
  ///
  /// It was a bool, so the form knew perfectly well which of six conditions
  /// had failed and had no way to tell anybody. Returning the sentence
  /// instead is the whole fix: the checks are unchanged, in the same order,
  /// and the button that used to grey out now names the field.
  ///
  /// ORDERED THE WAY THE FORM IS READ, top to bottom, so the first thing it
  /// names is the first thing missing rather than the last rule written.
  String? _whatIsMissing() {
    if (_fullName.text.trim().length < 2) return ref.t('full_name_required');
    if (_fatherHusband.text.trim().length < 2) {
      return ref.t('father_husband_name_required');
    }
    if (_gender == null) return ref.t('gender_required');
    if (_villageId == null) return ref.t('village_required');
    // Filled or empty, never half-typed.
    if (_mobile.text.trim().isNotEmpty && _mobile.text.trim().length != 10) {
      return ref.t('mobile_must_be_ten_digits');
    }
    if (_aadhaar.text.trim().isNotEmpty && _aadhaar.text.trim().length != 12) {
      return ref.t('aadhaar_must_be_twelve_digits');
    }
    // The rule _createNew already enforced, moved up here so it is answered
    // by the same sentence as everything else rather than by a snackbar that
    // only appears after the button is believed to work.
    if (!widget.migrationEntry &&
        _mobile.text.trim().isEmpty &&
        _aadhaar.text.trim().isEmpty) {
      return ref.t('customer_needs_phone_or_aadhaar');
    }
    return null;
  }

  /// True when Create New was stopped because somebody already on file looks
  /// like the same person. The matches are in [_results].
  bool _duplicateBlocked = false;

  /// The one duplicate the database cannot refuse on its own.
  ///
  /// persons.mobile_number is UNIQUE, so two people cannot share one -- a
  /// second registration on the same number is 23505 and already reaches the
  /// Owner as "that mobile number is already registered". But the column is
  /// NULLABLE, and Postgres allows unlimited NULLs in a unique column, while
  /// _canCreateNew permits an empty mobile. So two people with the same name,
  /// the same father's name, the same gender and the same village and no
  /// phone between them are two separate persons rows, one MLID each, and
  /// nothing anywhere objects. That is a duplicate customer, and the only
  /// remaining way to add somebody now runs straight through it: a search
  /// that finds nobody falls through to Create New.
  ///
  /// So the check is exactly where the constraint is not: WITHOUT a mobile
  /// number, a name plus father's name that already exists blocks the create
  /// and shows who it matched. WITH one, the database is already the
  /// authority and this stays out of the way -- which also means an Owner
  /// registering a genuine namesake is never stuck, because typing the phone
  /// number that distinguishes them is the way through.
  ///
  /// Not a database constraint on (name, father, village): namesakes in one
  /// village are real -- this file says so twice about picking the wrong
  /// person -- so the right answer is to make the Owner look, not to make the
  /// row impossible.
  /// The PIN the geocoder last read back, seeded into the village search.
  /// Null until "Use My Location" succeeds; cleared with the rest on a new fix.
  String? _geocodedPin;

  Future<bool> _wouldDuplicate() async {
    if (_mobile.text.trim().isNotEmpty) return false;

    final matches = await NetworkErrorHandler.run(context, () async {
      return ref
          .read(customerListProvider.notifier)
          .searchIdentity(fullName: _fullName.text.trim());
    });
    // A failed lookup is NOT a clean bill of health. Refuse to create rather
    // than create blind: the error is already on screen, and the Owner can
    // press the button again.
    if (matches == null || !mounted) return true;

    final father = _fatherHusband.text.trim().toLowerCase();
    final likely = matches
        .where((p) => p.fatherHusbandName.trim().toLowerCase() == father)
        .toList();
    if (likely.isEmpty) return false;

    setState(() {
      _results = likely;
      _foundIdentity = likely.length == 1 ? likely.first : null;
      _duplicateBlocked = true;
      _stage = _AddCustomerStage.found;
    });
    return true;
  }

  /// Tells the caller who was just created, if it asked to be told.
  ///
  /// The person_id is read back from the row rather than guessed:
  /// app.register_new_customer returns the customer_id alone, and the two ids
  /// are not interchangeable. One small select on a path that runs once per
  /// new person.
  Future<void> _announceCreated(String customerId) async {
    final cb = widget.onCreated;
    if (cb == null) return;
    try {
      final who = await ref
          .read(customerListProvider.notifier)
          .personForCustomer(customerId);
      if (who != null) cb(customerId, who.$1, who.$2);
    } catch (_) {
      // Never block the add on the announcement. The customer exists either
      // way; the caller simply does not get told, which is the state every
      // other caller is in.
    }
  }

  Future<void> _createNew({bool thenLoan = false}) async {
    // Checked HERE as well as in the RPC, because the two say it differently.
    // The RPC's refusal is the backstop and arrives as a thrown error; this is
    // the sentence the Owner reads, before the round trip, while the fields
    // are still in front of them.
    //
    // The form presents Mobile Number without an asterisk, which was true when
    // neither field was required and is now true only for a migration entry.
    if (!widget.migrationEntry &&
        _mobile.text.trim().isEmpty &&
        _aadhaar.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: ManaText.raw(ref.t('customer_needs_phone_or_aadhaar')),
      ));
      return;
    }
    setState(() => _submitting = true);
    if (await _wouldDuplicate()) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    if (!mounted) return;
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
            pinCode: _villagePinCode,
            villageId: _villageId!,
            migrationEntry: widget.migrationEntry,
          );
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (id == null || !mounted) return;
    // The person exists now, so the typing that made them is spent.
    //
    // A FLAG, NOT A CLEAR, and the difference is a bug I wrote and the test
    // suite caught. Clearing here does nothing: dispose runs afterwards,
    // _saveDraft calls ManaAddCustomerDraft.of() which re-creates the entry,
    // and it saves the controllers -- which still hold everything, because
    // _createNew pops rather than blanking the form. The next Add Customer
    // would have opened pre-filled with the customer just added.
    _created = true;
    ManaAddCustomerDraft.clear(widget.businessId);
    await _announceCreated(id);
    if (!mounted) return;
    // "Add Only" used to add the person and close, silently. The sheet
    // vanishing is the same thing the sheet does when it is dismissed, so from
    // the far side of the screen the button had done nothing -- and the person
    // it just created was somewhere off-screen in a list.
    //
    // Only on this branch: "Add & Issue Loan" carries straight into the loan
    // wizard, where the next screen IS the confirmation and a snackbar would
    // be talking over it.
    if (!thenLoan) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: ManaText.raw(ref.t('added_to_this_business')),
      ));
    }
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
                // THE WAY OUT SITS BESIDE THE TITLE, and its word depends on
                // whether there is anything to lose. "Discard" over an
                // untouched form is a threat about nothing; "Close" over a
                // filled one would throw away work without saying so.
                Row(
                  children: [
                    Expanded(
                      child: ManaText.raw(
                          ref.t(widget.existingOnly
                              ? 'existing_customers'
                              : 'add_customer'),
                          style: ManaType.sheetTitle),
                    ),
                    TextButton(
                      onPressed: _discardOrClose,
                      child: ManaText.raw(
                          _isDirty ? ref.t('discard') : ref.t('close')),
                    ),
                  ],
                ),
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
        if (_duplicateBlocked) ...[
          // Says what happened and what to do about it. "Already exists" with
          // no way forward is how an Owner standing in front of a real new
          // customer gets stuck.
          ManaText.raw(ref.t('duplicate_person_note'), style: ManaType.noteBad),
          const SizedBox(height: ManaSpacing.sm),
        ],
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
              leading: ManaVerificationRing(
                isVerified: person.isVerified ?? false,
                ringColor:
                    person.isVerified == null ? ManaColors.textSecondary : null,
                size: 40,
              ),
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
          blockedReason: () =>
              _foundIdentity == null ? ref.t('pick_a_person_first') : null,
          onAddOnly: () => _linkExisting(),
          onAddAndLend: () => _linkExisting(thenLoan: true),
        ),
        // NOT THIS PERSON. Reaching a list of matches and recognising none of
        // them used to leave only "Search Again" -- which searches for the
        // person the Owner has just decided is not on it. Somebody standing at
        // a door with a customer who is genuinely new needs the other door,
        // and it was two screens away.
        //
        // Hidden when the sheet was opened from "Existing Customers", where
        // creating a new identity is not what was asked for.
        if (!widget.existingOnly)
          TextButton.icon(
            onPressed: () => setState(() {
              _duplicateBlocked = false;
              _stage = _AddCustomerStage.createNew;
            }),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: ManaText.raw(ref.t('add_a_customer')),
          ),
        TextButton(
          onPressed: () => setState(() {
            _duplicateBlocked = false;
            _stage = _AddCustomerStage.search;
          }),
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
        // WHERE, BEFORE WHO. The Owner's instruction was "first ask to select
        // village ... this reduces duplicates registration of user and
        // villages both", and the mechanism is the ORDER rather than any new
        // control. The villages this book already works were always offered
        // above the national register -- but they sat below the name, the
        // gender and the door number, so anybody filling the form top to
        // bottom met a blank search first and typed a village that already
        // existed under a slightly different spelling. "Panagal" and
        // "Panagallu (Rural)" are one place, entered twice, for that reason.
        //
        // Nothing is forbidden here. A genuinely new village still has to be
        // addable, and a picker that refuses is one people work around. What
        // changed is which choice is in front of somebody first.
        const SizedBox(height: ManaSpacing.md),
        // Fills PIN and village from where the Owner is standing — which,
        // for this sheet, is the customer's doorstep. It does NOT capture
        // the coordinates: createNew already takes its own fix at save
        // time, and taking a second one here would record whichever was
        // earlier rather than where the address was actually confirmed.
        UseMyLocationButton(
          onCaptured: (place) {
            setState(() {
              // The geocoder's name is NOT typed into the village box. It used
              // to be, and what it usually returns at a doorstep is the colony
              // -- "Aphb Colony" -- which is not in the directory under any
              // PIN, so a typed name could never match.
              //
              // THE GEOCODED PIN IS NOW CARRIED IN. This said the search
              // field "has no hook to accept a prefilled PIN"; it has taken an
              // `initialPin` since before this was reported, and nobody came
              // back to use it. So the button cleared the village fields,
              // filled nothing, and showed a snackbar -- which from the far
              // side of the screen is a button that does not fetch anything.
              //
              // It fills the PIN and stops there, deliberately: a PIN alone
              // does not search. The village still needs three letters typed
              // (village_search_rule_test guards that rule), because one PIN
              // can carry fifty villages and the geocoder's own name at a
              // doorstep is usually the colony, which is in no directory.
              _villageId = null;
              _selectedVillageLabel = null;
              _villagePinCode = null;
              _geocodedPin = place.pinCode;
              _villageFieldKey = UniqueKey();
            });
          },
        ),
        TextField(
          controller: _doorNo,
          decoration: InputDecoration(labelText: ref.t('door_house_no')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.md),
        // THE VILLAGES THIS BOOK ACTUALLY WORKS, offered before the national
        // register. A business works a dozen villages out of 768,529, and the
        // person being added almost always lives in one of them -- so the
        // common case is a tap rather than a PIN plus three letters.
        //
        // With the PIN beside each name, which is what was asked for: two
        // villages of the same name in one district is ordinary, and the PIN
        // is what separates them.
        if (_businessVillages != null && _businessVillages!.isNotEmpty) ...[
          ManaText.raw(ref.t('villages_this_business_works'),
              style: ManaType.note),
          const SizedBox(height: ManaSpacing.xs),
          Wrap(
            spacing: ManaSpacing.xs,
            runSpacing: ManaSpacing.xs,
            children: [
              for (final v in _businessVillages!)
                ChoiceChip(
                  selected: _villageId == v.locationId,
                  label: ManaText.raw(
                      v.pinCode.isEmpty ? v.name : '${v.name} (${v.pinCode})'),
                  onSelected: (_) => _onVillagePicked(v),
                ),
            ],
          ),
          const SizedBox(height: ManaSpacing.sm),
        ],
        ManaVillageSearchField(
          key: _villageFieldKey,
          label: ref.t('search_village_town'),
          initialPin: _geocodedPin,
          onPicked: _onVillagePicked,
        ),
        // ADD A VILLAGE FROM HERE, because this is where somebody discovers
        // they need one. It goes to Operating Areas rather than creating a
        // location inline: a village is not a customer's field, it is a
        // decision about where this book works, and it belongs with the other
        // ones.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push('/ow-012?tab=areas',
                extra: widget.businessId),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: ManaText.raw(ref.t('add_new_village')),
          ),
        ),
        if (_selectedVillageLabel != null) ...[
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(ref.t('selected_note').replaceAll('{label}', _selectedVillageLabel!),
              style: ManaType.note),
        ],

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
        const SizedBox(height: ManaSpacing.lg),
        _AddEndings(
          submitting: _submitting,
          blockedReason: _whatIsMissing,
          migrationEntry: widget.migrationEntry,
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
  final VoidCallback onAddOnly;
  final VoidCallback onAddAndLend;

  /// Changes what the first button is OFFERING, not just what it says.
  ///
  /// "Add & Issue Loan" is right at a doorstep: money is about to leave the
  /// till. On the pre-existing-business door no money moves -- the loan
  /// already exists, was issued months ago by whoever kept the paper book, and
  /// is only being written down. Calling that "Issue" invites an Owner to
  /// think a disbursement happened today, which is the one thing that must not
  /// be ambiguous on a money path.
  ///
  /// add_existing_loan and add_existing_loan_note were both already in
  /// ui_translations, written and never wired to anything.
  final bool migrationEntry;

  /// What is missing, in the Owner's words, or null when nothing is.
  ///
  /// THE WHOLE POINT OF THIS PARAMETER. These two buttons used to be disabled
  /// whenever the form was incomplete, and a disabled button at a doorstep is
  /// indistinguishable from a broken one -- more so here, because the
  /// secondary button kept its full brand-blue border in the disabled state
  /// (fixed in theme.dart this pass, app-wide). Reported from a handset:
  /// "add & issue loan & add only - both on tap not working, not showing any
  /// error why it's not happening. either it should work or it should show
  /// any error."
  ///
  /// So they are always pressable and they always answer.
  final String? Function() blockedReason;

  const _AddEndings({
    required this.submitting,
    required this.blockedReason,
    required this.onAddOnly,
    required this.onAddAndLend,
    this.migrationEntry = false,
  });

  /// Act, or say why not. Never nothing.
  void _press(BuildContext context, VoidCallback action) {
    final why = blockedReason();
    if (why == null) {
      action();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: ManaText.raw(why)));
  }

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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (migrationEntry) ...[
          ManaText.raw(ref.t('add_existing_loan_note'), style: ManaType.note),
          const SizedBox(height: ManaSpacing.sm),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _press(context, onAddAndLend),
            child: ManaText.raw(ref
                .t(migrationEntry ? 'add_existing_loan' : 'add_and_issue_loan')),
          ),
        ),
        const SizedBox(height: ManaSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _press(context, onAddOnly),
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
              _LoansTab(
                profile: profile,
                businessId: businessId,
                customerId: customer.customerId,
              ),
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
        Center(
          child: ManaVerificationRing(
            isVerified: customer.isVerified ?? false,
            ringColor:
                customer.isVerified == null ? ManaColors.textSecondary : null,
            size: 72,
          ),
        ),
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
        ManaLabelValueRow(label: ref.t('outstanding_balance'), amount: customer.outstandingBalance),
      ],
    );
  }


}

class _LoansTab extends ConsumerWidget {
  final CustomerProfile profile;
  final String businessId;
  final String customerId;
  const _LoansTab({
    required this.profile,
    required this.businessId,
    required this.customerId,
  });

  /// AN EMPTY TAB THAT OFFERS NOTHING IS A DEAD END.
  ///
  /// This said "No loans yet." and stopped. True, and useless: a customer with
  /// no loan is the single most likely person to be about to get one, and the
  /// Owner had to leave the profile, find the loan wizard, and search for the
  /// same person again in a list of fifty-six. Reported from the handset after
  /// looking up Kiran Rao through global search and finding no way forward.
  ///
  /// Same shape as OW-012's Account Periods tab, which this codebase already
  /// fixed once for the same reason -- a screen that states a fact and offers
  /// no way to change it is a screen that has stopped being an app.
  ///
  /// The action is offered in BOTH states. With loans on the list it is the
  /// second loan somebody is here to add; with none it is the first. Only the
  /// prominence differs.
  void _issueLoan(BuildContext context) => context.push(
        '/ow-005?customerId=$customerId',
        extra: businessId,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profile.loans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManaText.raw(ref.t('no_loans_yet_period'), style: ManaType.secondary),
              const SizedBox(height: ManaSpacing.lg),
              FilledButton.icon(
                onPressed: () => _issueLoan(context),
                icon: const Icon(Icons.add, size: 18),
                label: ManaText.raw(ref.t('new_loan')),
              ),
            ],
          ),
        ),
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
          .cast<Widget>()
          .toList()
        // Below the list, not above it: the loans already on the book are what
        // somebody opened this tab to read, and a create button above them
        // pushes the reading down the screen to serve the rarer errand.
        ..add(Padding(
          padding: const EdgeInsets.only(top: ManaSpacing.sm),
          child: OutlinedButton.icon(
            onPressed: () => _issueLoan(context),
            icon: const Icon(Icons.add, size: 18),
            label: ManaText.raw(ref.t('new_loan')),
          ),
        )),
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

  /// Forwarded from /customer-new?migration=1 — see ManaAddCustomerSheet.
  final bool migrationEntry;

  const ManaAddCustomerScreen({
    super.key,
    required this.businessId,
    this.migrationEntry = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('add_a_customer'), homeRoute: '/ow-004'),
      body: SafeArea(
        child: ManaAddCustomerSheet(
          businessId: businessId,
          migrationEntry: migrationEntry,
        ),
      ),
    );
  }
}
