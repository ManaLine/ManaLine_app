import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_filter_rail.dart';

import 'support/mana_harness.dart';

/// Choosing "All" again after choosing a village.
///
/// The defect: PopupMenuButton cannot tell a selection of null from a
/// dismissed menu — its own callback reads `if (newValue == null)
/// onCanceled() else onSelected(newValue)`. Every "All" option in this app is
/// null by design (all villages, any status, any frequency), so picking
/// Panagallu left no way back to the whole round: the menu opened, All was
/// tapped, and nothing happened.
void main() {
  testWidgets('picking All after a village reports the change', (tester) async {
    String? chosen = 'Panagallu';
    var calls = 0;

    await pumpManaScreen(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: ManaFilterRail(
            filters: [
              ManaFilterChip<String?>(
                label: 'Village',
                value: chosen,
                active: chosen != null,
                options: const [
                  ManaFilterOption(null, 'All Villages · 56'),
                  ManaFilterOption('Panagallu', 'Panagallu · 12'),
                  ManaFilterOption('Srikalahasti', 'Srikalahasti · 9'),
                ],
                onChanged: (v) => setState(() {
                  chosen = v;
                  calls++;
                }),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open the chip and choose All.
    await tester.tap(find.text('Panagallu · 12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Villages · 56').last);
    await tester.pumpAndSettle();

    expect(calls, 1, reason: 'All must report, not read as a dismissal');
    expect(chosen, isNull);
    expect(find.text('All Villages · 56'), findsOneWidget,
        reason: 'the chip shows the filter it is actually applying');
  });

  testWidgets('picking a village still works', (tester) async {
    String? chosen;
    await pumpManaScreen(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: ManaFilterRail(
            filters: [
              ManaFilterChip<String?>(
                label: 'Village',
                value: chosen,
                options: const [
                  ManaFilterOption(null, 'All Villages'),
                  ManaFilterOption('Panagallu', 'Panagallu'),
                ],
                onChanged: (v) => setState(() => chosen = v),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('All Villages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Panagallu').last);
    await tester.pumpAndSettle();

    expect(chosen, 'Panagallu');
  });
}
