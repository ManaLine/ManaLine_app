import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/import_screen.dart';

import 'support/mana_harness.dart';

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('Import survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const ImportScreen(businessId: 'b1'),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'Import at ${scale}x');

      // The all-or-nothing warning is the sentence that tells an Owner what to
      // do when the import fails, so it must survive scaling rather than being
      // the thing that overflows.
      expect(find.textContaining('nothing is imported'), findsOneWidget);
    });
  }

  testWidgets('all three steps are present on a surface that fits them',
      (tester) async {
    // On 360x640 the later steps fall below the fold and a lazy ListView never
    // builds them — so content is asserted where it all lays out.
    await pumpManaScreen(
      tester,
      const ImportScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 1600),
    );
    expectNoLayoutFault(tester, 'Import fully laid out');
    expect(find.text('Get Template'), findsOneWidget);
    expect(find.text('Choose File'), findsOneWidget);
  });

  testWidgets('import is not offered before a file is chosen', (tester) async {
    await pumpManaScreen(
      tester,
      const ImportScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 1600),
    );
    // Step 3 only exists once there are parsed rows; offering it earlier would
    // let someone submit nothing and read the result as a completed import.
    expect(find.text('Import'), findsNothing);
  });
}
