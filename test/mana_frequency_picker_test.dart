import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_frequency_picker.dart';

import 'support/mana_harness.dart';

/// The All / Daily / Weekly / Monthly control on Collection Mode, which
/// replaced the ChoiceChip row that OW-006 and AG-002 each carried a copy of.
void main() {
  testWidgets('offers all four choices, whatever the round contains',
      (tester) async {
    await pumpManaScreen(
      tester,
      Scaffold(
        body: ManaFrequencyPicker(value: null, onChanged: (_) {}),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();

    // The chips used to hide a frequency the round did not contain. Inside a
    // closed dropdown that costs nothing, and a control that comes and goes
    // is harder to trust than one always in the same place.
    for (final label in ['All', 'Daily', 'Weekly', 'Monthly']) {
      expect(find.text(label), findsWidgets, reason: '$label must be offered');
    }
  });

  testWidgets('reports the raw repayment_type, not the translated label',
      (tester) async {
    // manaFilterDueRows compares against `loans.repayment_type`, so a
    // translated value would silently match nothing in Telugu.
    String? picked = 'unset';
    await pumpManaScreen(
      tester,
      Scaffold(
        body: ManaFrequencyPicker(value: null, onChanged: (v) => picked = v),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();

    expect(picked, 'Weekly');
  });

  testWidgets('All clears the filter back to the whole round', (tester) async {
    String? picked = 'Monthly';
    await pumpManaScreen(
      tester,
      Scaffold(
        body: ManaFrequencyPicker(value: 'Monthly', onChanged: (v) => picked = v),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();

    expect(picked, isNull);
  });
}
