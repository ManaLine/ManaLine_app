import 'ow_019_cheti_management.dart';
import 'ow_one_by_one_migration.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/icons.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_amount.dart';
import '../../../shared/network_error_handler.dart';
import '../state/business_management_state.dart';


/// Whether a mobile number entered on the pre-existing-business path may be
/// saved.
///
/// Blank is allowed HERE AND NOWHERE ELSE: `persons.mobile_number` is
/// nullable and `app.register_new_customer` NULLIFs an empty string, because
/// an old paper book routinely has no phone number for its older customers.
/// While the form demanded one, the only way to enter such a customer was to
/// invent a number, and an invented number collides with whoever really owns
/// it under `uq_persons_mobile_number`.
///
/// A PARTIAL number is still refused. Six digits is a typo, not a decision to
/// leave the field out, and letting it through would store a number that can
/// never be dialled.
bool migrationMobileAcceptable(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty || trimmed.length == 10;
}

/// OW-018 — Pre-Existing Business Migration.
///
/// For a business that was already running before it joined MANA LINE.
/// The Owner states the old book: what is out with customers, and what has
/// already come back.
///
/// BF (confirmed with the Owner 2026-07-31) is CASH IN HAND:
///   BF = investment principal − amount given out + already collected
/// The money still owed by customers is the Line Balance and sits OUTSIDE
/// BF, because BF everywhere else in this app means a figure that can be
/// physically counted (day-ledger opening, agent BF, Zero Difference).
///
/// Gated on `migration_locked = false` (GLOBAL BR-159). A business that has
/// already pressed Start Business can be reopened deliberately — Owner PIN
/// path, typed reason, audit row — mirroring Reopen Closed Day.
class BusinessMigrationScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BusinessMigrationScreen({super.key, required this.businessId});

  @override
  ConsumerState<BusinessMigrationScreen> createState() => _BusinessMigrationScreenState();
}

