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
import '../../../shared/payment_modes.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../state/record_book_state.dart';
import 'ow_line_pending_list.dart';

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
  final _pager = PageController();

  /// Which account is in front, so the arrow bar can say so and stop
  /// offering a direction there is nothing in.
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

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
    // The picked day becomes the newest row, so it is page 0 -- but the pager
    // is wherever the Owner left it. Without this, jumping to a date lands on
    // whatever account happens to sit at that index, which is a different day
    // from the one they chose.
    if (!mounted || !_pager.hasClients) return;
    _pager.jumpToPage(0);
    setState(() => _page = 0);
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
          // THE PENDING LIST HANGS OFF THE ACCOUNT SHEET, because the design
          // document puts it there -- 2.6.1.1, beneath 2.6 Account Sheet. An
          // Owner reading today's closing is exactly who wants to know who
          // has not paid, and it saves inventing a screen ID for a view the
          // spec numbered as a child.
          IconButton(
            tooltip: ref.t('line_pending_list'),
            icon: const Icon(Icons.pending_actions_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    LinePendingListScreen(businessId: widget.businessId),
              ),
            ),
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
                      // over at 2.0x in Telugu. The cause was its LABEL, not
                      // the number of actions: a TextButton.icon grows with
                      // text scale and an IconButton does not. The pending-list
                      // action added later is a sixth icon in that bar and the
                      // same tests pass at 2.0x in Telugu -- so the rule is
                      // "no labelled controls in this bar", not "no more than
                      // five". The first version of this comment said the
                      // latter, which would have argued against a change that
                      // turned out to be fine.
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
                      // ONE ACCOUNT, AND THE NEXT ONE IS SIDEWAYS.
                      //
                      // The Owner, on build 14.8: "no scrolling - show one
                      // account and swipe to left to see the next account with
                      // arrow mark."
                      //
                      // This was a VERTICAL pager for about an hour earlier
                      // today, and it had to be torn out: a day tall enough to
                      // need its own scroll view puts two scrollables on the
                      // same axis, Flutter does not hand the gesture up when
                      // the inner one ends, and the pager sat at offset 0
                      // through three consecutive flings. Measured, not
                      // guessed. Horizontal has none of that -- the page turns
                      // on one axis and the content scrolls on the other, so
                      // they never compete for the same drag.
                      //
                      // rows are newest-first, so page 0 is the latest account
                      // and swiping left walks backwards in time.
                      Expanded(
                        child: PageView.builder(
                          controller: _pager,
                          itemCount: state.rows.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (context, i) => SingleChildScrollView(
                            // Vertical, against a horizontal pager, so this is
                            // not the nested-scroll trap the vertical version
                            // was. It exists only for 2.0x text, where the
                            // sheet is taller than the screen and the Closing
                            // -- the one figure the sheet exists to state --
                            // would otherwise be clipped.
                            padding: const EdgeInsets.all(ManaSpacing.lg),
                            child: _LedgerRowCard(
                              row: state.rows[i],
                              income: state.loanIncome[
                                  manaIsoDate(state.rows[i].businessDate)],
                              shown: _shown,
                              modes: state.paymentModes[
                                  manaIsoDate(state.rows[i].businessDate)],
                              onTap: () =>
                                  _openDayDetails(context, state.rows[i]),
                              onDateTap: () => _pickDate(context),
                            ),
                          ),
                        ),
                      ),
                      // THE ARROW MARK the Owner asked for, and a position.
                      //
                      // A PageView gives no sign that anything is beside it.
                      // On a list you can see the next row beginning; on a
                      // pager the screen looks identical whether there are two
                      // accounts or twenty, and the gesture is only
                      // discoverable by accident.
                      //
                      // The arrows are buttons as well as signs. One-handed at
                      // a doorstep, a tap at the edge is easier than a swipe
                      // across the whole screen, and an arrow that points at
                      // something you cannot press reads as broken.
                      if (state.rows.length > 1)
                        _PagerBar(
                          page: _page,
                          count: state.rows.length,
                          onPrev: () => _pager.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut),
                          onNext: () => _pager.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut),
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

  /// How this day's Vasool arrived, by mode. Null means it was not broken
  /// down, which is not the same as a day that took nothing.
  final Map<String, int>? modes;

  /// TAP opens the day's entries.
  ///
  /// It was a long press for one build, on the Owner's first instruction, and
  /// they changed it on seeing it: "not long tap - just tap to open the
  /// summary of that account." A long press is an invisible gesture -- nothing
  /// on the card says it is there -- and the summary is the main thing an
  /// Owner wants from a day.
  ///
  /// The date still opens the calendar, and still wins, because its InkWell is
  /// a child of this one: Flutter's gesture arena gives the contest to the
  /// innermost hit target, so the two do not fight.
  final VoidCallback onTap;

  /// Tap the date to jump to another day.
  final VoidCallback onDateTap;

  const _LedgerRowCard({
    required this.row,
    required this.income,
    required this.shown,
    required this.modes,
    required this.onTap,
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
        onTap: onTap,
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
              // THE MODE SPLIT AS A NOTE, NOT ROWS -- for exactly the reason
              // spelled out for penalty immediately below, and worth saying
              // twice because the pull to make them rows is strong. Page 4 of
              // the design document totals the day by mode underneath the
              // slip, and the Owner approved it. But Cash + GPay + PhonePe
              // ADD UP TO Vasool; they are not money arriving beside it. In a
              // two-column sheet that sums its columns, a Cash row and a
              // Vasool row would count every rupee twice.
              //
              // Zero-amount modes are dropped: a day that took nothing by
              // Paytm has nothing to say about Paytm.
              if (modes != null &&
                  modes!.values.any((v) => v != 0)) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaFitText(
                  '${ref.t('how_it_was_paid')}: '
                  '${(modes!.entries.where((e) => e.value != 0).toList()
                        ..sort((a, b) => b.value.compareTo(a.value)))
                      .map((e) => '${ref.t(manaPaymentModeKey(e.key))} '
                          '${manaRupees(e.value)}')
                      .join(' · ')}',
                  style: ManaType.note,
                ),
              ],
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
/// The arrow mark, and which account of how many is in front.
///
/// Both arrows are always drawn and the unavailable one is disabled rather
/// than removed. A control that disappears moves the one beside it, and on
/// the last account the Owner would find the button they were aiming at has
/// shifted under their thumb.
class _PagerBar extends StatelessWidget {
  final int page;
  final int count;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _PagerBar({
    required this.page,
    required this.count,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            // Page 0 is the LATEST account, so this arrow moves towards the
            // more recent one -- forwards in time, backwards through pages.
            onPressed: page > 0 ? onPrev : null,
          ),
          // Flexible so a large text scale shrinks this rather than pushing
          // an arrow off the edge.
          Flexible(
            child: ManaFitText('${page + 1} / $count',
                style: ManaType.secondary, maxLines: 1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: page < count - 1 ? onNext : null,
          ),
        ],
      ),
    );
  }
}

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
