import '../state/account_sheet_rows.dart';
import '../../../design/components/mana_account_sheet.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_fit_text.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/soft_delete_service.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../state/record_book_state.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

/// OW-009 — Daily Record Book. One row per Business Day (`day_ledger`),
/// including still-Open days. Selecting a row opens an inline "View Day
/// Details" drill-down (Collections/Loans/Expenses/Deposits/Withdrawals/
/// Adjustments/Audit/Timeline), per OW-009_Daily_Record_Book.md.
///
/// NOT the same screen as OW-010 Report Hub — OW-010 shows one row per
/// CLOSED business-day-account with From/To ranges and monthly rollups;
/// this screen shows every raw Business Day, Open or Closed, one date each.
class DailyRecordBookScreen extends ConsumerStatefulWidget {
  final String businessId;
  const DailyRecordBookScreen({super.key, required this.businessId});

  @override
  ConsumerState<DailyRecordBookScreen> createState() => _DailyRecordBookScreenState();
}

class _DailyRecordBookScreenState extends ConsumerState<DailyRecordBookScreen> {
  /// Tap the date beside BF to jump to another day's account.
  ///
  /// THE CALENDAR OFFERS ONLY THE DAYS THE BOOK HOLDS -- "only show dates
  /// that are actively submitted account dates". state.activeDates is the
  /// same answer the list was filtered by, fetched for the whole book rather
  /// than for the loaded window, so jumping never shrinks the calendar.
  ///
  /// PICKING RELOADS FROM THAT DAY rather than scrolling to it. "tap on date
  /// ... to select date that shows that days account" -- so the chosen day
  /// becomes the top of the list and swiping up still walks backwards from
  /// there, which is the same gesture that worked a moment ago. Scrolling to
  /// an index would need every account's height in advance, and they vary
  /// with how many optional rows the Owner has added.
  Future<void> _pickDate(BuildContext context) async {
    final state = ref.read(recordBookProvider);
    if (state.activeDates.isEmpty) return;
    final sorted = state.activeDates.toList()..sort();
    final earliest = DateTime.parse(sorted.first);
    final latest = DateTime.parse(sorted.last);
    final current = state.rows.isEmpty ? latest : state.rows.first.businessDate;
    final picked = await showDatePicker(
      context: context,
      // The window's own top day may sit outside [earliest, latest] only if
      // activeDates and rows disagree, which they cannot -- both come from
      // one call. Clamped anyway: showDatePicker asserts rather than copes.
      initialDate: current.isBefore(earliest)
          ? earliest
          : (current.isAfter(latest) ? latest : current),
      firstDate: earliest,
      lastDate: latest,
      selectableDayPredicate: (d) => state.activeDates.contains(manaIsoDate(d)),
    );
    if (picked == null || !mounted) return;
    await ref.read(recordBookProvider.notifier).load(
          widget.businessId,
          dateTo: picked,
          status: state.statusFilter,
        );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recordBookProvider.notifier).load(widget.businessId);
      _restoreShown();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordBookProvider);

    return Scaffold(
      appBar: ManaAppBar(
        homeRoute: '/ow-001',
        title: ref.t('daily_record_book'),
        actions: [
          PopupMenuButton<String?>(
            tooltip: ref.t('filter_by_status'),
            onSelected: (status) => ref
                .read(recordBookProvider.notifier)
                .load(widget.businessId, status: status),
            itemBuilder: (_) => [
              PopupMenuItem(value: null, child: ManaText.raw(ref.t('all'))),
              PopupMenuItem(value: 'Open', child: ManaText.raw(ref.t('open'))),
              PopupMenuItem(value: 'Closed', child: ManaText.raw(ref.t('closed'))),
            ],
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(
            tooltip: ref.t('recent_deletes'),
            icon: const Icon(Icons.restore_from_trash),
            onPressed: () => context.push('/recent-deletes?businessId=${widget.businessId}'),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref
              .read(recordBookProvider.notifier)
              .load(widget.businessId, status: state.statusFilter),
          child: state.loading && state.rows.isEmpty
              // Ledger rows carry ~10 figures each, so the placeholders are
              // tall to match — a short skeleton would jump when data lands.
              ? const ManaSkeletonList(itemHeight: 220)
              : state.rows.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                          child: Center(
                            child: ManaText.raw(ref.t('no_accounts_yet'),
                                style: ManaType.secondary),
                          ),
                        ),
                      ],
                    )
                  : Column(children: [
                      // ADD ROW LIVES IN THE BODY, not the header.
                      //
                      // It went in the app bar first and pushed it 34 pixels
                      // over at 2.0x in Telugu -- the bar already carries a
                      // back button, a title, a filter, restore, the bell, the
                      // + and search, and a sixth action is one too many at
                      // any large text size. The layout tests caught it; the
                      // handset would have.
                      //
                      // Here it also sits where it is understood: directly
                      // above the sheets it changes, and it is the only thing
                      // on screen saying the optional rows exist.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(ManaSpacing.lg,
                              ManaSpacing.sm, ManaSpacing.lg, 0),
                          child: TextButton.icon(
                            onPressed: () => _chooseRows(context),
                            icon: const Icon(Icons.playlist_add, size: 18),
                            label: ManaText.raw(ref.t('add_row')),
                          ),
                        ),
                      ),
                      // AN ORDINARY LIST, LATEST FIRST.
                      //
                      // This was a vertical PageView for about an hour --
                      // one account per page, swipe up to turn it -- and the
                      // layout tests caught what that costs. A page tall
                      // enough to need its own scroll view (any day carrying
                      // an investor deposit, a cheti and a penalty note) puts
                      // two scrollables on the same axis, and Flutter does
                      // not hand the gesture up when the inner one reaches
                      // its end. Measured: the pager stayed at offset 0
                      // through three consecutive flings. The previous day
                      // was not merely awkward to reach -- it was
                      // unreachable, on exactly the days that matter most.
                      //
                      // A plain list is what the Owner actually asked for:
                      // "show latest account on top and on swipe up show
                      // previous one." rows arrive newest-first, so the
                      // latest account IS on top and swiping up reveals the
                      // one before it. The paging was mine, not theirs.
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(ManaSpacing.lg),
                          itemCount: state.rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: ManaSpacing.md),
                          itemBuilder: (context, i) => _LedgerRowCard(
                            row: state.rows[i],
                            income: state.loanIncome[
                                manaIsoDate(state.rows[i].businessDate)],
                            shown: _shown,
                            onLongPress: () =>
                                _openDayDetails(context, state.rows[i]),
                            onDateTap: () => _pickDate(context),
                          ),
                        ),
                      ),
                    ]),
        ),
      ),
    );
  }

  /// The optional lines the Owner has added, remembered between visits.
  ///
  /// PER BUSINESS. Two books are run differently -- one takes chetis, one
  /// does not -- and carrying one book's sheet into the other would be the
  /// app telling somebody what their business does.
  ///
  /// flutter_secure_storage rather than a new preferences dependency: the
  /// same call appearance_state.dart makes and already justifies, and the
  /// same one the camera lens uses. Heavier than this needs, already present,
  /// and not worth another build-compatibility risk on AGP 9 for one set of
  /// enum names.
  Set<ManaSheetLine> _shown = {};
  static const _shownKey = 'mana_sheet_rows_';
  static const _shownStore = FlutterSecureStorage();

  Future<void> _restoreShown() async {
    try {
      final saved =
          await _shownStore.read(key: _shownKey + widget.businessId);
      if (saved == null || !mounted) return;
      final names = saved.split(',').where((e) => e.isNotEmpty).toSet();
      setState(() {
        _shown = ManaSheetLine.values
            .where((l) => !l.isFixed && names.contains(l.name))
            .toSet();
      });
    } catch (_) {
      // A preference that could not be read is a sheet with fewer optional
      // rows on it. It must never be a screen that does not load.
    }
  }

  Future<void> _rememberShown() async {
    try {
      await _shownStore.write(
        key: _shownKey + widget.businessId,
        value: _shown.map((e) => e.name).join(','),
      );
    } catch (_) {
      // Costs a re-add next time, never the sheet in front of them.
    }
  }

  /// Choose which optional rows appear.
  ///
  /// THE THREE FIXED ONES ARE NOT IN THE LIST. They cannot be removed -- the
  /// Owner's instruction -- so offering them with a tick that does nothing
  /// would be a control that lies.
  ///
  /// A row that is carrying money is drawn whether or not it is ticked here;
  /// see manaAccountSheetRows. What this chooses is what appears when the
  /// figure is ZERO, plus the two lines that re-express Karchu.
  Future<void> _chooseRows(BuildContext context) async {
    final working = {..._shown};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: ManaText.raw(ref.t('rows_to_show'),
                    style: ManaType.sheetTitle),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final line in ManaSheetLine.values
                        .where((l) => !l.isFixed))
                      CheckboxListTile(
                        value: working.contains(line),
                        title: ManaText.raw(ref.t(_lineKey(line))),
                        onChanged: (v) => setSheetState(() {
                          if (v == true) {
                            working.add(line);
                          } else {
                            working.remove(line);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _shown = working);
    await _rememberShown();
  }

  Future<void> _openDayDetails(BuildContext context, DayLedgerRow row) async {
    await ref.read(recordBookProvider.notifier).openDayDetails(widget.businessId, row.businessDate);
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DayDetailsSheet(businessId: widget.businessId, row: row),
    );
    ref.read(recordBookProvider.notifier).closeDayDetails();
  }
}

