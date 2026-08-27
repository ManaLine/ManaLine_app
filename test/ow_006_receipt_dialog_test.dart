import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_006_collection_mode.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// The receipt. The last of the seventeen AlertDialogs that took
/// `scrollable: true` in a sweep with nothing opening them.
///
/// It only exists after a collection has SAVED, which is why it stayed
/// unproven: reaching it means getting a real write to succeed. The notifier
/// is faked to return a saved outcome, which is the smallest honest way in --
/// the alternative is not testing the one dialog that tells somebody money
/// was taken.
///
/// The figures are deliberately large. A receipt number, a rupee amount and a
/// new balance on three lines is exactly the shape that stops fitting, and
/// this is what an Agent reads back at the door.
class _FakeCollectionNotifier extends CollectionModeNotifier {
  @override
  CollectionModeState build() => const CollectionModeState();

  @override
  Future<RecordCollectionOutcome?> recordCollection({
    required String loanId,
    required String customerId,
    required int collectedAmount,
    required String payerType,
    String? payerName,
    String? guarantorId,
    required List<PaymentSplit> paymentSplits,
    required String businessDate,
    required String businessId,
    String? excessDisposition,
    String? remarks,
    bool confirmDuplicate = false,
    String? idempotencyKey,
  }) async =>
      RecordCollectionOutcome.saved(CollectionResult(
        receiptNumber: 'MLRC0000123456',
        resultType: 'Excess',
        collectedAmount: 1284500,
        newOutstandingBalance: 0,
        businessDate: DateTime(2026, 8, 27),
      ));
}

void main() {
  final row = CollectionDueRow(
    loanId: 'l1',
    customerId: 'c1',
    customerName: 'Nagabhushanam Venkata Subba Reddy',
    village: 'Srikalahasti — Uranduru Colony',
    loanNumber: 'MLLN0000098765',
    mlid: 'MLCU0000012345',
    installmentDue: 12845,
    installmentAmount: 12845,
    outstandingBalance: 1284500,
    lineRepaymentIndex: 12,
    collectionStatus: 'Pending',
    collectionAgent: 'm1',
  );

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';

      testWidgets('OW-006 receipt dialog survives ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          Scaffold(
            body: ManaCollectionForm(
              row: row,
              businessId: 'b1',
              onCancel: () {},
            ),
          ),
          textScale: scale,
          language: lang,
          overrides: [
            collectionModeProvider.overrideWith(_FakeCollectionNotifier.new),
          ],
        );
        await tester.pumpAndSettle();

        // The amount field opens on the instalment, so the button is already
        // live; typing keeps this honest about what is being recorded.
        final amount = find.byType(TextField).first;
        await tester.enterText(amount, '1284500');
        await tester.pumpAndSettle();

        final submit = find.byType(ElevatedButton);
        expect(submit, findsWidgets, reason: 'no submit button on the form');
        await tester.ensureVisible(submit.first);
        await tester.pumpAndSettle();
        await tester.tap(submit.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'the receipt did not open — the collection did not land');
        expect(find.textContaining('MLRC0000123456'), findsWidgets,
            reason: 'the receipt must show the receipt number');
        expectNoLayoutFault(tester, 'OW-006 receipt at ${scale}x$tag');
      });
    }
  }
}
