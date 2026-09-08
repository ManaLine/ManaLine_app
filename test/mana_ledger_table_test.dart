// Tests for ManaLedgerTable, the desktop ledger spread (Plan 2a Task 3).
//
// What matters here is not "does a table render" but the three things the
// design brief calls out as correctness properties, not style: numeric
// columns line up in tabular figures and right-align, the table -- not the
// page -- absorbs horizontal overflow, and the layout survives real widths
// without the overflow bug class this codebase has shipped four times.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_ledger_table.dart';
import 'package:mana_line/design/components/mana_text.dart';

import 'support/mana_harness.dart';

const _columns = [
  ManaLedgerColumn(label: 'Date', flex: 1),
  ManaLedgerColumn(label: 'Description', flex: 3),
  ManaLedgerColumn(label: 'Amount', flex: 1, numeric: true),
];

List<List<Widget>> _rows(int count) => [
      for (var i = 0; i < count; i++)
        [
          ManaText.raw('12/0$i'),
          ManaText.raw('Collection from a fairly long customer name $i'),
          ManaText.raw('${(i + 1) * 1000}'),
        ],
    ];

Widget _hostedTable({
  required List<List<Widget>> rows,
  double? width,
  double? height,
}) {
  final table = ManaLedgerTable(columns: _columns, rows: rows);
  final sized = (width == null && height == null)
      ? table
      : SizedBox(width: width, height: height, child: table);
  return MaterialApp(
    home: Scaffold(body: sized),
  );
}

void main() {
  group('ManaLedgerTable', () {
    testWidgets('every column header renders', (tester) async {
      await tester.pumpWidget(_hostedTable(rows: _rows(2)));
      await tester.pumpAndSettle();

      for (final column in _columns) {
        expect(
          find.text(column.label),
          findsOneWidget,
          reason: '${column.label} header should render exactly once',
        );
      }
    });

    testWidgets('numeric cell right-aligns, text cell does not', (tester) async {
      await tester.pumpWidget(_hostedTable(rows: _rows(1)));
      await tester.pumpAndSettle();

      // Header cells: Date (text) vs Amount (numeric).
      final dateHeaderAlign = tester.widget<Align>(
        find.ancestor(of: find.text('Date'), matching: find.byType(Align)).first,
      );
      final amountHeaderAlign = tester.widget<Align>(
        find.ancestor(of: find.text('Amount'), matching: find.byType(Align)).first,
      );
      expect(dateHeaderAlign.alignment, Alignment.centerLeft);
      expect(amountHeaderAlign.alignment, Alignment.centerRight);

      // Data cells: the description cell (text) vs the amount cell (numeric).
      final descriptionAlign = tester.widget<Align>(
        find
            .ancestor(
              of: find.text('Collection from a fairly long customer name 0'),
              matching: find.byType(Align),
            )
            .first,
      );
      final amountCellAlign = tester.widget<Align>(
        find.ancestor(of: find.text('1000'), matching: find.byType(Align)).first,
      );
      expect(descriptionAlign.alignment, Alignment.centerLeft);
      expect(amountCellAlign.alignment, Alignment.centerRight);

      // And the numeric cell carries tabular figures, forced by the table
      // itself rather than left to the caller to remember.
      final numericStyle = DefaultTextStyle.of(
        tester.element(find.text('1000')),
      ).style;
      expect(
        numericStyle.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('lays out without overflow at phone, tablet and desk widths',
        (tester) async {
      await pumpAtWidths(
        tester,
        _hostedTable(rows: _rows(15), height: 700),
        (width) async {
          expectNoLayoutFault(tester, 'ManaLedgerTable at width $width');
        },
      );
    });

    testWidgets(
      'the table scrolls horizontally in its own box; the page does not',
      (tester) async {
        final pageController = ScrollController();
        addTearDown(pageController.dispose);

        // A viewport far narrower than three real columns need, so the
        // spread cannot fit -- exactly the case this requirement guards.
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                controller: pageController,
                scrollDirection: Axis.horizontal,
                // Pinning the child to the viewport width is the honest
                // model of "the page" here: nothing widens this box, so if
                // the table were leaking its own horizontal overflow onto
                // the page, this SizedBox would force a RenderFlex overflow
                // rather than silently scrolling with it.
                child: SizedBox(
                  width: 390,
                  height: 700,
                  child: ManaLedgerTable(columns: _columns, rows: _rows(10)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // The table's own horizontal scroll view exists and has somewhere
        // to scroll to, because the columns do not fit at 390.
        final tableScrollable = tester.widget<Scrollable>(
          find
              .descendant(
                of: find.byType(ManaLedgerTable),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tableScrollable.axisDirection, AxisDirection.right);

        final tableScrollableState = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ManaLedgerTable),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          tableScrollableState.position.maxScrollExtent,
          greaterThan(0),
          reason: 'the table itself must have room to scroll sideways',
        );

        // The page's own scroll view -- the thing standing in for "the
        // page must never scroll sideways" -- gained no extent from it.
        expect(
          pageController.position.maxScrollExtent,
          0,
          reason: "the page's own scroll extent must not grow because of "
              'the table scrolling inside its own container',
        );
      },
    );
  });
}