class _LedgerRowCard extends ConsumerWidget {
  final DayLedgerRow row;

  /// What this day's loans were made of, or null when the decomposition was
  /// not fetched.
  ///
  /// NULL IS NOT ZERO. Null means the sheet does not KNOW the split, so it
  /// falls back to the ledger's own net figure for Karchu and offers neither
  /// Vaddi nor the fee. Drawing them as zero would tell an Owner a day earned
  /// no interest, which is a different statement from not having asked.
  final ManaDayLoanIncome? income;

  /// Which optional lines the Owner has asked to see.
  final Set<ManaSheetLine> shown;

  /// LONG PRESS, NOT TAP, opens the day's entries -- the Owner's instruction:
  /// "on long tap show the summary as it shows now". Tap belongs to the date
  /// now, and a card that opened a sheet on any tap would swallow it.
  final VoidCallback onLongPress;

  /// Tap the date to jump to another day.
  final VoidCallback onDateTap;

  const _LedgerRowCard({
    required this.row,
    required this.income,
    required this.shown,
    required this.onLongPress,
    required this.onDateTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      color: ManaColors.surfaceMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // THE DATE IS THE CONTROL. "tap on date (beside BF) opens
                  // calendar to select date that shows that days account."
                  // The icon is there because a bare date does not look like
                  // a button, and this is the only way back to a day that is
                  // twenty swipes down.
                  //
                  // Flexible inside the Row inside the Expanded: the date is
                  // the thing that may need to give way, and the 16dp icon
                  // beside it must not be the fixed-width child that makes
                  // this the project's sixth overflow.
                  Expanded(
                    child: InkWell(
                      onTap: onDateTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: ManaText.raw(
                              _dateFmt.format(row.businessDate),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.heavy,
                            ),
                          ),
                          const SizedBox(width: ManaSpacing.xs),
                          Icon(Icons.calendar_month_outlined,
                              size: 16, color: ManaColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(
                    child: ManaStatusPill(
                      label: row.status,
                      status: row.isClosed ? ManaStatus.neutral : ManaStatus.good,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ManaSpacing.sm),
              // THE SHEET, not thirteen figures in a wrap.
              //
              // The wrap had no axis: Opening BF, Collections, Loan Dist. and
              // Expenses sat side by side with nothing saying which of them
              // was money IN. Reported from a handset as "it looks messey",
              // and the Owner sent the sheet their business has used all
              // along -- credits left, debits right, each side totalled, the
              // difference carried into tomorrow.
              ManaAccountSheet(
                creditsLabel: ref.t('credits'),
                debitsLabel: ref.t('debits'),
                closing: row.closingBalance,
                closingNote: ref.t('next_bf'),
                rows: manaAccountSheetRows(
                  ledger: row,
                  // The fallback: face = the ledger's net, no interest, no
                  // fee. manaAccountSheetRows then computes Karchu as
                  // face - 0 - 0, which is the net -- exactly what the old
                  // screen showed.
                  income: income ??
                      ManaDayLoanIncome(
                        face: row.totalLoanDistribution,
                        interest: 0,
                        fee: 0,
                        net: row.totalLoanDistribution,
                      ),
                  shown: income == null
                      ? shown.difference(
                          {ManaSheetLine.vaddi, ManaSheetLine.processingFee})
                      : shown,
                  label: (line) => ref.t(_lineKey(line)),
                ),
              ),
              // PENALTY AS A NOTE, NOT A ROW. It is already inside Vasool --
              // it arrived as part of ordinary collections -- and this sheet
              // adds its columns up, so a penalty line in Credits would
              // overstate the day by exactly the penalties collected. The old
              // wrap could keep that straight in a comment because nothing
              // summed it.
              if (row.penaltyCollected > 0) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(
                    ref.t('of_which_penalty').replaceAll(
                        '{amount}', manaRupees(row.penaltyCollected)),
                    style: ManaType.note),
              ],
              if (row.remarks != null && row.remarks!.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(row.remarks!,
                    style: ManaType.note),
              ],
            ],
          ),
        ),
      ),
    );
  }

}

