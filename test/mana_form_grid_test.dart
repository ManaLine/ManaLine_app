// Tests for ManaFormGrid, the shared form-column primitive (Plan 2a Task 5).
//
// What matters: one column below medium, columnsAtMedium at or above it,
// every child present at every width, no layout fault, and an odd number of
// children does not leave a stretched orphan on the last row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_form_grid.dart';

import 'support/mana_harness.dart';

Widget _hostedGrid(List<Widget> children, {int columnsAtMedium = 2}) {
  return MaterialApp(
    home: Scaffold(
      body: ManaFormGrid(columnsAtMedium: columnsAtMedium, children: children),
    ),
  );
}

void main() {
  group('ManaFormGrid', () {
    testWidgets('one column at 390, two at 820 and 1440; every child renders at every width',
        (tester) async {
      final children = [
        for (var i = 0; i < 4; i++) SizedBox(height: 40, child: Text('field $i')),
      ];

      await pumpAtWidths(tester, _hostedGrid(children), (width) async {
        for (var i = 0; i < 4; i++) {
          expect(find.text('field $i'), findsOneWidget,
              reason: 'field $i should render at width $width');
        }
        expectNoLayoutFault(tester, 'ManaFormGrid at width $width');

        final field0X = tester.getTopLeft(find.text('field 0')).dx;
        final field1X = tester.getTopLeft(find.text('field 1')).dx;
        if (width < 600) {
          // Single column: every field starts at the same x.
          expect(field1X, field0X, reason: 'compact width should stack fields in one column');
        } else {
          // Two columns: field 1 sits to the right of field 0.
          expect(field1X, greaterThan(field0X),
              reason: 'medium/expanded width should flow fields into columns');
        }
      });
    });

    testWidgets('an odd number of children does not stretch the last row orphan',
        (tester) async {
      final children = [
        for (var i = 0; i < 3; i++) SizedBox(height: 40, child: Text('field $i')),
      ];

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_hostedGrid(children));
      await tester.pumpAndSettle();

      // Row 0: field 0 + field 1 (two columns). Row 1: field 2 alone.
      final width0 = tester.getSize(find.byType(SizedBox).at(0)).width;
      final width1 = tester.getSize(find.byType(SizedBox).at(1)).width;
      final width2 = tester.getSize(find.byType(SizedBox).at(2)).width;

      expect(width0, width1, reason: 'both children in a full row share the same width');
      expect(width2, width0,
          reason: 'the lone last-row child must keep the same width as its row-mates, '
              'not stretch to fill the row');
    });

    testWidgets('columnsAtMedium controls the column count at medium/expanded width',
        (tester) async {
      final children = [
        for (var i = 0; i < 3; i++) SizedBox(height: 40, child: Text('col $i')),
      ];

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_hostedGrid(children, columnsAtMedium: 3));
      await tester.pumpAndSettle();

      // All three in one row: strictly increasing x.
      final x0 = tester.getTopLeft(find.text('col 0')).dx;
      final x1 = tester.getTopLeft(find.text('col 1')).dx;
      final x2 = tester.getTopLeft(find.text('col 2')).dx;
      expect(x1, greaterThan(x0));
      expect(x2, greaterThan(x1));
      expectNoLayoutFault(tester, 'ManaFormGrid with columnsAtMedium: 3');
    });
  });
}
