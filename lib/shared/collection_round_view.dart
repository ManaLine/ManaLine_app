import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design/components/mana_amount.dart';
import '../design/components/mana_collection_search_field.dart';
import '../design/components/mana_skeleton.dart';
import '../design/components/mana_brand_mark.dart';
import '../design/components/mana_app_bar.dart';
import '../design/components/mana_filter_rail.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../features/owner_workspace/state/collection_mode_state.dart';
import 'apply_penalty_sheet.dart';
import 'collect_sheet.dart';
import 'mana_time.dart';
import 'network_error_handler.dart';
import 'translation_service.dart';
import 'outbox/mana_outbox_banner.dart';

/// The collection round, for whoever is walking it.
///
/// OW-006 and AG-002 rendered the same `collectionModeProvider` through two
/// separate lists, and AG-002's own comment admitted its due row was "a
/// near-verbatim duplicate" of the Owner's. They drifted: the Owner's round
/// was rebuilt with village filters, a sort picker and a Pay button while the
/// Agent -- the person who actually walks the round -- kept the old one.
///
/// Sharing the widget does NOT merge the two workspaces' entries. A collection
/// is attributed server-side: record_collection checks
/// `own_active_agent_membership_permits`, so an Agent can only ever record as
/// themselves and only with `can_collect_payments`. What the role changes is
/// where Back goes and what the screen offers -- never whose name lands on the
/// money.
class ManaCollectionRound extends ConsumerStatefulWidget {
  final String businessId;

  /// A loan to open straight away, if it is in today's round.
  ///
  /// The /ow-006 route has always passed something through `extra` -- a
  /// businessId from the dashboard, a customerId from Customer Management, a
  /// loanId from Loan Details and the record book -- and the screen read none
  /// of them, so "open this customer's collection" quietly landed on the plain
  /// round every time. Anything that is not a loan in the round is ignored
  /// rather than guessed at, which is what makes the other two call sites
  /// harmless.
  final String? focusLoanId;

  /// The footer nav for whoever is walking this round, or null.
  ///
  /// Passed in for the same reason onBack is: the two workspaces have
  /// different destinations, and this view must not decide which set of four
  /// an Agent sees. Null leaves the screen without a bar, which is what an
  /// embedded round wants.
  final Widget? bottomNavigationBar;

  /// Where the app-bar Back arrow goes. The two workspaces have different
  /// homes, and landing an Agent on the Owner's dashboard would show them a
  /// business they do not run.
  final VoidCallback? onBack;

  const ManaCollectionRound({
    this.bottomNavigationBar,
    super.key,
    required this.businessId,
    this.onBack,
    this.focusLoanId,
  });

  @override
  ConsumerState<ManaCollectionRound> createState() => _ManaCollectionRoundState();
}

class _ManaCollectionRoundState extends ConsumerState<ManaCollectionRound> {
  /// Local, not in the notifier: searching narrows what is on screen, it does
  /// not change the round. Keeping it out of the notifier is also what stops a
  /// reload from silently re-applying it.
  String _query = '';
  bool _searchOpen = false;

  /// Daily / Weekly / Monthly, or null for the whole round. A view preference,
  /// not state the collection depends on -- reloading must not re-narrow it.
  String? _frequency;
  CollectionSort _sort = CollectionSort.dueToday;

  /// Empty means the whole round. Somebody who has picked nothing has not
  /// asked to be shown nothing.
  final Set<String> _villages = {};