/// VIEW DAY DETAILS — Collections/Loans/Expenses/Deposits/Withdrawals/
/// Adjustments/Audit/Timeline, all filtered to one Business Date.
class _DayDetailsSheet extends ConsumerStatefulWidget {
  final String businessId;
  final DayLedgerRow row;
  const _DayDetailsSheet({required this.businessId, required this.row});

  @override
  ConsumerState<_DayDetailsSheet> createState() => _DayDetailsSheetState();
}

class _DayDetailsSheetState extends ConsumerState<_DayDetailsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 8, vsync: this);
  final _remarksController = TextEditingController();

  @override
  void dispose() {
    _tabs.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordBookProvider);
    final detail = state.dayDetail;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.only(top: ManaSpacing.md),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ManaText.raw(
                        _dateFmt.format(widget.row.businessDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: ManaSpacing.xs),
                    Flexible(
                      child: ManaStatusPill(
                        label: widget.row.status,
                        status: widget.row.isClosed ? ManaStatus.neutral : ManaStatus.good,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.row.isClosed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg, vertical: ManaSpacing.xs),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ManaText.raw(
                      ref.t('read_only_day_closed_note'),
                      style: ManaType.note,
                    ),
                  ),
                ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: [
                  Tab(text: ref.t('collections')),
                  Tab(text: ref.t('loans')),
                  Tab(text: ref.t('expenses')),
                  Tab(text: ref.t('deposits')),
                  Tab(text: ref.t('withdrawals')),
                  Tab(text: ref.t('adjustments')),
                  Tab(text: ref.t('audit')),
                  Tab(text: ref.t('timeline')),
                ],
              ),
              Expanded(
                child: state.detailLoading
                    ? const ManaSkeletonList(itemCount: 5, itemHeight: 64)
                    : state.detailError != null
                        ? Center(
                            child: ManaText.raw(state.detailError!,
                                style: ManaType.bad),
                          )
                        : detail == null
                            ? const SizedBox.shrink()
                            : TabBarView(
                                controller: _tabs,
                                children: [
                                  _EntryList(
                                    entries: detail.collections,
                                    emptyLabel: ref.t('no_collections_this_day'),
                                    onOpenSource: (loanId) => _goTo(
                                        context, '/ow-006?loan=$loanId', null),
                                    deletableAs: DeletableEntity.collection,
                                    businessId: widget.businessId,
                                  ),
                                  _EntryList(
                                    entries: detail.loans,
                                    emptyLabel: ref.t('no_loans_distributed_this_day'),
                                    onOpenSource: (loanId) => _goTo(context, '/ow-007', loanId),
                                    deletableAs: DeletableEntity.loan,
                                    businessId: widget.businessId,
                                  ),
                                  _EntryList(
                                      entries: detail.expenses,
                                      emptyLabel: ref.t('no_expenses_this_day'),
                                      deletableAs: DeletableEntity.expense,
                                      businessId: widget.businessId),
                                  _EntryList(
                                      entries: detail.deposits,
                                      emptyLabel: ref.t('no_investor_deposits_this_day'),
                                      deletableAs: DeletableEntity.investment,
                                      businessId: widget.businessId),
                                  _EntryList(
                                      entries: detail.withdrawals,
                                      emptyLabel: ref.t('no_investor_withdrawals_this_day'),
                                      deletableAs: DeletableEntity.investmentWithdrawal,
                                      businessId: widget.businessId),
                                  _EntryList(
                                    entries: detail.adjustments,
                                    emptyLabel: ref.t('no_corrections_adjustments_this_day'),
                                    deletableAs: DeletableEntity.settlementAdjustment,
                                    businessId: widget.businessId,
                                  ),
                                  _AuditList(entries: detail.auditLog),
                                  _EntryList(
                                    entries: detail.timeline,
                                    emptyLabel: ref.t('nothing_recorded_this_day_yet'),
                                  ),
                                ],
                              ),
              ),
              Padding(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _remarksController..text = widget.row.remarks ?? '',
                        decoration: InputDecoration(
                          labelText: ref.t('remarks_optional_freeform_note'),
                          border: const OutlineInputBorder(),
                        ),
                        maxLength: 500,
                      ),
                    ),
                    const SizedBox(width: ManaSpacing.sm),
                    Flexible(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: ManaColors.accent),
                        onPressed: () async {
                          final ok = await NetworkErrorHandler.run(context, () async {
                            return ref.read(recordBookProvider.notifier).updateRemarks(
                                  widget.businessId,
                                  widget.row.businessDate,
                                  _remarksController.text,
                                );
                          });
                          if (ok == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: ManaText.raw(ref.t('remarks_saved_note'))));
                          }
                        },
                        child: ManaText.raw(ref.t('save')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Closes the day-detail sheet, then opens the record it came from.
  ///
  /// `extra` is the businessId where a route wants one. A route that needs to
  /// know WHICH record takes it in the path -- /ow-006 read a loan id off
  /// `extra` until the footer nav started sending a business id through the
  /// same channel.
  void _goTo(BuildContext context, String route, String? extra) {
    Navigator.of(context).pop();
    context.push(route, extra: extra ?? widget.businessId);
  }
}

