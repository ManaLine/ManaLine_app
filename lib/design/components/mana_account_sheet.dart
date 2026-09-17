import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'mana_amount.dart';
import 'mana_fit_text.dart';
import 'mana_text.dart';

/// One day, as the paper sheet draws it: credits on the left, debits on the
/// right, the name of the thing between them.
///
/// WHAT THIS REPLACED. Thirteen labelled figures in a wrap -- Opening BF,
/// Collections, Penalty Collected, Loan Dist., Investor Dep., Investor W/D,
/// Expenses, Cheeti Paid, Cheeti Received, Short, Excess, Difference, Closing
/// -- with no axis saying which of them was money IN and which was money OUT.
/// Reported from a handset as "it looks messey", and the Owner sent the sheet
/// their business has always used instead: page 9 of the 2024 design
/// document, a two-column daybook that totals each side and carries the
/// difference forward.
///
/// THREE ROWS ARE ALWAYS THERE, at the Owner's instruction and in their
/// order: Brought Forward, Vasool, Karchu. Everything else is added.
///
/// AND A ROW CARRYING MONEY CANNOT BE HIDDEN. That is not in the
/// instruction and it is not negotiable: if an investor put fifty thousand
/// rupees in today and the row for it was never added, a sheet that still
/// printed a Closing would be stating a total it had not counted. Optional
/// means optional to SHOW WHEN ZERO. A figure that moved appears whether
/// anybody asked for it or not, and [ManaSheetRow.alwaysWhenNonZero] is how a
/// caller says which of its rows are money rather than commentary.
class ManaAccountSheet extends StatelessWidget {
  final List<ManaSheetRow> rows;

  /// The two column headings, translated by the caller.
  ///
  /// PASSED IN, not looked up. This is design/, and the design layer does not
  /// read app state -- the same rule that keeps ManaNotificationBell in
  /// shared/ rather than here. Hardcoding "Credits" would also have put two
  /// English words on a Telugu screen.
  final String creditsLabel;
  final String debitsLabel;

  /// Drawn under the two totals. The paper sheet writes it as the next day's
  /// Brought Forward, which is what it is.
  final int closing;

  /// Optional label under the closing figure -- the paper sheet writes
  /// "(Next BF)" there.
  final String? closingNote;

  const ManaAccountSheet({
    super.key,
    required this.rows,
    required this.closing,
    required this.creditsLabel,
    required this.debitsLabel,
    this.closingNote,
  });

  /// What each side adds up to.
  ///
  /// Computed from the rows that are actually DRAWN, not from everything
  /// handed in -- a total that counts a row nobody can see is the defect this
  /// widget exists to prevent.
  static int creditsOf(Iterable<ManaSheetRow> shown) =>
      shown.where((r) => r.isCredit).fold(0, (a, r) => a + r.amount);

  static int debitsOf(Iterable<ManaSheetRow> shown) =>
      shown.where((r) => !r.isCredit).fold(0, (a, r) => a + r.amount);

  @override
  Widget build(BuildContext context) {
    final credits = creditsOf(rows);
    final debits = debitsOf(rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeadRow(credits: creditsLabel, debits: debitsLabel),
        const Divider(height: 1),
        for (final r in rows) _Row(row: r),
        const Divider(height: 1),
        _TotalRow(credits: credits, debits: debits),
        const SizedBox(height: ManaSpacing.xs),
        _ClosingRow(closing: closing, note: closingNote),
      ],
    );
  }
}

/// One line of the sheet.
class ManaSheetRow {
  /// What it is called, in the words the business uses.
  final String label;

  /// Whole rupees. Always positive -- which SIDE it falls on is [isCredit],
  /// not the sign. A negative credit and a positive debit are the same thing
  /// written two ways, and a sheet that allowed both would be unreadable.
  final int amount;

  final bool isCredit;

  /// Tapping it does something -- add an expense, open the day's collections.
  /// Null for a row that is only a figure.
  final VoidCallback? onTap;

  /// This row is money, so it must be drawn whenever it is non-zero, whether
  /// or not anybody chose to show it. False for a row that is commentary on
  /// another row rather than a movement of its own -- Vaddi and the
  /// processing fee, which re-express Karchu rather than adding to it.
  final bool alwaysWhenNonZero;

  /// Draw it in the warning tone. For Short and Excess, which are not wrong
  /// but are always worth a second look.
  final bool caution;

  const ManaSheetRow({
    required this.label,
    required this.amount,
    required this.isCredit,
    this.onTap,
    this.alwaysWhenNonZero = true,
    this.caution = false,
  });
}

class _HeadRow extends StatelessWidget {
  final String credits;
  final String debits;
  const _HeadRow({required this.credits, required this.debits});

