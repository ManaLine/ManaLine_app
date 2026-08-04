import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/soft_delete_service.dart';
import 'package:mana_line/shared/widgets/confirm_delete_dialog.dart';

import 'support/mana_harness.dart';

/// Two new surfaces, so two new chances for the overflow bug this repo has
/// now shipped five times.
///
/// The delete dialog is the riskier one: two full sentences of warning
/// copy, a title Row carrying an icon beside translated text, and a
/// Cancel/Delete action pair — the exact shape that overflowed in the
/// expense sheet at 1.6x.
void main() {
  Widget dialog({bool affectsBalances = true}) => Scaffold(
        body: ConfirmDeleteDialog(
          entity: DeletableEntity.collection,
          recordId: '00000000-0000-0000-0000-000000000000',
          // A real receipt label with a real amount: the longest thing this
          // dialog actually renders.
          description: 'Collection RCT-20260804-a1b2c3 — ₹12,500',
          affectsBalances: affectsBalances,
        ),
      );

  for (final scale in kManaTextScales) {
    testWidgets('Delete warning survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(tester, dialog(), textScale: scale);
      expectNoLayoutFault(tester, 'ConfirmDeleteDialog at ${scale}x');
    });
  }

  testWidgets('the balance-change warning is shown for ledger records',
      (tester) async {
    await pumpManaScreen(tester, dialog());
    // This sentence is the whole reason the dialog exists: a delete moves a
    // day's closing balance. If it ever stops rendering, the user is
    // agreeing to something they were not told.
    expect(find.textContaining('closing balance'), findsOneWidget);
    expect(find.textContaining('restored for 30 days'), findsOneWidget);
  });

  testWidgets('non-financial records do not claim balances move',
      (tester) async {
    await pumpManaScreen(tester, dialog(affectsBalances: false));
    expect(find.textContaining('closing balance'), findsNothing);
    // The recovery promise still applies to everything.
    expect(find.textContaining('restored for 30 days'), findsOneWidget);
  });

  testWidgets('every server-side entity name is mapped', (tester) async {
    // app.soft_delete_record accepts a closed set and raises 22023 on
    // anything else, so a name that drifts here is a delete that always
    // fails. Round-trip every value through the wire mapping.
    for (final e in DeletableEntity.values) {
      expect(DeletableEntity.fromWire(e.wireName), e,
          reason: '${e.name} does not round-trip through its wire name');
    }
    expect(DeletableEntity.fromWire('not_a_real_entity'), isNull);
  });
}