class _BusinessMigrationScreenState extends ConsumerState<BusinessMigrationScreen> {
  MigrationSummary? _summary;
  int? _investorPayableBalance;
  int? _businessProfit;
  DateTime? _figuresAsOf;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      final s = await api.fetchMigrationSummary(businessId: widget.businessId);
      // Independent of BF and Line Balance above — see the two RPCs' own
      // doc comments in the P3 migration for why these are separate figures.
      //
      // Stated AT THE CUT-OFF for a migrated book, never at today. Investor
      // interest keeps accruing after the cut-off, so today's payable is not
      // the number the Owner can check against a book that stops in March —
      // on sri satyanarayana it read Rs 38,70,308 against a book saying
      // Rs 24,85,582, and nothing on the screen said the dates differed.
      final snapshot = await api.fetchMigrationSnapshot(businessId: widget.businessId);
      final payable = await api.fetchInvestorPayableBalance(
          businessId: widget.businessId, asOf: snapshot?.cutoff);
      // Profit is the Owner's declared figure once a snapshot exists. What the
      // app derives is missing whatever the book knows and the tables do not
      // — the interest on loans that had already closed, most of all — and
      // that gap is already carried as profit_carry_forward.
      final profit = snapshot != null
          ? snapshot.declaredProfit
          : await api.fetchBusinessProfit(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _investorPayableBalance = payable;
        _businessProfit = profit;
        _figuresAsOf = snapshot?.cutoff;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openBulkOnboarding() async {
    // TWO DESTINATIONS, because THIS SCREEN RUNS ON BOTH BUILDS. OW-018 is in
    // kManaWebAllowedRoutes, so an Owner can be standing on it in a browser.
    //
    // Bringing a whole book across means downloading a spreadsheet, filling it
    // in and uploading it back, which has no comfortable home on a phone -- so
    // on the handset this leads to a signpost that points at the website.
    //
    // THAT SIGNPOST IS ANDROID-ONLY, deliberately: telling somebody to visit
    // the website they are already on would be absurd, so it is absent from
    // the web allowlist. Pushing it unconditionally therefore sent a web Owner
    // to the route-unavailable screen -- "This Screen Is in the App", offering
    // to install the app, from inside the app's own website, one click from
    // the wizard they were trying to reach. Reported from the live site.
    //
    // I introduced that when the signpost was added and did not check who else
    // built this screen. It is the exact failure CLAUDE.md opens its
    // "not breaking the thing next to the thing you fixed" section with.
    await context.push(
      kIsWeb ? '/ow-bulk-onboarding-menu' : '/ow-bulk-onboarding-web',
      extra: widget.businessId,
    );
    await _load();
  }

  /// The second door, BESIDE the wizard rather than instead of it.
  ///
  /// The wizard is seven pages of grids and a spreadsheet -- right for two
  /// hundred customers, wrong for three investors, and wrong for the one
  /// person the wizard missed, because finishing that entry means walking all
  /// seven pages again.
  ///
  /// Which door suits is decided PER STAGE, not per business. A real book has
  /// 200 customers, 2 agents and 3 investors: the wizard is the only sane way
  /// to do the customers, and building a spreadsheet for the other five people
  /// is not.
  Future<void> _openOneByOne() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OneByOneMigrationScreen(businessId: widget.businessId),
      ),
    );
    if (mounted) await _load();
  }

  /// A cheti that was already running when the book came across.
  ///
  /// This is a signpost, not a feature -- OW-019 already takes the opening
  /// position. It is here because the Owner migrating a book is on this
  /// screen, and a cheti left out is money going out every week that the app
  /// never sees.
  Future<void> _openChetis() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChetiManagementScreen(businessId: widget.businessId),
      ),
    );
  }

  /// The reasons a started business gets unlocked again.
  ///
  /// A free-text box on its own produced "correction" and "mistake", which
  /// audits to nothing -- and this reason is the ONLY record of why a locked
  /// migration was reopened. Each of these is something the migration actually
  /// captures: investors, agents, customers with their loans, BF and line
  /// balance.
  ///
  /// 'other' keeps the typed box. A list that cannot say "none of these"
  /// pushes people into picking the nearest wrong answer, which is worse for
  /// an audit trail than free text.
  static const _reopenReasonKeys = <String>[
    'reopen_reason_missed_entry',
    'reopen_reason_wrong_amount',
    'reopen_reason_investor_principal',
    'reopen_reason_agent',
    'reopen_reason_started_early',
    'reopen_reason_duplicate',
    'reopen_reason_other',
  ];

  Future<void> _reopen() async {
    final controller = TextEditingController();
    String? chosenKey;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          // Scrolls if it does not fit -- see ow_011_day_closure.dart.
          scrollable: true,
          title: ManaText.raw(ref.t('reopen_migration')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManaText.raw(
                ref.t('reopen_migration_note'),
                style: ManaType.note,
              ),
              const SizedBox(height: ManaSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: chosenKey,
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: ref.t('reopen_reason_label')),
                items: [
                  for (final key in _reopenReasonKeys)
                    DropdownMenuItem(
                      value: key,
                      // isExpanded above plus this: a Row with an unflexible
                      // child is the overflow shape, and these sentences are
                      // longer in Telugu than the box is wide.
                      child: ManaText.raw(ref.t(key),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setLocal(() => chosenKey = v),
              ),
              // Only for Other. Showing it always would put an empty box under
              // a chosen reason and invite somebody to answer twice.
              if (chosenKey == 'reopen_reason_other') ...[
                const SizedBox(height: ManaSpacing.md),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 2,
                  decoration:
                      InputDecoration(labelText: ref.t('reason_required_field')),
                  onChanged: (_) => setLocal(() {}),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: ManaText.raw(ref.t('cancel'))),
            FilledButton(
              // A chosen reason is enough; Other needs its text as well.
              onPressed: chosenKey == null ||
                      (chosenKey == 'reopen_reason_other' &&
                          controller.text.trim().isEmpty)
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        chosenKey == 'reopen_reason_other'
                            ? controller.text.trim()
                            // The ENGLISH sentence, not the key: the audit log
                            // is read by people, and a row saying
                            // 'reopen_reason_agent' tells them nothing.
                            : ref.t(chosenKey!),
                      ),
              child: ManaText.raw(ref.t('reopen')),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(businessManagementApiServiceProvider)
          .reopenMigration(businessId: widget.businessId, reason: reason);
      return true;
    });
    if (ok == true) await _load();
  }

  Future<void> _lock() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('finish_migration_question')),
        content: ManaText.raw(ref.t('finish_migration_note')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: ManaText.raw(ref.t('finish'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(businessManagementApiServiceProvider)
          .lockMigration(businessId: widget.businessId);
      return true;
    });
    if (ok == true) await _load();
  }

  /// The global search, with no role fixed.
  ///
  /// No `role=` query parameter on purpose: absent means "ask which role",
  /// and asking is the safe direction. A wrong role files an agent as a
  /// borrower; a needless question does not.
  Future<void> _addUser() async {
    await context.push('/ow-search', extra: widget.businessId);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('pre_existing_business')),
      // ADD A USER, not a customer.
      //
      // This button used to open the migrate-loan form directly, which named
      // the role before the Owner had chosen it: a book being brought across
      // has investors and agents in it too, and the only thing on this screen
      // offering to add anybody said "Customer". It goes to the global search
      // now, which finds the person first and then asks which of the three
      // they are -- the same route the + and the magnifier already take.
      //
      // THIS ORPHANS _MigrateLoanScreen (below, ~700 lines), which was the
      // only caller. Left in place rather than deleted in a renaming change:
      // it did something the new route does NOT, namely take a new person and
      // their loan in ONE form. Through the search that is two errands -- add
      // the person, then add their loan from the village book. Flagged for a
      // decision rather than removed quietly, because deleting it is a choice
      // about how an Owner works, not tidying.
      floatingActionButton: (s != null && !s.migrationLocked)
          ? FloatingActionButton.extended(
              onPressed: _addUser,
              icon: const Icon(Icons.person_add_alt_1),
              label: ManaText.raw(ref.t('add_a_user')),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorState(_error!)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      // Room for the FAB to float over. Without it the
                      // extended button sat on top of Finish Migration, which
                      // is the last thing an Owner needs to reach on this
                      // screen and the one they cannot scroll past.
                      padding: EdgeInsets.fromLTRB(
                        ManaSpacing.lg,
                        ManaSpacing.lg,
                        ManaSpacing.lg,
                        (s != null && !s.migrationLocked)
                            ? ManaSpacing.lg + 88
                            : ManaSpacing.lg,
                      ),
                      children: [
                        _statusCard(s!),
                        const SizedBox(height: ManaSpacing.lg),
                        _bfCard(s),
                        const SizedBox(height: ManaSpacing.lg),
                        _profitCard(),
                        const SizedBox(height: ManaSpacing.lg),
                        if (!s.migrationLocked) ...[
                          // The spreadsheet is the fallback, not the front
                          // door. Most Owners here have never used Excel,
                          // and a sheet also fails all-or-nothing — one bad
                          // row in a thousand rejects the lot. Entering
                          // people one at a time is slower per customer and
                          // far more likely to finish, so the one-at-a-time
                          // path is the button on the screen (the FAB) and
                          // this is demoted to a plain link beneath it.
                          ManaText.raw(
                            'Adding customers one at a time is the reliable way — each '
                            'one is saved on its own, so a mistake in the tenth never '
                            'undoes the first nine. The spreadsheet below is only worth '
                            'it if you already keep your book in Excel.',
                            style: ManaType.fine,
                          ),
                          const SizedBox(height: ManaSpacing.sm),
                          // Outlined, like the three buttons under it.
                          //
                          // It was a bare TextButton sitting between two
                          // OutlinedButtons, so the one control on this screen
                          // that opens a seven-page wizard read as less of a
                          // button than the ones that do smaller things. Being
                          // the second choice is what the sentence above it
                          // says; it does not also need to look unpressable.
                          OutlinedButton.icon(
                            onPressed: _openBulkOnboarding,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: ManaText.raw(ref.t('bulk_onboarding_wizard')),
                          ),
                          const SizedBox(height: ManaSpacing.sm),
                          OutlinedButton.icon(
                            onPressed: _openOneByOne,
                            icon: const Icon(Icons.person_outline),
                            label: ManaText.raw(ref.t('enter_one_by_one')),
                          ),
                          const SizedBox(height: ManaSpacing.lg),
                          // The chetis an Owner is already paying into.
                          //
                          // OW-019 has always been able to take one: chetis
                          // carries opening_instalments_paid,
                          // opening_amount_paid and availed_pre_migration, the
                          // create form collects all three, and
                          // app.record_cheti_payment ADDS the opening count to
                          // the payments recorded since, so stating a position
                          // and then collecting does not double count.
                          //
                          // What was missing is any reason to go there. An
                          // Owner bringing a book across is on THIS screen,
                          // and nothing on it mentions chetis -- so two
                          // running chetis quietly never arrive, and the first
                          // sign is a BF figure that does not match the till.
                          ManaText.raw(ref.t('pre_existing_cheti_note'),
                              style: ManaType.fine),
                          const SizedBox(height: ManaSpacing.sm),
                          OutlinedButton.icon(
                            onPressed: _openChetis,
                            icon: const Icon(ManaIcons.cheti),
                            label: ManaText.raw(
                                ref.t('chetis_you_are_already_paying')),
                          ),
                          const SizedBox(height: ManaSpacing.md),
                        ],
                        if (!s.migrationLocked)
                          OutlinedButton(
                            onPressed: _lock,
                            child: ManaText.raw(ref.t('finish_migration')),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _errorState(String message) => ListView(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        children: [
          Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
          const SizedBox(height: ManaSpacing.md),
          Center(child: ManaText.raw(ref.t('could_not_load_migration_status'))),
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(message,
              textAlign: TextAlign.center,
              style: ManaType.noteBad),
          const SizedBox(height: ManaSpacing.md),
          Center(child: ElevatedButton(onPressed: _load, child: ManaText.raw(ref.t('retry')))),
        ],
      );

  Widget _statusCard(MigrationSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ManaText.raw(ref.t(s.migrationLocked ? 'migration_closed' : 'migration_open'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ManaType.cardTitle),
                ),
                const SizedBox(width: ManaSpacing.xs),
                Flexible(
                    child: ManaStatusPill(
                  label: ref.t(s.migrationLocked ? 'locked' : 'open_status'),
                  status: s.migrationLocked ? ManaStatus.neutral : ManaStatus.good,
                )),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              s.migrationLocked
                  ? ref.t('migration_locked_note').replaceAll(
                      '{date}',
                      s.businessStartedAt == null
                          ? ref.t('an_earlier_date')
                          : DateFormat('d MMM yyyy').format(s.businessStartedAt!))
                  : ref.t('migration_open_note'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.md),
            if (s.migrationLocked)
              OutlinedButton(onPressed: _reopen, child: ManaText.raw(ref.t('reopen_migration'))),
            if (!s.migrationLocked)
              ManaText.raw(
                  ref.t('pre_existing_loans_entered_note').replaceAll('{count}', '${s.migratedLoanCount}'),
                  style: ManaType.small),
          ],
        ),
      ),
    );
  }

  /// Declaring BF is a one-way act — the server refuses it once migration is
  /// locked — so the sheet says so before the Owner commits.
  Future<void> _declareBf(MigrationSummary s) async {
    final controller = TextEditingController(
        text: s.openingBfDeclaredAmount != null ? '${s.openingBfDeclaredAmount}' : '');
    final entered = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Scrolls if it does not fit -- see ow_011_day_closure.dart.
        scrollable: true,
        title: ManaText.raw(ref.t('declare_opening_bf')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(
              ref.t('declare_opening_bf_note'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.md),
            // Whole rupees, and the keyboard says so. It offered a decimal
            // point before, and a decimal typed into it parsed to null through
            // int.tryParse below — the dialog closed having declared nothing,
            // with no error to explain why. Money columns are numeric(_,0);
            // paise cannot be stored.
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: InputDecoration(
                labelText: ref.t('cash_in_hand_field'),
                prefixText: '₹ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: ManaText.raw(ref.t('declare')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (entered == null || entered < 0) return;
    if (!mounted) return;

    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(businessManagementApiServiceProvider).setOpeningBf(
            businessId: widget.businessId,
            amount: entered,
          );
      return true;
    });
    if (ok == true) await _load();
  }

  Widget _bfCard(MigrationSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          children: [
            // The old card listed Investment principal / Given out /
            // Collected above a divider, as if those summed to BF. They never
            // did — BF is read independently — and for a business funded by
            // its own retained profit, investment principal is 0, so the
            // breakdown visibly contradicted the total.
            //
            // BF is now what the Owner declared after counting the cash box,
            // so the card states that figure and when it was stated.
            Row(
              children: [
                Expanded(
                  child: ManaText.raw(ref.t('bf_cash_in_hand'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ManaType.strong),
                ),
                const SizedBox(width: ManaSpacing.xs),
                Flexible(child: ManaAmount(s.bf, semanticLabel: ref.t('bf_semantic_label'))),
              ],
            ),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              s.hasDeclaredBf
                  ? ref.t('bf_declared_on_note').replaceAll(
                          '{date}', DateFormat('d MMM yyyy').format(s.openingBfDeclaredOn!)) +
                      (s.migrationLocked ? ref.t('bf_locked_suffix') : '')
                  : ref.t('bf_not_declared_note'),
              style: TextStyle(
                fontSize: 13,
                color: s.hasDeclaredBf
                    ? ManaColors.textSecondary
                    : ManaColors.statusBad,
              ),
            ),
            if (!s.migrationLocked) ...[
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => _declareBf(s),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: ManaText.raw(
                    ref.t(s.hasDeclaredBf ? 'change_opening_bf' : 'declare_opening_bf')),
              ),
            ],
            const Divider(),
            const SizedBox(height: ManaSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: ManaSpacing.sm, vertical: ManaSpacing.xs),
              decoration: BoxDecoration(
                color: ManaColors.brandFaint,
                borderRadius: BorderRadius.circular(ManaRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ManaText.raw(ref.t('line_balance_label'),
                        style: ManaType.note),
                  ),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(child: ManaAmount(s.lineBalance, size: ManaAmountSize.compact)),
                ],
              ),
            ),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              ref.t('line_balance_note'),
              style: ManaType.note,
            ),
          ],
        ),
      ),
    );
  }


  /// Two figures that are NOT BF and NOT Line Balance:
  ///   Investor Payable — what the business owes back to investors (principal
  ///   still standing plus interest not yet paid or compounded away).
  ///   Business Profit — interest+fee income minus expenses minus the
  ///   lifetime interest cost of investor capital.
  /// Kept as a separate card so neither is mistaken for cash in hand.
  Widget _profitCard() {
    final payable = _investorPayableBalance;
    final profit = _businessProfit;
    if (payable == null && profit == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('profit_and_investor_payable'), style: ManaType.strong),
            // Without the date these read as "now" and get compared against a
            // book that stopped months ago.
            if (_figuresAsOf != null)
              ManaText.raw(
                'As on ${_figuresAsOf!.day} '
                '${const [
                  'Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'
                ][_figuresAsOf!.month - 1]} ${_figuresAsOf!.year}',
                style: ManaType.fine,
              ),
            const SizedBox(height: ManaSpacing.sm),
            if (payable != null)
              Row(
                children: [
                  Expanded(child: ManaText.raw(ref.t('owed_back_to_investors'))),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(child: ManaAmount(payable, size: ManaAmountSize.compact)),
                ],
              ),
            if (profit != null) ...[
              const SizedBox(height: ManaSpacing.xs),
              Row(
                children: [
                  Expanded(child: ManaText.raw(ref.t('business_profit'))),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(
                    child: ManaAmount(profit,
                        size: ManaAmountSize.compact,
                        tone: profit < 0 ? ManaAmountTone.negative : ManaAmountTone.positive),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
