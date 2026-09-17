import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design/components/mana_amount.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_filter_rail.dart';
import '../../../design/components/mana_fit_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/translation_service.dart';
import '../state/line_pending_state.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

/// The Line Pending List — design document 2.6.1.1, opened from the Account
/// Sheet (2.6), which is the Daily Record Book.
///
/// NO SCREEN ID, deliberately. CLAUDE.md: "Screen IDs are the routing
/// contract... a file/screen number doubles as its route name." The document
/// numbers this 2.6.1.1, a view BENEATH the account sheet rather than a screen
/// beside it, and inventing an OW-0xx for it would put a number in the routing
/// contract that no spec locked. It is pushed from OW-009 the same way
/// VillageCustomersScreen is pushed from the village book.
class LinePendingListScreen extends ConsumerStatefulWidget {
  final String businessId;
  const LinePendingListScreen({super.key, required this.businessId});

  @override
  ConsumerState<LinePendingListScreen> createState() =>
      _LinePendingListScreenState();
}

class _LinePendingListScreenState extends ConsumerState<LinePendingListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(linePendingProvider.notifier).load(widget.businessId);
    });
  }

  /// "From date – to date."
  ///
  /// One control for both ends, because they are one question. Two separate
  /// chips invite a From later than its To, and then the list is empty for a
  /// reason the screen never explains.
  Future<void> _pickRange(BuildContext context) async {
    final state = ref.read(linePendingProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: state.from != null && state.to != null
          ? DateTimeRange(start: state.from!, end: state.to!)
          : null,
    );
    if (picked == null || !mounted) return;
    await ref
        .read(linePendingProvider.notifier)
        .setDates(widget.businessId, picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(linePendingProvider);
    final rows = state.sorted;

    return Scaffold(
      appBar: ManaAppBar(
        homeRoute: '/ow-001',
        title: ref.t('line_pending_list'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, 0),
              child: ManaFilterRail(
                filters: [
                  // The document's four, in its order: dates, minimum balance,
                  // pending periods, then sort.
                  _DateChip(
                    from: state.from,
                    to: state.to,
                    onTap: () => _pickRange(context),
                    onClear: () => ref
                        .read(linePendingProvider.notifier)
                        .setDates(widget.businessId, null, null),
                  ),
                  ManaFilterChip<int>(
                    label: ref.t('min_balance'),
                    value: state.minBalance,
                    active: state.minBalance > 0,
                    // "Eg. 0, 500, 5000" -- the document's own three, plus one
                    // step between them. These are a line's round numbers, not
                    // a scale somebody derived.
                    options: [
                      ManaFilterOption(0, ref.t('any_amount')),
                      ManaFilterOption(500, manaRupees(500)),
                      ManaFilterOption(1000, manaRupees(1000)),
                      ManaFilterOption(5000, manaRupees(5000)),
                    ],
                    onChanged: (v) => ref
                        .read(linePendingProvider.notifier)
                        .setMinBalance(widget.businessId, v),
                  ),
                  ManaFilterChip<int>(
                    label: ref.t('pending_periods'),
                    value: state.minPeriods,
                    active: state.minPeriods > 0,
                    // "Eg. Last 10weeks/Last 3Months." A bare count, because
                    // the unit belongs to the loan -- ten on a weekly loan is
                    // ten weeks, on a monthly one ten months. Mixing both in
                    // one list and filtering on the count is the honest
                    // behaviour: an Owner asking for "10 pending" wants
                    // everybody ten periods behind.
                    options: [
                      ManaFilterOption(0, ref.t('any_age')),
                      const ManaFilterOption(4, '4+'),
                      const ManaFilterOption(10, '10+'),
                      const ManaFilterOption(20, '20+'),
                    ],
                    onChanged: (v) => ref
                        .read(linePendingProvider.notifier)
                        .setMinPeriods(widget.businessId, v),
                  ),
                  ManaFilterChip<PendingSort>(
                    label: ref.t('sorted_by'),
                    value: state.sort,
                    // Sorting never hides anybody, so it is never "active" --
                    // the highlight means the list is narrowed, and a sort
                    // that lit it up would say a complete list is partial.
                    active: false,
                    options: [
                      ManaFilterOption(
                          PendingSort.lastPaid, ref.t('sort_last_paid')),
                      ManaFilterOption(
                          PendingSort.amount, ref.t('sort_amount')),
                      ManaFilterOption(
                          PendingSort.newest, ref.t('sort_newest')),
                      ManaFilterOption(
                          PendingSort.oldest, ref.t('sort_oldest')),
                      ManaFilterOption(
                          PendingSort.name, ref.t('name_field')),
                      ManaFilterOption(
                          PendingSort.villagePin, ref.t('sort_village_pin')),
                    ],
                    onChanged: (v) =>
                        ref.read(linePendingProvider.notifier).setSort(v),
                  ),
                ],
              ),
            ),
            if (rows.isNotEmpty) _TotalBar(count: rows.length, state: state),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.read(linePendingProvider.notifier).load(widget.businessId),
                child: state.loading && state.rows.isEmpty
                    ? const ManaSkeletonList(itemHeight: 96)
                    : state.error != null
                        ? ListView(children: [
                            Padding(
                              padding: const EdgeInsets.all(ManaSpacing.xxl),
                              child: Center(
                                // The message, not the exception. An Owner
                                // standing in a field can act on "pull down
                                // to try again"; they cannot act on
                                // "PostgrestException(code: PGRST203)".
                                child: ManaText.raw(
                                    ref.t('could_not_load_pull_to_retry'),
                                    style: ManaType.secondary),
                              ),
                            ),
                          ])
                        : rows.isEmpty
                            ? ListView(children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.all(ManaSpacing.xxl),
                                  child: Center(
                                    child: ManaText.raw(
                                      // A filtered empty list and a settled
                                      // book are different facts, and only one
                                      // of them is good news.
                                      state.isNarrowed
                                          ? ref.t('no_rows_for_filters')
                                          : ref.t('nothing_pending'),
                                      style: ManaType.secondary,
                                    ),
                                  ),
                                ),
                              ])
                            : ListView.separated(
                                padding: const EdgeInsets.all(ManaSpacing.lg),
                                itemCount: rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: ManaSpacing.sm),
                                itemBuilder: (context, i) =>
                                    _PendingCard(row: rows[i]),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The date range, as its own chip because it opens a picker rather than a
/// menu. Clearing it is a separate tap: a range is the one filter with no
/// natural "all" option inside the picker.
class _DateChip extends ConsumerWidget {
  final DateTime? from;
  final DateTime? to;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateChip({
    required this.from,
    required this.to,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = from != null && to != null;
    return InputChip(
      // ManaText.raw, NOT ManaFitText. A Chip measures its label with a dry
      // layout and ManaFitText is a LayoutBuilder, which cannot be dry-laid --
      // "The _RenderLayoutBuilder class does not support dry layout", and the
      // whole rail fails to render rather than degrading. Nothing here needs
      // shrinking anyway: the longest this ever reads is "01 May – 17 Sep".
      label: ManaText.raw(
        set
            ? '${DateFormat('dd MMM').format(from!)} – '
                '${DateFormat('dd MMM').format(to!)}'
            : ref.t('all_dates'),
      ),
      avatar: const Icon(Icons.date_range_outlined, size: 16),
      selected: set,
      onPressed: onTap,
      onDeleted: set ? onClear : null,
    );
  }
}

class _TotalBar extends ConsumerWidget {
  final int count;
  final LinePendingState state;
  const _TotalBar({required this.count, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, 0),
      // Wrap, not Row: the count and the total are two independent strings
      // and at 2.0x in Telugu they do not share a line. A Row here would be
      // the fixed-child-beside-flexible shape this project keeps shipping.
      child: Wrap(
        spacing: ManaSpacing.sm,
        runSpacing: ManaSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ManaText.raw('$count', style: ManaType.heavy),
          ManaText.raw(ref.t('total_outstanding'), style: ManaType.secondary),
          ManaAmount(state.totalOutstanding, size: ManaAmountSize.compact),
        ],
      ),
    );
  }
}