class _EntryList extends ConsumerWidget {
  final List<DayDetailEntry> entries;
  final String emptyLabel;
  final void Function(String loanId)? onOpenSource;

  /// What kind of record these rows are. Null makes the tab read-only —
  /// used for tabs whose rows are not individually deletable.
  final DeletableEntity? deletableAs;

  /// Needed to refresh the day after a delete changes its figures.
  final String? businessId;

  const _EntryList({
    required this.entries,
    required this.emptyLabel,
    this.onOpenSource,
    this.deletableAs,
    this.businessId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return Center(
        child: ManaText.raw(emptyLabel, style: ManaType.secondary),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: ManaSpacing.lg),
      itemBuilder: (context, i) {
        final e = entries[i];
        // The amount and the Correction pill moved OUT of `trailing` and
        // onto the subtitle line. ListTile's trailing slot must size to its
        // content, and amount + pill + open + delete together consumed the
        // whole tile width — which ListTile rejects outright rather than
        // merely overflowing. Actions stay in trailing; facts read below the
        // title, in a Wrap so they can drop to a second line when scaled.
        // WHO, THEN WHAT, THEN WHEN AND HOW MUCH.
        //
        // Reported from a handset: "it should at least show name, c/o,
        // village along with date & time to identify from whom collected
        // from." Before this the title was the word 'Collection' on every
        // row, so a day read "Collection / Collection / Collection" with
        // amounts beside them -- enough to see that money came in, and
        // nothing at all about whose.
        //
        // The NAME takes the title when there is one and the kind moves to
        // the line below. On a tab already labelled Collections, repeating
        // "Collection" eleven times is the one thing on the row carrying no
        // information. An expense keeps its category as the title, because
        // there the category IS what identifies it.
        final identity = [
          if (e.careOf != null && e.careOf!.isNotEmpty) 'C/o ${e.careOf}',
          if (e.village != null && e.village!.isNotEmpty) e.village!,
        ].join(' · ');

        return ListTile(
          contentPadding: EdgeInsets.zero,
          // The tile is three lines whenever anything sits between the title
          // and the facts row. Left at two, ListTile clips the identity line
          // rather than growing -- and it would clip exactly the C/o that was
          // added to tell two people apart.
          isThreeLine: e.isCorrection || identity.isNotEmpty,
          title: ManaText.raw(e.personName?.isNotEmpty == true
              ? e.personName!
              : e.label),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ManaFitText, NOT an ellipsis. This line is a C/o and a
              // village -- the two things that tell two people with the same
              // given name apart -- so cutting it takes away exactly the
              // information it was added to supply. It shrinks to fit and
              // wraps to a second line before it gives up anything.
              if (identity.isNotEmpty)
                ManaFitText(identity,
                    style: TextStyle(
                        fontSize: 13, color: ManaColors.textSecondary)),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: ManaSpacing.sm,
                runSpacing: ManaSpacing.xs,
                children: [
                  // The kind, now that the title is a person. Dropped when the
                  // title already IS the kind, so an expense does not read
                  // "Fuel / Fuel".
                  if (e.personName?.isNotEmpty == true)
                    ManaText.raw(e.label,
                        style: TextStyle(
                            fontSize: 13, color: ManaColors.textSecondary)),
                  ManaText.raw(
                      DateFormat('dd MMM, hh:mm a').format(e.timestamp),
                      style: TextStyle(
                          fontSize: 13, color: ManaColors.textSecondary)),
                  ManaAmount(e.amount, size: ManaAmountSize.compact),
                  if (e.isCorrection)
                    ManaStatusPill(
                        label: ref.t('correction'), status: ManaStatus.warn),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onOpenSource != null && e.sourceLoanId != null)
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: () => onOpenSource!(e.sourceLoanId!),
                ),
              if (deletableAs != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: ManaColors.statusBad,
                  tooltip: ref.t('delete'),
                  onPressed: () => _delete(context, ref, e),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, DayDetailEntry e) async {
    final deleted = await ConfirmDeleteDialog.show(
      context,
      entity: deletableAs!,
      recordId: e.id,
      description: '${e.label} — ${manaRupees(e.amount)}',
    );
    if (!deleted || !context.mounted || businessId == null) return;
    // The day's figures moved, and so did every day after it. Reload rather
    // than removing the row from the list and leaving the totals stale.
    await ref.read(recordBookProvider.notifier).load(businessId!);
  }
}

/// `audit_log` is administrative/security events ONLY (BR-124/158) — a
/// Day Reopen, a Loan/Collection Correction record, a permission change,
/// etc. Routine collections/loans/expenses do NOT appear here (they're
/// already the "Collections"/"Loans"/etc. tabs above).
class _AuditList extends ConsumerWidget {
  final List<AuditLogEntry> entries;
  const _AuditList({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return Center(
        child: ManaText.raw(ref.t('no_admin_security_events_this_day'),
            style: ManaType.secondary),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: ManaSpacing.lg),
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: ManaText(e.actionType),
          subtitle: ManaText.raw('${e.entityType} · ${e.entityId}',
              style: ManaType.note),
          trailing: ManaText.raw(DateFormat('dd MMM, hh:mm a').format(e.entryTimestamp),
              style: ManaType.note),
        );
      },
    );
  }
}

/// The translation key for each sheet line.
///
/// A top-level switch rather than a getter on the enum: ManaSheetLine lives in
/// state/ and must not know about translation keys, which are a UI concern --
/// and both the card that draws the sheet and the chooser that edits it need
/// the same answer, so it cannot sit on either.
String _lineKey(ManaSheetLine line) => switch (line) {
      ManaSheetLine.broughtForward => 'brought_forward',
      ManaSheetLine.vasool => 'vasool',
      ManaSheetLine.karchu => 'karchu',
      ManaSheetLine.vaddi => 'vaddi',
      ManaSheetLine.processingFee => 'processing_fee',
      ManaSheetLine.investorDeposit => 'investor_dep',
      ManaSheetLine.investorWithdrawal => 'investor_wd',
      ManaSheetLine.chetiReceived => 'cheti_received',
      ManaSheetLine.chetiPaid => 'cheti_paid',
      ManaSheetLine.expenses => 'expenses',
      ManaSheetLine.shortExcess => 'short_excess',
    };
