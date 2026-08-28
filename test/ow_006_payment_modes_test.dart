import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_006_collection_mode.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';

import 'support/mana_harness.dart';

/// What mode the money arrived in.
///
/// Every collection this app has ever recorded was written as Cash. The form
/// hardcoded `[PaymentSplit('Cash', amount)]` unless a Mixed Payment switch
/// was on, and that switch offered Cash and UPI only -- so a customer paying
/// entirely by UPI was recorded as having handed over notes, and cheque and
/// bank transfer could not be recorded at all despite payment_mode_enum
/// carrying both since it was created.
///
/// These pin the splits that actually leave the screen, because that is the
/// part a receipt and a settlement are built from.
class _CapturingNotifier extends CollectionModeNotifier {
  static List<PaymentSplit>? lastSplits;
  static int? lastAmount;

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
  }) async {
    lastSplits = paymentSplits;
    lastAmount = collectedAmount;
    return RecordCollectionOutcome.saved(CollectionResult(
      receiptNumber: 'MLRC0000000001',
      resultType: 'Partial',
      collectedAmount: collectedAmount,
      newOutstandingBalance: 0,
      businessDate: DateTime(2026, 8, 28),
    ));
  }
}

final _row = CollectionDueRow(
  loanId: 'l1',
  customerId: 'c1',
  customerName: 'Kotha Lakshmi Prasad',
  village: 'Srikalahasti',
  loanNumber: 'MLLN0000098765',
  mlid: 'MLCU0000012345',
  installmentDue: 6300,
  installmentAmount: 6300,
  outstandingBalance: 63000,
  lineRepaymentIndex: 4,
  collectionStatus: 'Pending',
  collectionAgent: 'm1',
);

Future<void> _pumpForm(WidgetTester tester) async {
  await pumpManaScreen(
    tester,
    Scaffold(
      body: SingleChildScrollView(
        child: ManaCollectionForm(
          row: _row,
          businessId: 'b1',
          onCancel: () {},
        ),
      ),
    ),
    overrides: [
      collectionModeProvider.overrideWith(_CapturingNotifier.new),
    ],
  );
  await tester.pumpAndSettle();
}

/// Opens one mode's box, types an amount and saves it.
Future<void> _enterMode(WidgetTester tester, String label, String amount) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, amount);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Save'));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  final submit = find.byType(ElevatedButton);
  await tester.ensureVisible(submit.first);
  await tester.pumpAndSettle();
  await tester.tap(submit.first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _CapturingNotifier.lastSplits = null;
    _CapturingNotifier.lastAmount = null;
  });

  testWidgets('the instalment is prefilled as Cash, and records as Cash',
      (tester) async {
    await _pumpForm(tester);
    await _submit(tester);

    expect(_CapturingNotifier.lastAmount, 6300);
    expect(_CapturingNotifier.lastSplits!.map((s) => s.paymentMode).toList(),
        ['Cash']);
    expect(_CapturingNotifier.lastSplits!.single.amount, 6300);
  });

  testWidgets('a UPI-only collection records as UPI, not as Cash',
      (tester) async {
    await _pumpForm(tester);
    // Clearing the collected amount drops the prefilled Cash, which is what
    // makes a pure-UPI entry possible at all -- the bug was that it wasn't.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await _enterMode(tester, 'UPI', '6300');
    await _submit(tester);

    expect(_CapturingNotifier.lastAmount, 6300);
    expect(_CapturingNotifier.lastSplits!.map((s) => s.paymentMode).toList(),
        ['UPI']);
  });

  testWidgets('two modes add up into the collected amount', (tester) async {
    await _pumpForm(tester);
    await _enterMode(tester, 'Cash', '4000');
    await _enterMode(tester, 'UPI', '2300');
    await _submit(tester);

    expect(_CapturingNotifier.lastAmount, 6300,
        reason: 'the app adds the modes up; the Agent does not');
    expect(
      {
        for (final s in _CapturingNotifier.lastSplits!) s.paymentMode: s.amount
      },
      {'Cash': 4000, 'UPI': 2300},
    );
  });

  testWidgets('a mode saved as zero is dropped rather than recorded',
      (tester) async {
    await _pumpForm(tester);
    await _enterMode(tester, 'Cheque', '0');
    await _submit(tester);

    expect(_CapturingNotifier.lastSplits!.map((s) => s.paymentMode).toList(),
        ['Cash'],
        reason: 'a zero-rupee split names a payment nobody made');
  });

  testWidgets('Bank Transfer and Cheque are offered at all', (tester) async {
    await _pumpForm(tester);
    for (final mode in ['Cash', 'UPI', 'Bank Transfer', 'Cheque']) {
      expect(find.text(mode), findsOneWidget,
          reason: '$mode has been in payment_mode_enum all along');
    }
    expect(find.text('Mixed Payment'), findsNothing);
  });
}