class _PendingCard extends ConsumerWidget {
  final PendingLoanRow row;
  const _PendingCard({required this.row});

  /// One overdue period in the loan's own unit. A Daily loan 205 periods
  /// behind is 205 days, not 205 weeks, and the difference is a factor of
  /// seven on the one number this screen exists to rank by.
  String _overdue(WidgetRef ref) => ref
      .t('periods_overdue')
      .replaceAll('{n}', '${row.periodsOverdue}')
      .replaceAll(
          '{unit}',
          ref.t(switch (row.repaymentType) {
            'Daily' => 'unit_days',
            'Monthly' => 'unit_months',
            _ => 'unit_weeks',
          }));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = [
      if (row.careOf.isNotEmpty) 'C/o ${row.careOf}',
      if (row.village.isNotEmpty)
        row.pinCode.isNotEmpty ? '${row.village} – ${row.pinCode}' : row.village,
    ].join(' · ');

    return Card(
      elevation: 0,
      color: ManaColors.surfaceMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name and balance, stacked rather than opposed. The balance is
            // the reason the row exists, so it gets its own line instead of
            // competing with a long Telugu name for a 360dp width.
            ManaFitText(row.fullName, style: ManaType.heavy),
            if (identity.isNotEmpty) ...[
              const SizedBox(height: ManaSpacing.xs),
              ManaFitText(identity, style: ManaType.note),
            ],
            const SizedBox(height: ManaSpacing.sm),
            Wrap(
              spacing: ManaSpacing.sm,
              runSpacing: ManaSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ManaAmount(row.balance, size: ManaAmountSize.compact),
                ManaText.raw(
                  _overdue(ref),
                  style: TextStyle(
                    fontSize: 13,
                    // The overdue count is the only thing on this card that
                    // is a warning rather than a fact.
                    color: row.periodsOverdue > 0
                        ? ManaColors.statusWarn
                        : ManaColors.textSecondary,
                  ),
                ),
                ManaText.raw(
                  row.lastPaid == null
                      ? ref.t('never_paid')
                      : '${ref.t('last_paid')} ${_dateFmt.format(row.lastPaid!)}',
                  style: ManaType.note,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
