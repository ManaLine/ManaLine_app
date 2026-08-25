import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design/components/mana_amount.dart';
import '../design/components/mana_collection_search_field.dart';
import '../design/components/mana_skeleton.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../features/owner_workspace/state/collection_mode_state.dart';
import 'mana_time.dart';
import 'translation_service.dart';

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

  /// What tapping a row opens. Passed in rather than hardcoded so this file
  /// does not have to import a workspace's screens.
  final void Function(BuildContext context, CollectionDueRow row) onOpenRow;

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

  /// Where the app-bar Back arrow goes. The two workspaces have different
  /// homes, and landing an Agent on the Owner's dashboard would show them a
  /// business they do not run.
  final VoidCallback? onBack;

  const ManaCollectionRound({
    super.key,
    required this.businessId,
    required this.onOpenRow,
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
  Widget _villageDropdown(List<CollectionDueRow> all) {
    final villages = manaVillagesInRound(all);
    if (villages.isEmpty) return const SizedBox.shrink();
    // A-Z, with All Villages pinned on top.
    final sorted = [...villages]..sort((a, b) => a.village.compareTo(b.village));
    final total = all.length;
    // One village selected at a time through this control. The Set underneath
    // still supports several, which is what the filter helper takes.
    final current = _villages.isEmpty ? null : _villages.first;

    return _HeaderDropdown<String?>(
      label: ref.t('village'),
      value: current,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: ManaText.raw('${ref.t('all_villages')} · $total',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: ManaType.small),
        ),
        for (final v in sorted)
          DropdownMenuItem<String?>(
            value: v.village,
            child: ManaText.raw(
              '${v.village.isEmpty ? "—" : v.village} · ${v.rows}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ManaType.small,
            ),
          ),
      ],
      onChanged: (v) => setState(() {
        _villages.clear();
        if (v != null) _villages.add(v);
      }),
    );
  }

  Widget _frequencyDropdown() => _HeaderDropdown<String?>(
        label: ref.t('frequency'),
        value: _frequency,
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: ManaText.raw(ref.t('all'), style: ManaType.small),
          ),
          for (final f in const ['Daily', 'Weekly', 'Monthly'])
            DropdownMenuItem<String?>(
              value: f,
              child: ManaText.raw(f, style: ManaType.small),
            ),
        ],
        onChanged: (f) => setState(() => _frequency = f),
      );

  Widget _sortDropdown() => _HeaderDropdown<CollectionSort>(
        label: ref.t('sorted_by'),
        value: _sort,
        items: [
          for (final m in CollectionSort.values)
            DropdownMenuItem(
              value: m,
              child: ManaText.raw(m.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: ManaType.small),
            ),
        ],
        onChanged: (m) => setState(() => _sort = m ?? CollectionSort.dueToday),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectionModeProvider);

    if (!_focusHandled && widget.focusLoanId != null && state.dueList.isNotEmpty) {
      final match =
          state.dueList.where((r) => r.loanId == widget.focusLoanId).firstOrNull;
      _focusHandled = true;
      if (match != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onOpenRow(context, match);
        });
      }
    }

    final visible = manaSortDueRows(
      manaFilterDueRows(
        manaFilterByVillages(state.sorted, _villages),
        _query,
        frequency: _frequency,
      ),
      _sort,
    );

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null ? null : BackButton(onPressed: widget.onBack),
        title: ManaText.raw(ref.t('collection_mode')),
        actions: [
          IconButton(
            icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
            tooltip: ref.t('search'),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              // Closing the search restores the full round. Leaving a filter
              // applied behind a collapsed box is how a round is finished in
              // the belief that everyone was visited.
              if (!_searchOpen) _query = '';
            }),
          ),
        ],
        // The filters live in the header, above the round rather than inside
        // it, so scrolling the list never scrolls the controls away.
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_searchOpen ? 116 : 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                ManaSpacing.md, 0, ManaSpacing.md, ManaSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_searchOpen)
                  ManaCollectionSearchField(
                    onChanged: (v) => setState(() => _query = v),
                  ),
                Row(
                  children: [
                    Expanded(child: _villageDropdown(state.sorted)),
                    const SizedBox(width: ManaSpacing.sm),
                    Expanded(child: _frequencyDropdown()),
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
                        ManaText.raw(DateFormat('d MMM yyyy').format(manaNowIst()),
                            style: ManaType.note),
                        const Spacer(),
                        Flexible(child: _sortDropdown()),
                      ],
                    ),
                    const SizedBox(height: ManaSpacing.sm),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          // "Nobody is due" and "nothing matched what you
                          // typed" are different facts, and telling somebody
                          // the first when the second is true reads as an
                          // empty round.
                          child: ManaText.raw(
                              _query.trim().isEmpty
                                  ? ref.t('nobody_due_today')
                                  : ref.t('no_customers_match_view'),
                              textAlign: TextAlign.center,
                              style: ManaType.secondary),
                        ),
                      )
                    else
                      ...visible.map((row) => ManaDueRow(
                            row: row,
                            onTap: () => widget.onOpenRow(context, row),
                          )),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A labelled dropdown sized for the app bar.
class _HeaderDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _HeaderDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: ManaSpacing.sm, vertical: ManaSpacing.xs),
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          // Without this the button sizes to the selected item's intrinsic
          // width, and a long village name (or a wide Telugu translation)
          // overflows the Row that DropdownButton lays its value and arrow
          // out in, since that Row has nothing constraining it.
          isExpanded: true,
          isDense: true,
          items: items,
          onChanged: onChanged,
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
class ManaDueRow extends ConsumerWidget {
  final CollectionDueRow row;
  final VoidCallback onTap;
  const ManaDueRow({super.key, required this.row, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // NOT a ListTile -- its leading/title/trailing layout clamps content to a
    // fixed height and squeezes the title as the trailing text widens, both
    // only at larger text scales, which is why that shipped unnoticed.
    final done = row.collectionStatus == 'Collected';
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ManaText.raw(row.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ManaType.emphasis),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  if (done)
                    Icon(Icons.check_circle, size: 20, color: ManaColors.statusGood)
                  else
                    FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding:
                            const EdgeInsets.symmetric(horizontal: ManaSpacing.md),
                      ),
                      child: ManaText.raw(ref.t('pay')),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              // MLID under the name: it is how a person is identified aloud
              // at a door, and how two customers of the same name are told
              // apart. The loan number that used to sit here told nobody
              // anything they could act on.
              if (row.mlid.isNotEmpty)
                ManaText.raw(row.mlid,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: ManaType.note),
              // What they are asked at a door is how much is still owed.
              // maxLines/overflow are required, not optional: an unbroken
              // token forces its own width and overflows rather than wrapping.
              ManaText.raw(
                '${row.village} · ${manaRupees(row.outstandingBalance)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ManaType.note,
              ),
              const SizedBox(height: ManaSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: row.penaltyEligible
                        ? ManaText.raw(ref.t('penalty'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: ManaColors.statusBad))
                        : row.gracePeriod
                            ? ManaText.raw(ref.t('grace'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: ManaColors.statusWarn))
                            : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  Flexible(
                    child: ManaText.raw(manaRupees(row.installmentDue),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ManaType.cardTitle),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
