import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/backup_screen.dart';
import 'package:mana_line/features/owner_workspace/state/backup_export_service.dart';

import 'support/mana_harness.dart';

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('Backup survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const BackupScreen(businessId: 'b1'),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'Backup at ${scale}x');

      // The intro copy sits at the top of the list, so it is built at every
      // scale. It is also the longest run of text on the screen, which makes
      // it the thing most likely to overflow.
      expect(find.textContaining('Deleted records'), findsOneWidget);
    });
  }

  testWidgets('the whole screen is present once it all fits', (tester) async {
    // On 360x640 at 2.0x the button falls below the fold, and a lazy ListView
    // never builds it — so asserting it inside the scale loop above would fail
    // for a layout reason that is not a fault. Content gets its own surface.
    await pumpManaScreen(
      tester,
      const BackupScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 1400),
      textScale: 2.0,
    );
    expectNoLayoutFault(tester, 'Backup fully laid out at 2.0x');
    expect(find.text('Create Backup'), findsOneWidget);
    expect(find.textContaining('Deleted records'), findsOneWidget);
  });

  testWidgets('nothing is shareable before a backup is created',
      (tester) async {
    await pumpManaScreen(tester, const BackupScreen(businessId: 'b1'));
    // The share button appearing before a file exists would offer to send
    // nothing at all.
    expect(find.text('Share File'), findsNothing);
  });

  test('the row cap is a real bound, not a placeholder', () {
    // The screen tells the user which sheets were cut and quotes this number,
    // so a cap of zero or something absurdly large would make that message
    // either constant or meaningless.
    expect(BackupExportService.maxRowsPerSheet, greaterThan(1000));
    expect(BackupExportService.maxRowsPerSheet, lessThan(1048575));
  });
}
