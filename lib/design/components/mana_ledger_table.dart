/// The desktop ledger spread — Plan 2a's signature element.
///
/// On a phone MANA LINE is a sequence: one row at a time, because a collector
/// standing at a doorstep can hold one thing. A desk gives back what the
/// phone had to take away — simultaneity — and the artifact that already
/// solved this for these businesses is a hand-written lending ledger: a
/// ruled spread showing many rows at once, with the rupee column aligned so
/// the eye can run down it and add by sight. This widget is that spread, not
/// a generic data grid: rules instead of cards, no zebra striping, and a
/// rupee column that is genuinely aligned rather than merely right-adjusted.
///
/// TABULAR FIGURES ARE A CORRECTNESS PROPERTY HERE, NOT A STYLE CHOICE. A
/// column whose digits do not line up cannot be scanned or added by eye, and
/// a misread figure is the failure this project treats as worse than a
/// crash (see CLAUDE.md's money-correctness rule). Every numeric column gets
/// `FontFeature.tabularFigures()` merged onto whatever the caller placed in
/// the cell via `DefaultTextStyle.merge`, so a plain [ManaText] figure lines
/// up exactly the same as a [ManaLedgerAmount] or [ManaAmount] without the
/// caller opting in — this is a strong default, not an enforced guarantee.
/// `TextStyle.merge` lets the *cell's own* non-null fields win over the
/// ambient style it is merged onto, so a cell can still defeat it: setting
/// its own explicit `fontFeatures` (including an empty list), setting
/// `style.inherit = false`, or building a raw `RichText`/`CustomPaint` that
/// never reads `DefaultTextStyle.of(context)` at all. None of these raise an
/// error — the digits just silently stop lining up. Today's only cell
/// content ([ManaText]/[ManaAmount]/[ManaLedgerAmount]) does none of these,
/// but a future cell widget is not stopped from doing so by this mechanism.
///
/// PURE LAYOUT, ON PURPOSE. This widget takes rows already built by the
/// caller and knows nothing about ledgers, money rules or dates — it never
/// imports `LedgerEvent` or a money type. That boundary is what lets OW-017
/// (Owner) and AG-010 (Agent) share this table in the next task without
/// sharing behaviour: each screen decides what a row means, this widget only
/// decides where it sits.
library;

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'mana_text.dart';

/// One column of the spread: a header label, a share of the row's width, and
/// whether it carries money (right-aligned, tabular) or text (left-aligned).
class ManaLedgerColumn {
  final String label;

  /// Share of the table's total width, in the same proportional sense as
  /// [Expanded]'s flex — a column with flex 2 is twice as wide as one with
  /// flex 1. Not required to sum to any particular total.
  final double flex;

  /// True for a rupee column: right-aligned, tabular figures. False (the
  /// default) for a text column: left-aligned, no forced figure width.
  final bool numeric;

  const ManaLedgerColumn({
    required this.label,
    required this.flex,
    this.numeric = false,
  });
}

/// Baseline width per unit of [ManaLedgerColumn.flex]. Three [ManaSpacing.xxl]
/// steps (96px) is the minimum a single-flex column needs to hold a rupee
/// figure or a short label without wrapping at desk font sizes — one `xxl`
/// reads as cramped for that, two is tight, three is comfortable; it is not
/// itself an on-scale spacing token, just built from one. This is what
/// decides when the spread must scroll: on a narrow window the columns'
/// combined minimum width exceeds the viewport and the table scrolls
/// sideways in its own box; on a desk-wide window the columns stretch to
/// fill the space instead.
const double _kColumnFlexUnit = ManaSpacing.xxl * 3;

/// A ledger spread: a header row and data rows, ruled by hairlines, with the
/// numeric columns right-aligned in tabular figures.
///
/// [rows] are pre-built by the caller, one list of cell widgets per row,
/// positional against [columns]. [dayHeaders], if supplied, must be the same
/// length as [rows]; `dayHeaders[i]` (which may be an empty widget such as
/// `SizedBox.shrink()`) is placed as a full-width band directly above
/// `rows[i]`. This widget does not decide when a day boundary falls — it
/// only places whatever the caller handed it, which is what keeps it free of
/// ledger knowledge.
class ManaLedgerTable extends StatelessWidget {
  final List<ManaLedgerColumn> columns;
  final List<List<Widget>> rows;
  final List<Widget>? dayHeaders;

