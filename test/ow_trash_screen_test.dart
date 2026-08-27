import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_trash_screen.dart';
import 'package:mana_line/shared/soft_delete_service.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// The Owner's Trash, where the only irreversible action in the app lives.
///
/// Two things are worth holding still here, and neither is cosmetic:
///
///   A plain tap must not select. Selection starts on LONG press, because
///   the toolbar action that appears alongside a selection destroys records
///   and the primary gesture on this screen has to stay harmless.
///
///   Select All must not exist before a selection does. Offering it to
///   somebody who has selected nothing is one tap away from emptying the bin.
List<DeletedRecord> _bin() => [
      DeletedRecord(
        entity: null,
        entityWireName: 'collection',
        recordId: 'r1',
        label: 'Collection MLRC0000123456',
        amount: 12845,
        businessDate: DateTime(2026, 8, 20),
        deletedAt: DateTime(2026, 8, 26, 18, 30),
        deletedBy: 'Karri Siri Manikanta Reddy',
        reason: 'Entered against the wrong customer.',
        daysLeft: 29,
      ),
      DeletedRecord(
        entity: null,
        entityWireName: 'loan',
        recordId: 'r2',
        label: 'Loan LN-MIG-20260822-046336',
        amount: 600000,
        businessDate: DateTime(2026, 8, 22),
        deletedAt: DateTime(2026, 8, 25, 9, 0),
        deletedBy: 'Karri Siri Manikanta Reddy',
        reason: null,
        // Nearly swept: the row that should read as urgent.
        daysLeft: 2,
      ),
    ];

void main() {
  Widget screen() => const OwnerTrashScreen(businessId: 'b1');

  List<Override> overrides() => [
        recentDeletesProvider('b1').overrideWith((ref) async => _bin()),
      ];

  testWidgets('a plain tap selects nothing', (tester) async {
    await pumpManaScreen(tester, screen(), overrides: overrides());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Collection MLRC').first,
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('Selected'), findsNothing,
        reason: 'tapping must not begin a selection on a screen whose other '
            'action cannot be undone');
    expect(find.text('Select All'), findsNothing,
        reason: 'Select All before any selection is one tap from emptying the bin');
  });

  testWidgets('a long press starts a selection and offers Select All',
      (tester) async {
    await pumpManaScreen(tester, screen(), overrides: overrides());
    await tester.pumpAndSettle();

    await tester.longPress(find.textContaining('Collection MLRC').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('1 Selected'), findsWidgets);
    expect(find.text('Select All'), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever_outlined), findsOneWidget,
        reason: 'the destructive action appears only alongside a selection');
  });

  testWidgets('Select All takes everything, and clears back', (tester) async {
    await pumpManaScreen(tester, screen(), overrides: overrides());
    await tester.pumpAndSettle();

    await tester.longPress(find.textContaining('Collection MLRC').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 of 2 selected'), findsWidgets);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected'), findsNothing);
  });

  testWidgets('delete forever asks first, and names what a loan takes',
      (tester) async {
    await pumpManaScreen(tester, screen(), overrides: overrides());
    await tester.pumpAndSettle();

    // Select the LOAN, which is the row whose purge cascades.
    await tester.longPress(find.textContaining('Loan LN-MIG').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_forever_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'destroying records must be confirmed, never immediate');
    expect(find.textContaining('cannot be undone'), findsWidgets);
    expect(find.textContaining('collections, schedule and penalties'),
        findsWidgets,
        reason: 'a loan takes its children with it, and the person agreeing '
            'is entitled to know that before agreeing');
  });

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('Trash survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(tester, screen(),
            textScale: scale, language: lang, overrides: overrides());
        await tester.pumpAndSettle();
        expectNoLayoutFault(tester, 'Trash at ${scale}x$tag');
      });

      testWidgets('Trash selecting survives text scale ${scale}x$tag',
          (tester) async {
        // The selection bar and the checkboxes are extra width on every row.
        await pumpManaScreen(tester, screen(),
            textScale: scale, language: lang, overrides: overrides());
        await tester.pumpAndSettle();
        await tester.longPress(find.textContaining('Collection MLRC').first);
        await tester.pumpAndSettle();
        expectNoLayoutFault(tester, 'Trash selecting at ${scale}x$tag');
      });
    }
  }
}