  /// Opened once, not on every rebuild -- a reload must not reopen the entry
  /// screen on top of whatever the user has since navigated to.
  bool _focusHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(collectionModeProvider.notifier).load(widget.businessId);
    });
  }

  /// Villages as a dropdown rather than a row of chips.
  ///
  /// Chips wrapped onto three lines on a real handset and pushed the round
  /// itself below the fold -- the list is what the work happens in, and a
  /// filter should not out-size it. A village whose loans are all settled is
  /// not offered: it is not a place to walk to today.
  /// THE LINE. One amber hairline, and the only decorative-looking thing on
  /// this screen that is not decoration.
  ///
  /// The app is called MANA LINE, and in this trade a line is two things at
  /// once: the round an agent walks, and the ruled column of the paper ledger
  /// this replaces. `line_balance` and `line_repayment_index` are already in
  /// the schema. The word is the product's own, so the signature is drawn from
  /// it rather than from a moodboard -- amber because amber is already the
  /// functional decision here (a high-luminance surface with dark marks is
  /// what survives glare, which is why hi-vis clothing is that colour), and
  /// horizontal because a ledger is.
  ///
  /// It is also the answer to a question the round could not answer. The list
  /// showed every door and said nothing about progress, so an agent halfway
  /// down a village counted the rows they had already walked past. Filled for
  /// what has been collected, hollow for what has not.
  ///
  /// COUNTED OVER THE WHOLE ROUND, not the filtered view: narrowing to one
  /// village must not make the day look finished. `all` is state.sorted.
  ///
  /// 2dp costs nothing to render on a cheap handset, survives 2.0x text scale
  /// because it is not text, and carries no translation.
  Widget _roundLine(List<CollectionDueRow> all) {
    if (all.isEmpty) return const SizedBox.shrink();
    final done = all.where(manaRowSettled).length;
    final fraction = done / all.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(
            ref
                .t('round_progress')
                .replaceAll('{done}', '$done')
                .replaceAll('{total}', '${all.length}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ManaType.note,
          ),
          const SizedBox(height: ManaSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Container(
                  height: 2,
                  width: constraints.maxWidth,
                  color: ManaColors.brand.withValues(alpha: 0.20),
                ),
                Container(
                  height: 2,
                  width: constraints.maxWidth * fraction,
                  color: ManaColors.brand,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _villageDropdown(List<CollectionDueRow> all) {
    final villages = manaVillagesInRound(all);
    if (villages.isEmpty) return const SizedBox.shrink();
    // A-Z, with All Villages pinned on top.
    final sorted = [...villages]..sort((a, b) => a.village.compareTo(b.village));
    final total = all.length;
    // One village selected at a time through this control. The Set underneath
    // still supports several, which is what the filter helper takes.
    //
    // Falls back to All Villages when the chosen village is no longer offered.
    // manaVillagesInRound drops a village once everything in it is settled, so
    // collecting from the last customer in Uranduru removes it from these
    // items while it is still selected -- and a DropdownButton whose value
    // matches no item throws. Only reachable now that a collected row stays on
    // screen instead of the round silently reloading without it.
    final selected = _villages.isEmpty ? null : _villages.first;
    final current =
        sorted.any((v) => v.village == selected) ? selected : null;

    return ManaFilterChip<String?>(
      label: ref.t('village'),
      value: current,
      active: current != null,
      options: [
        ManaFilterOption(null, '${ref.t('all_villages')} · $total'),
        for (final v in sorted)
          ManaFilterOption(
              v.village, '${v.village.isEmpty ? "—" : v.village} · ${v.rows}'),
      ],
      onChanged: (v) => setState(() {
        _villages.clear();
        if (v != null) _villages.add(v);
      }),
    );
  }

  /// Sort direction. Default descending, which is what a round wants: the
  /// biggest amount due at the top.
  bool _ascending = false;

  /// Collection status, or null for every door.
  String? _status;

  Widget _orderChip() => ManaFilterChip<bool>(
        label: ref.t('sort_order'),
        value: _ascending,
        active: _ascending,
        options: [
          ManaFilterOption(false, ref.t('highest_first')),
          ManaFilterOption(true, ref.t('lowest_first')),
        ],
        onChanged: (v) => setState(() => _ascending = v),
      );

  Widget _statusChip() => ManaFilterChip<String?>(
        label: ref.t('status'),
        value: _status,
        active: _status != null,
        options: [
          ManaFilterOption(null, ref.t('all')),
          for (final s in const ['Pending', 'Collected', 'Partial', 'Skipped'])
            ManaFilterOption(s, ref.t(s.toLowerCase())),
        ],
        onChanged: (v) => setState(() => _status = v),
      );

  Widget _frequencyChip() => ManaFilterChip<String?>(
        label: ref.t('frequency'),
        value: _frequency,
        active: _frequency != null,
        options: [
          ManaFilterOption(null, ref.t('all')),
          for (final f in const ['Daily', 'Weekly', 'Monthly'])
            ManaFilterOption(f, f),
        ],
        onChanged: (f) => setState(() => _frequency = f),
      );

  Widget _sortChip() => ManaFilterChip<CollectionSort>(
        label: ref.t('sorted_by'),
        value: _sort,
        active: _sort != CollectionSort.dueToday,
        options: [
          for (final m in CollectionSort.values) ManaFilterOption(m, m.label),
        ],
        onChanged: (m) => setState(() => _sort = m),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectionModeProvider);

    if (!_focusHandled && widget.focusLoanId != null && state.dueList.isNotEmpty) {
      final match =
          state.dueList.where((r) => r.loanId == widget.focusLoanId).firstOrNull;
      _focusHandled = true;
      if (match != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final recorded = await showCollectSheet(context,
              row: match, businessId: widget.businessId);
          if (recorded && mounted) {
            ref.read(collectionModeProvider.notifier).load(widget.businessId);
          }
        });
      }
    }

    final visible = manaSortDueRows(
      manaFilterByStatus(
        manaFilterDueRows(
          manaFilterByVillages(state.sorted, _villages),
          _query,
          frequency: _frequency,
        ),
        _status,
      ),
      _sort,
      ascending: _ascending,
    );

    return Scaffold(
      bottomNavigationBar: widget.bottomNavigationBar,
      appBar: ManaAppBar(
        // onBack passes straight through, null included: a null here means
        // this view is embedded and the host owns back, which is the same
        // thing the conditional leading used to say.
        onBack: widget.onBack,
        title: ref.t('collection_mode'),
        // No search action up here. The header carries Universal Search on
        // every Owner and Agent screen now, and this screen's own search
        // narrows THIS round -- two different questions that were about to
        // share a magnifier, side by side, in the same bar. The round's own
        // search moved down into the filter rail, where the rest of the
        // narrowing controls are.
        // The filters live in the header, above the round rather than inside
        // it, so scrolling the list never scrolls the controls away.
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_searchOpen ? 132 : 68),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                ManaSpacing.md, 0, ManaSpacing.md, ManaSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Collections still on the phone. Shown HERE, on the shared
                // round view, so the Owner's OW-006 and the Agent's AG-002
                // both get it from one widget -- two copies would drift, and
                // what they would drift about is whether somebody's money has
                // been recorded. Draws nothing when the queue is empty.
                const ManaOutboxBanner(),
                if (_searchOpen)
                  ManaCollectionSearchField(
                    onChanged: (v) => setState(() => _query = v),
                  ),
                // Order, village, sort, status, frequency -- the same rail
                // Customer Management uses, so the two screens filter the same
                // book through the same control. It scrolls sideways rather
                // than wrapping: five filters in a grid is three rows of
                // controls above a list that is the point of the screen.
                ManaFilterRail(
                  leading: IconButton(
                    icon: Icon(_searchOpen ? Icons.search_off : Icons.person_search),
                    tooltip: ref.t('search_this_round'),
                    onPressed: () => setState(() {
                      _searchOpen = !_searchOpen;
                      // Closing the search restores the full round. Leaving a
                      // filter applied behind a collapsed box is how a round
                      // is finished in the belief that everyone was visited.
                      if (!_searchOpen) _query = '';
                    }),
                  ),
                  filters: [
                    _orderChip(),
                    _villageDropdown(state.sorted),
                    _sortChip(),
                    _statusChip(),
                    _frequencyChip(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(collectionModeProvider.notifier).load(widget.businessId),
          child: state.loading && state.dueList.isEmpty
              ? const ManaSkeletonList()
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    Row(
                      children: [
                        // manaNowIst(), not DateTime.now(): this names which
                        // business day's round is being walked, and a handset
                        // an hour either side of midnight in the wrong zone
                        // would name the wrong one.
                        Flexible(
                          child: ManaText.raw(
                              DateFormat('d MMM yyyy').format(manaNowIst()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.note),
                        ),
                      ],
                    ),
                    const SizedBox(height: ManaSpacing.sm),
                    _roundLine(state.sorted),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          // "Nobody is due" and "nothing matched what you
                          // typed" are different facts, and telling somebody
                          // the first when the second is true reads as an
                          // empty round.
                          // An empty screen is an invitation, and this app
                          // already owns a good sentence for one. The tagline
                          // appeared once, small, on a screen nobody spends
                          // time on; it belongs where the app is idle and
                          // waiting, which is a round with nothing left in it.
                          //
                          // Only on a FINISHED round -- never under "nothing
                          // matched what you typed", where the screen is not
                          // idle, the agent is mid-search, and a brand mark
                          // would be the app congratulating itself over
                          // somebody's failed filter.
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ManaText.raw(
                                  _query.trim().isEmpty
                                      ? ref.t('nobody_due_today')
                                      : ref.t('no_customers_match_view'),
                                  textAlign: TextAlign.center,
                                  style: ManaType.secondary),
                              if (_query.trim().isEmpty) ...[
                                const SizedBox(height: ManaSpacing.md),
                                ManaText.raw(
                                  kManaTagline,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.0,
                                    color: ManaColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    else
                      ...visible.map((row) => ManaDueRow(
                            // Keyed by loan, not by position: the sort is by
                            // what is due, and recording a payment moves the
                            // row the moment the round reloads.
                            key: ValueKey(row.loanId),
                            row: row,
                            businessId: widget.businessId,
                            onDone: () => ref
                                .read(collectionModeProvider.notifier)
                                .load(widget.businessId),
                          )),
                  ],
                ),
        ),
      ),
    );
  }
}


/// One customer in the round.
///
/// Shared by both workspaces. The status circle that used to lead the row
/// carried one bit -- collected or not -- in the most valuable spot on it,
/// while Pay is what somebody standing at a door reaches for. The row leads
/// with the name and ends with the money.
/// One customer in the round.
///
/// Three lines, and every one of them earns its place: who this is, how to
/// name them at the door, and the two figures that matter -- what they still
/// owe, and what they hand over today.
///
/// Collect opens a sheet over the round rather than navigating or expanding in
/// place. A pushed screen restated this row's own contents before any figure
/// could be typed; an inline expansion pushed the rest of the round off a
/// 360px handset. The sheet leaves the list visible and closes on a tap
/// outside without recording anything.
///
/// The Penalty tag is a control, not a label. An Owner who can see a customer
/// is overdue is one tap from doing something about it, and a penalty is real
/// money -- applying one adds it to the balance.
class ManaDueRow extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final String businessId;

  /// Something was recorded against this loan -- a payment, a visit without
  /// one, an extension, or a penalty. The round reloads: the balance, what is
  /// due and today's outcome have all moved.
  final VoidCallback onDone;

  const ManaDueRow({
    super.key,
    required this.row,
    required this.businessId,
    required this.onDone,
  });

  @override
  ConsumerState<ManaDueRow> createState() => _ManaDueRowState();
}

class _ManaDueRowState extends ConsumerState<ManaDueRow> {
  Future<void> _collect() async {
    final recorded = await showCollectSheet(
      context,
      row: widget.row,
      businessId: widget.businessId,
    );
    if (recorded && mounted) widget.onDone();
  }

  /// Long press on a door already answered: open what was recorded and
  /// correct it.
  ///
  /// A wrong figure used to be permanent. The row went quiet, the tap did
  /// nothing, and the only recovery was an Owner deleting the collection --
  /// which is not available to somebody standing in a village. One entry per
  /// loan per day is enforced server-side now, so this is the ONLY way to
  /// change one, and app.amend_collection closes the window once the account
  /// has gone to the Owner.
  Future<void> _correct() async {
    final existing = await NetworkErrorHandler.run(context, () {
      return ref.read(collectionModeProvider.notifier).loadTodaysCollection(
            loanId: widget.row.loanId,
            businessDate: manaBusinessDate(),
          );
    });
    if (!mounted) return;
    if (existing == null) {
      // A door recorded as "no collection" has a visit but no entry, and a
      // long press on it would otherwise do nothing at all -- which reads as
      // a broken screen rather than as an answer.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('nothing_to_correct'))),
      );
      return;
    }
    final amended = await showCollectSheet(
      context,
      row: widget.row,
      businessId: widget.businessId,
      editing: existing,
    );
    if (amended && mounted) widget.onDone();
  }

  Future<void> _penalty() async {
    final applied = await showApplyPenaltySheet(
      context,
      ref,
      loanId: widget.row.loanId,
      customerName: widget.row.customerName,
      outstandingBalance: widget.row.outstandingBalance,
    );
    if (applied && mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    // Same rule the sort uses to sink finished doors -- see manaRowSettled.
    // Two copies of it drifting apart would grey a row that still sorted as
    // work to do.
    final done = manaRowSettled(row);

    // A finished door stays in the list and goes quiet. Removing it would make
    // the round shorter than the work actually done, and an Agent checking
    // whether they visited somebody would find nothing there.
    return Opacity(
      opacity: done ? 0.55 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
        child: InkWell(
          onTap: done ? null : _collect,
          // Settled rows only. A long press on a door not yet visited has
          // nothing to correct.
          onLongPress: done ? _correct : null,
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Expanded and two lines, so the whole name shows.
                    //
                    // It shared one line with a Penalty tag and a Collect
                    // button, and Flexible let all three negotiate for width:
                    // the name lost, and every three-part name ended in an
                    // ellipsis -- "Daggubati Dilip..." on a screen whose job
                    // is to say whose door this is. It takes the width first
                    // now, and wraps rather than truncating.
                    Expanded(
                      child: ManaText.raw(row.customerName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ManaType.emphasis),
                    ),
                    if (row.penaltyEligible && !done) ...[
                      const SizedBox(width: ManaSpacing.xs),
                      // Tappable: this is where a penalty gets applied.
                      InkWell(
                        onTap: _penalty,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ManaSpacing.xs, vertical: 2),
                          child: ManaText.raw(ref.t('penalty'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  color: ManaColors.statusBad)),
                        ),
                      ),
                    ] else if (row.gracePeriod && !done) ...[
                      const SizedBox(width: ManaSpacing.xs),
                      ManaText.raw(ref.t('grace'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ManaColors.statusWarn)),
                    ],
                    const SizedBox(width: ManaSpacing.sm),
                    if (done)
                      Icon(Icons.check_circle,
                          size: 20, color: ManaColors.statusGood)
                    else
                      // Flexible with an ellipsis: "Collect" is one word in
                      // English and a much wider one in Telugu, and a bare
                      // button beside a Flexible name is this app's recurring
                      // overflow shape.
                      Flexible(
                        child: FilledButton(
                          onPressed: _collect,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: ManaSpacing.md),
                          ),
                          child: ManaText.raw(ref.t('collect'),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                // How this customer is named at a door: the ID on the card
                // they carry, and where they are.
                ManaText.raw(
                  [row.mlid, row.village].where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ManaType.note,
                ),
                // Correcting an entry is a long press, and a gesture nobody
                // is told about is a gesture nobody uses. Only on the rows it
                // applies to.
                if (done) ...[
                  const SizedBox(height: 2),
                  ManaText.raw(ref.t('long_press_to_correct'),
                      maxLines: 2, style: ManaType.note),
                ],
                const SizedBox(height: ManaSpacing.xs),
                // THE TWO FIGURES ARE THE POINT OF THE ROW, and they were the
                // smallest text on it.
                //
                // Both were interpolated into a sentence and handed to
                // ManaText: the balance at ManaType.note, which is 13sp, and
                // the EMI at cardTitle, 16sp. ManaAmount exists precisely to
                // stop that -- its own doc records that money was being set at
                // 11-12sp across the app, "the most important numbers in the
                // app were among its smallest text" -- and it declares 16sp as
                // the floor for a rupee figure. The screen an agent reads at a
                // door was below that floor.
                //
                // What ManaAmount adds beyond size, and why a NumberFormat
                // call could not: TABULAR FIGURES, so a column of amounts
                // aligns instead of jittering (1 is narrower than 8, so ₹1,111
                // and ₹8,888 did not line up, and scanning a round for the odd
                // figure out is the core task here); a screen-reader label, so
                // TalkBack says "four thousand rupees" instead of spelling the
                // glyphs; and no soft-wrap mid-number.
                //
                // Labels sit ABOVE their figures now rather than inline. The
                // amounts are then the only thing on their baseline, which is
                // what makes the column scannable, and at 2.0x text scale the
                // label wraps on its own line instead of shoving the number.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ManaText.raw(ref.t('balance'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.fine),
                          ManaAmount(row.outstandingBalance,
                              size: ManaAmountSize.compact,
                              semanticLabel: ref.t('balance')),
                        ],
                      ),
                    ),
                    const SizedBox(width: ManaSpacing.sm),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ManaText.raw(ref.t('emi'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.fine),
                          // The figure to ask for at the door, and the largest
                          // thing on the row.
                          ManaAmount(row.installmentAmount,
                              size: ManaAmountSize.standard,
                              semanticLabel: ref.t('emi')),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