  /// Optional controller for the table's own internal (vertical) list.
  ///
  /// Layout-only, same as everything else here: this widget does not read
  /// scroll position or decide when to page. A caller that also drives
  /// pagination off a [ScrollController] (see `ManaLedgerHistoryView`) can
  /// hand the SAME controller instance here and to whatever other
  /// Scrollable it swaps in/out in its place, so one listener and one
  /// threshold check keep working regardless of which Scrollable currently
  /// has the controller attached. Never attach one controller to two
  /// concurrently-mounted Scrollables -- that is a Flutter framework error,
  /// not something this widget can guard against.
  final ScrollController? scrollController;

  const ManaLedgerTable({
    super.key,
    required this.columns,
    required this.rows,
    this.dayHeaders,
    this.scrollController,
  });

  double get _totalFlex => columns.fold<double>(0, (sum, c) => sum + c.flex);

  /// A hairline rule, not a card border — the table is one ruled object, not
  /// a stack of cards. Reused between every row and under the header.
  Widget _rule() => Container(height: 1, color: ManaColors.divider);

  Widget _cell(ManaLedgerColumn column, double width, Widget child) {
    final content = column.numeric
        // Merged onto whatever the caller put in the cell -- a plain
        // ManaText figure lines up like a ManaLedgerAmount without the call
        // site opting in. This is a strong default, not an enforced one: a
        // cell that sets its own fontFeatures/inherit=false, or a raw
        // RichText that never reads DefaultTextStyle, can still defeat it
        // silently (see the class doc comment).
        ? DefaultTextStyle.merge(
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            child: child,
          )
        : child;
    return SizedBox(
      width: width,
      child: Align(
        alignment: column.numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: content,
      ),
    );
  }

  Widget _rowOf(List<Widget> cells, List<double> widths) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ManaSpacing.lg,
        vertical: ManaSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) const SizedBox(width: ManaSpacing.md),
            _cell(columns[i], widths[i], i < cells.length ? cells[i] : const SizedBox.shrink()),
          ],
        ],
      ),
    );
  }

  Widget _headerRow(List<double> widths) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ManaSpacing.lg,
        vertical: ManaSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) const SizedBox(width: ManaSpacing.md),
            SizedBox(
              width: widths[i],
              child: Align(
                alignment:
                    columns[i].numeric ? Alignment.centerRight : Alignment.centerLeft,
                child: ManaText(
                  columns[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ManaType.smallStrong.copyWith(color: ManaColors.textSecondary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      dayHeaders == null || dayHeaders!.length == rows.length,
      'dayHeaders must have one entry per row (use SizedBox.shrink() where none is wanted)',
    );

    final totalFlex = _totalFlex == 0 ? 1 : _totalFlex;
    final gaps = ManaSpacing.md * (columns.length - 1) + ManaSpacing.lg * 2;

    return LayoutBuilder(
      builder: (context, outer) {
        final minContentWidth = totalFlex * _kColumnFlexUnit + gaps;
        // Stretch to fill a wide window; on a narrow one, keep the minimum
        // the columns need and let the table -- not the page -- scroll for
        // the difference.
        final tableWidth = outer.maxWidth.isFinite
            ? (minContentWidth > outer.maxWidth ? minContentWidth : outer.maxWidth)
            : minContentWidth;
        final availableForColumns = tableWidth - gaps;
        final widths = [
          for (final c in columns) availableForColumns * (c.flex / totalFlex),
        ];

        final body = <Widget>[];
        for (var i = 0; i < rows.length; i++) {
          if (i > 0) body.add(_rule());
          final header = dayHeaders != null ? dayHeaders![i] : null;
          if (header != null) body.add(header);
          body.add(_rowOf(rows[i], widths));
        }

        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerRow(widths),
            _rule(),
            // A bounded ancestor (the caller placed this table inside an
            // Expanded, a SizedBox, etc.) lets the header stay put while the
            // body scrolls vertically beneath it -- the "sticky at the top
            // of the scroll area" requirement. Without one, Expanded would
            // throw ("unbounded height"), so the body falls back to a plain
            // Column and the surrounding page scrolls the whole spread
            // instead of crashing.
            if (outer.hasBoundedHeight)
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: body,
                ),
              )
            else
              ...body,
          ],
        );

        // The table scrolls horizontally inside its own box; the page around
        // it must never gain sideways scroll extent from this widget, so the
        // horizontal Scrollable is created and consumed entirely here.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: tableWidth, child: content),
        );
      },
    );
  }
}