  @override
  Widget build(BuildContext context) {
    Widget head(String s, TextAlign align) => Expanded(
          child: ManaText.raw(s,
              textAlign: align,
              style: ManaType.note.copyWith(fontWeight: FontWeight.w700)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xs),
      child: Row(
        children: [
          head(credits, TextAlign.left),
          const Spacer(),
          head(debits, TextAlign.right),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final ManaSheetRow row;
  const _Row({required this.row});

  @override
  Widget build(BuildContext context) {
    final figure = ManaAmount(
      row.amount,
      size: ManaAmountSize.compact,
      tone: row.caution ? ManaAmountTone.caution : ManaAmountTone.neutral,
      semanticLabel: row.label,
    );

    final body = LayoutBuilder(builder: (context, constraints) {
      // MEASURED, NOT ASSUMED. The first version of this row used two fixed
      // 92dp columns and overflowed by 34 pixels at 2.0x in Telugu -- a
      // fixed-width child beside a flexible one, which is the shape this
      // project has shipped five times and caught here only because the
      // layout tests run at four scales in two languages.
      //
      // At 2.0x a compact figure is 32sp: two of them plus a label simply do
      // not fit a 360dp row, and no column width makes them. So the row
      // stacks instead, the same answer ManaMoneyRow reached for the same
      // reason -- and it keeps the side, because which side a line falls on
      // is the whole information a two-column sheet carries.
      final painter = TextPainter(
        text: TextSpan(
          text: manaRupees(row.amount),
          style: TextStyle(
              fontSize: ManaAmountSize.compact.fontSize,
              fontWeight: ManaAmountSize.compact.weight),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();

      // Two figure columns plus something readable left for the label.
      final column = painter.width + ManaSpacing.sm;
      final stack = column * 2 + 64 > constraints.maxWidth;

      if (stack) {
        return Column(
          crossAxisAlignment: row.isCredit
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            ManaFitText(row.label,
                textAlign: row.isCredit ? TextAlign.left : TextAlign.right),
            figure,
          ],
        );
      }

      return Row(
        children: [
          SizedBox(
            width: column,
            child: row.isCredit
                ? Align(alignment: Alignment.centerLeft, child: figure)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.xs),
              child: ManaFitText(row.label, textAlign: TextAlign.center),
            ),
          ),
          SizedBox(
            width: column,
            child: row.isCredit
                ? const SizedBox.shrink()
                : Align(alignment: Alignment.centerRight, child: figure),
          ),
        ],
      );
    });

    final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xs),
      child: body,
    );
    if (row.onTap == null) return padded;
    return InkWell(onTap: row.onTap, child: padded);
  }
}

class _TotalRow extends StatelessWidget {
  final int credits;
  final int debits;
  const _TotalRow({required this.credits, required this.debits});

  @override
  Widget build(BuildContext context) {
    // STANDARD, where every row above is compact. ManaAmount owns its own
    // text style and takes no override -- deliberately, so money cannot be
    // set below its floor -- so the totals separate themselves by SIZE
    // rather than by a weight passed in from here.
    Widget total(int v) => ManaAmount(v,
        size: ManaAmountSize.standard, semanticLabel: 'Total');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xs),
      child: LayoutBuilder(builder: (context, constraints) {
        // AND THE TOTALS STACK TOO. Flexible does not save this line: it
        // hands the child a maximum, and ManaAmount does not wrap, so it
        // overflows rather than shrinking. That is what put 42 pixels over
        // the edge of a 296dp card at 2.0x -- two 36sp figures on one row --
        // and it is the same mistake the sheet's own rows make if they are
        // not measured.
        final painter = TextPainter(
          text: TextSpan(
            text: manaRupees(credits > debits ? credits : debits),
            style: TextStyle(
                fontSize: ManaAmountSize.standard.fontSize,
                fontWeight: ManaAmountSize.standard.weight),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        if (painter.width * 2 + ManaSpacing.sm > constraints.maxWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: total(credits)),
              Align(alignment: Alignment.centerRight, child: total(debits)),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [total(credits), total(debits)],
        );
      }),
    );
  }
}

class _ClosingRow extends StatelessWidget {
  final int closing;
  final String? note;
  const _ClosingRow({required this.closing, this.note});

  @override
  Widget build(BuildContext context) {
    final figure = ManaAmount(closing, semanticLabel: note ?? 'Closing');

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: ManaSpacing.sm, vertical: ManaSpacing.xs),
      decoration: BoxDecoration(
        color: ManaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        // THE ONE THAT ACTUALLY OVERFLOWED, and the reason is worth keeping:
        // Expanded on the label does NOT save this line. At 2.0x the closing
        // figure is 36sp, and "Rs 3,04,260" at 36sp is wider than a 296dp
        // card on its own -- so squeezing the note to nothing still leaves
        // the amount over the edge. 42 pixels, on the day's most important
        // number.
        //
        // Measured and stacked, like the rows and the totals above. Shrinking
        // it was the other option and is the wrong one: this is the figure
        // the sheet exists to produce and the one tomorrow opens on.
        final painter = TextPainter(
          text: TextSpan(
            text: manaRupees(closing),
            style: TextStyle(
                fontSize: ManaAmountSize.standard.fontSize,
                fontWeight: ManaAmountSize.standard.weight),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final label = ManaFitText(note ?? '', style: ManaType.note, maxLines: 1);
        // Room for the figure and something readable beside it.
        if (painter.width + 48 > constraints.maxWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [label, figure],
          );
        }
        return Row(
          children: [Expanded(child: label), figure],
        );
      }),
    );
  }
}
