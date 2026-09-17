import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/components/mana_amount.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/translation_service.dart';
import '../state/village_book_summary.dart';
import 'ow_pre_existing_loan_sheet.dart';

/// One person's pre-existing entry: who they are, what they already owe, and
/// one way to add another loan.
///
/// WHAT THIS REPLACED, AND WHY IT IS ITS OWN SCREEN. Reaching this from a
/// member row used to open the VILLAGE book with the person's name in the
/// title bar. That screen is a list, so it drew what a list draws: a search
/// icon over one row, the count line "1 Customers", and the person collapsed
/// behind a chevron you had to tap to reach the loans you came for. Reported
/// from a handset as "why showing 1 customers?" -- which is the right
/// question. The answer was that a list of one is not a person.
///
/// Passing a `single` flag into the village screen would have been the other
/// option, and it would have meant every part of that screen growing a branch
/// for a case its whole shape is wrong for. This one has no list, so it has
/// no count, no search and nothing to expand.
///
/// THE HEADER IS TWO ROWS, in the Owner's own words: the name and the MLID on
/// the first, the care-of name and the village on the second. Those four
/// fields are how somebody standing in a village is identified -- there are
/// three men called Ramesh in Someswaram and the care-of name is what
/// separates them.
class OnePersonEntryScreen extends ConsumerStatefulWidget {
  final String businessId;

  /// This person's rows as `app.migration_customer_positions` returned them:
  /// one per live loan, or a single loan-less row when they have none. Passed
  /// in rather than re-queried -- the caller has just fetched them, and a
  /// second round trip on a village connection to redraw what is already on
  /// screen is latency for nothing.
  final List<ManaLoanPosition> positions;

  /// Refetch, so a loan added here appears without leaving the screen.
  final Future<void> Function() onSaved;

  const OnePersonEntryScreen({
    super.key,
    required this.businessId,
    required this.positions,
    required this.onSaved,
  });

  @override
  ConsumerState<OnePersonEntryScreen> createState() =>
      _OnePersonEntryScreenState();
}

class _OnePersonEntryScreenState extends ConsumerState<OnePersonEntryScreen> {
  /// Whether anything was saved in this sitting, so the screen says so rather
  /// than looking identical before and after.
  bool _savedNow = false;

  ManaLoanPosition get _who => widget.positions.first;

  /// The live loans, and only those.
  ///
  /// `hasLoan` is the filter because the RPC returns a customer with NO loan
  /// as a row anyway -- that is deliberate there, so a loan-less person still
  /// has a way in -- and drawing that row as a loan would put a Rs 0 card in
  /// front of the Owner for a loan that does not exist.
  ///
  /// It does not need an "is it active" test of its own: the RPC's join
  /// carries `remaining_balance > 0`, so a settled loan never arrives here.
  List<ManaLoanPosition> get _loans =>
      widget.positions.where((p) => p.hasLoan).toList();

  Future<void> _addLoan() async {
    final saved = await manaEnterPreExistingLoan(
      context,
      ref,
      businessId: widget.businessId,
      mlid: _who.mlid,
      fullName: _who.fullName,
    );
    if (!saved || !mounted) return;
    setState(() => _savedNow = true);
    await widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final loans = _loans;
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('enter_one_by_one')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(ManaSpacing.lg,
                  ManaSpacing.lg, ManaSpacing.lg, ManaSpacing.sm),
              child: ManaText.raw(
                loans.isEmpty ? ref.t('no_loans_yet') : ref.t('active_loans'),
                style: ManaType.strong,
              ),
            ),
            Expanded(
              child: loans.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.lg),
                      itemCount: loans.length,
                      itemBuilder: (context, i) => _loanCard(loans[i]),
                    ),
            ),
            if (_savedNow)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: ManaSpacing.lg, vertical: ManaSpacing.xs),
                child: ManaText.raw(ref.t('entered_in_this_sitting'),
                    style: TextStyle(
                        color: ManaColors.statusGood, fontSize: 13)),
              ),
            // AT THE BOTTOM, asked for by name and right for the reason the
            // Owner asked: it is the one action on the screen, and the bottom
            // edge is where a thumb already is on a phone held one-handed.
            // Outside the scrolling list, so a person with six loans does not
            // have to scroll past them to reach it.
            Padding(
              padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, 0,
                  ManaSpacing.lg, ManaSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _addLoan,
                  icon: const Icon(Icons.add, size: 18),
                  label: ManaText.raw(ref.t('add_loan')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Name and MLID, then C/o and village.
  ///
  /// Each line is `Flexible` beside its fixed neighbour rather than a plain
  /// Row of two: a Telugu village name is longer than the English the layout
  /// was drawn against, and an unflexible child beside a flexible one is the
  /// overflow this project has shipped four times.
  Widget _header() {
    final careOf = _who.fatherHusbandName;
    final village = _who.village;
    final second = [
      if (careOf.isNotEmpty) '${ref.t('care_of')} $careOf',
      if (village.isNotEmpty) village,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, ManaSpacing.lg,
          ManaSpacing.lg, ManaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _nameAndMlid(),
          if (second.isNotEmpty) ...[
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(second,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ManaType.secondary),
          ],
        ],
      ),
    );
  }

  /// The name and the MLID on one line -- until they cannot both be on one.
  ///
  /// AN MLID CANNOT BE ELLIPSISED and it cannot be wrapped: it is an
  /// identifier, and "MLPI1000..." is not a shorter way of saying it, it is a
  /// different string. So it takes its intrinsic width and the name takes
  /// what is left, which is fine at 1.0x and overflowed by 21 pixels at 2.0x
  /// in Telugu -- caught by the layout test, which is the recurring bug class
  /// in this project and the reason that test exists.
  ///
  /// Measured rather than guessed, the same way ManaMoneyRow decides whether
  /// a figure still fits beside its label: when the MLID would leave the name
  /// under half the row, the pair stacks. The Owner asked for both on the
  /// first row and at every ordinary text size they are; at 2.0x the honest
  /// answer is two lines rather than a clipped name.
  Widget _nameAndMlid() {
    const nameStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    return LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context);
      final painter = TextPainter(
        text: TextSpan(text: _who.mlid, style: ManaType.note),
        textDirection: Directionality.of(context),
        textScaler: scale,
      )..layout();
      final room = constraints.maxWidth - painter.width - ManaSpacing.sm;
      final name = ManaText.raw(
        _who.fullName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: nameStyle,
      );
      final mlid = ManaText.raw(_who.mlid, style: ManaType.note);

      if (room < constraints.maxWidth / 2) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [name, const SizedBox(height: ManaSpacing.xs), mlid],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(child: name),
          const SizedBox(width: ManaSpacing.sm),
          mlid,
        ],
      );
    });
  }

  Widget _loanCard(ManaLoanPosition loan) => Card(
        margin: const EdgeInsets.only(bottom: ManaSpacing.xs),
        child: ListTile(
          title: ManaAmount.compact(loan.balance,
              semanticLabel: ref.t('remaining_balance')),
          subtitle: ManaText.raw(
            loan.lastCollection == null
                ? ref.t('no_collections_yet')
                : manaDisplayDate(loan.lastCollection),
            style: ManaType.note,
          ),
        ),
      );
}
