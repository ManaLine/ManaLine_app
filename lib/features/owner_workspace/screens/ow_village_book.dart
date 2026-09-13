import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/components/mana_amount.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/bulk_onboarding_service.dart';
import '../state/village_book_summary.dart';
import 'ow_village_customers.dart';

/// A pre-existing book, village by village.
///
/// 200 customers is not a 200-screen wall. It is a dozen villages of about
/// seventeen, one sitting each -- and an Owner entering a paper book works down
/// it village by village anyway, because that is how the book and the
/// collection round are both organised.
///
/// After each village the Owner reconciles against the page in front of them:
/// how many customers, what is still owed, and how much of that is money
/// nobody has paid in months.
class VillageBookList extends ConsumerStatefulWidget {
  final String businessId;
  const VillageBookList({super.key, required this.businessId});

  @override
  ConsumerState<VillageBookList> createState() => _VillageBookListState();
}

class _VillageBookListState extends ConsumerState<VillageBookList> {
  List<ManaLoanPosition> _positions = const [];
  bool _loading = true;

  /// Months back from today, before which a loan counts as struck. The Owner's
  /// default is six.
  int _months = kManaStruckDefaultMonths;

  /// Set when the Owner picks an exact day instead of a span.
  DateTime? _exactCutoff;

  DateTime get _cutoff =>
      _exactCutoff ?? manaStruckCutoff(months: _months);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await NetworkErrorHandler.run(context, () async {
      return ref
          .read(bulkOnboardingServiceProvider)
          .customerPositions(widget.businessId);
    });
    if (!mounted) return;
    setState(() {
      // Null is a network failure the handler has already surfaced; an empty
      // list means nothing has been entered yet. The two say different things.
      _positions = rows ?? const [];
      _loading = false;
    });
  }

  Future<void> _pickExactDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _cutoff,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _exactCutoff = picked);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final summaries = manaVillageSummaries(_positions, cutoff: _cutoff);
    if (summaries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(ManaSpacing.xxl),
        child: Center(
          child: ManaText.raw(ref.t('nothing_entered_for_this_village_yet'),
              textAlign: TextAlign.center, style: ManaType.secondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        _cutoffPicker(),
        const SizedBox(height: ManaSpacing.md),
        for (final summary in summaries) ...[
          _VillageCard(
            summary: summary,
            businessId: widget.businessId,
            onChanged: _load,
            // The rows this card was built from, handed on rather than
            // re-queried: a second round trip on a village connection to
            // redraw what is already on screen is latency for nothing.
            positions: _positions
                .where((p) =>
                    p.village == summary.village &&
                    p.inOperatingArea == summary.inOperatingArea)
                .toList(),
          ),
          const SizedBox(height: ManaSpacing.sm),
        ],
      ],
    );
  }

  Widget _cutoffPicker() => Row(
        children: [
          ManaText.raw(ref.t('not_recovered_since'), style: ManaType.note),
          const SizedBox(width: ManaSpacing.sm),
          // Flexible beside a fixed label: a Row with two unflexible children
          // is this codebase's recurring overflow shape, and the Telugu for
          // "Not recovered since" is longer than the English.
          Expanded(
            child: DropdownButton<int>(
              isExpanded: true,
              // -1 is the escape hatch, not a span. Kept out of
              // kManaStruckMonthOptions so that list stays exactly the six the
              // Owner asked for.
              value: _exactCutoff != null ? -1 : _months,
              items: [
                for (final n in kManaStruckMonthOptions)
                  DropdownMenuItem(
                    value: n,
                    child: ManaText.raw(
                        ref.t('last_n_months').replaceAll('{n}', '$n'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                DropdownMenuItem(
                  value: -1,
                  child: ManaText.raw(ref.t('choose_a_date'),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                if (v == -1) {
                  _pickExactDate();
                  return;
                }
                setState(() {
                  _months = v;
                  _exactCutoff = null;
                });
              },
            ),
          ),
        ],
      );
}

/// One village: its head count, its three figures, and a way in.
class _VillageCard extends ConsumerWidget {
  final ManaVillageSummary summary;
  final String businessId;
  final VoidCallback onChanged;
  final List<ManaLoanPosition> positions;

  const _VillageCard({
    required this.summary,
    required this.businessId,
    required this.onChanged,
    required this.positions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An out-of-area group has no village name worth showing as a heading --
    // it is a group of leftovers, and saying so is the point of it existing.
    final title = summary.inOperatingArea && summary.village.isNotEmpty
        ? summary.village
        : ref.t('not_in_any_operating_area');

    return Card(
      child: InkWell(
        // The whole card opens the village. The figures on it are what an
        // Owner reads before deciding to go in, so making only a small chevron
        // tappable would put the target somewhere other than where they are
        // already looking.
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VillageCustomersScreen(
                businessId: businessId,
                title: title,
                positions: positions,
              ),
            ),
          );
          // Entering a loan changes every figure on this card.
          onChanged();
        },
        child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ManaText.raw(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ManaType.cardTitle),
                ),
                // The count the Owner checks against the page before opening
                // the village.
                ManaText.raw(
                  ref
                      .t('customers_in_village')
                      .replaceAll('{count}', '${summary.customerCount}'),
                  style: ManaType.note,
                ),
              ],
            ),
            if (!summary.inOperatingArea) ...[
              const SizedBox(height: ManaSpacing.xs),
              // Not a failure -- a prompt. These customers are real and their
              // money counts; what is missing is the operating area.
              ManaText.raw(
                summary.village.isEmpty
                    ? ref.t('no_village_on_file')
                    : summary.village,
                style: TextStyle(color: ManaColors.statusWarn, fontSize: 12),
              ),
            ],
            const SizedBox(height: ManaSpacing.sm),
            _figure(ref, 'total_balance', summary.totalBalance, null),
            _figure(ref, 'running_amount', summary.runningBalance,
                ManaColors.statusGood),
            // struck_amount now READS "On Hold". The key keeps its name --
            // renaming a live key means a new row, a new migration and every
            // call site, for no behaviour -- but the word an Owner sees is
            // deliberately not "Struck". Struck is a judgement about the
            // person; this figure is a fact about the money, and on an
            // un-migrated book it may be an ESTIMATE from the loan's own
            // dates rather than anything collected. Same for the Dart
            // identifiers below.
            _figure(ref, 'struck_amount', summary.struckBalance,
                ManaColors.statusBad,
                // Named rather than counted: a figure an Owner cannot act on
                // is one they will ignore.
                onTap: summary.struckCustomers.isEmpty
                    ? null
                    : () => _showStruck(context, ref),
                trailingNote: summary.struckCustomers.isEmpty
                    ? null
                    : ref.t('struck_customers_note').replaceAll(
                        '{count}', '${summary.struckCustomers.length}')),
            // Says when the figure above is a GUESS. Worked out from loan due
            // dates because nothing has been collected against them in the app
            // yet -- which is the normal state of a book just typed in. A
            // struck total from collection history is a fact; this one is an
            // estimate, and they lead to the same doorstep.
            if (summary.struckIsEstimated) ...[
              const SizedBox(height: 2),
              ManaText.raw(ref.t('struck_is_estimated_note'),
                  style: TextStyle(
                      color: ManaColors.textSecondary, fontSize: 11)),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _figure(WidgetRef ref, String labelKey, int amount, Color? colour,
          {VoidCallback? onTap, String? trailingNote}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: ManaText.raw(ref.t(labelKey), style: ManaType.note)),
              if (trailingNote != null) ...[
                ManaText.raw(trailingNote, style: ManaType.note),
                const SizedBox(width: ManaSpacing.sm),
              ],
              ManaAmount.compact(amount, semanticLabel: ref.t(labelKey)),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: colour),
            ],
          ),
        ),
      );

  void _showStruck(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            ManaText.raw(ref.t('struck_amount'), style: ManaType.cardTitle),
            const SizedBox(height: ManaSpacing.sm),
            for (final who in summary.struckCustomers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: ManaText.raw(who.fullName),
                subtitle: ManaText.raw(who.mlid, style: ManaType.note),
                trailing: ManaAmount.compact(who.struckBalance,
                    semanticLabel: ref.t('struck_amount')),
              ),
          ],
        ),
      ),
    );
  }
}
