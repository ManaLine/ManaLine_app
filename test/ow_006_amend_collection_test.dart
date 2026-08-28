import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_006_collection_mode.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';

import 'support/mana_harness.dart';

/// Correcting an entry instead of adding a second one.
///
/// A wrong figure at a doorstep was permanent: the round greyed the row, the
/// tap did nothing, and the schema had no edit at all. The only "correction"
/// available was recording a second collection, which the old duplicate
/// warning actively offered as "Continue" -- two receipts for one payment and
/// a balance short by the difference.
class _AmendNotifier extends CollectionModeNotifier {
  static int? amendedAmount;
  static String? amendedId;
  static List<PaymentSplit>? amendedSplits;
  static int? previousAmount;

  /// Set to make recordCollection answer "there is already one of these".
  static ExistingCollection? existing;

  /// The receipt id the form sent on its retry, if any.
  static String? parentSent;

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
    String? parentCollectionId,
  }) async {
    parentSent = parentCollectionId;
    if (existing != null) return RecordCollectionOutcome.already(existing!);
    return RecordCollectionOutcome.saved(CollectionResult(
      receiptNumber: 'RCT-1',
      resultType: 'Partial',
      collectedAmount: collectedAmount,
      newOutstandingBalance: 0,
      businessDate: DateTime(2026, 8, 28),
    ));
  }

  @override
  Future<CollectionResult> amendCollection({
    required String collectionId,
    required int collectedAmount,
    required String payerType,
    String? payerName,
    required List<PaymentSplit> paymentSplits,
    String? excessDisposition,
    String? remarks,
    required int previousAmount,
  }) async {
    amendedId = collectionId;
    amendedAmount = collectedAmount;
    amendedSplits = paymentSplits;
    _AmendNotifier.previousAmount = previousAmount;
    return CollectionResult(
      collectionId: collectionId,
      receiptNumber: 'RCT-20260828-abc123',
      resultType: 'Partial',
      collectedAmount: collectedAmount,
      newOutstandingBalance: 0,
      businessDate: DateTime(2026, 8, 28),
    );
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
  collectionStatus: 'Collected',
  collectedToday: 6300,
  collectionAgent: 'm1',
);

const _existingEntry = CollectionEdit(
  collectionId: 'col-1',
  receiptNumber: 'RCT-20260828-abc123',
  collectedAmount: 6300,
  payerType: 'Customer',
  splits: {'UPI': 6300},
);

Future<void> _pump(WidgetTester tester, {CollectionEdit? editing}) async {
  await pumpManaScreen(
    tester,
    Scaffold(
      body: SingleChildScrollView(
        child: ManaCollectionForm(
          row: _row,
          businessId: 'b1',
          editing: editing,
          onCancel: () {},
        ),
      ),
    ),
    overrides: [collectionModeProvider.overrideWith(_AmendNotifier.new)],
  );
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
    _AmendNotifier.amendedAmount = null;
    _AmendNotifier.amendedId = null;
    _AmendNotifier.amendedSplits = null;
    _AmendNotifier.previousAmount = null;
    _AmendNotifier.existing = null;
    _AmendNotifier.parentSent = null;
  });

  testWidgets('an entry opened for correction shows what was recorded',
      (tester) async {
    await _pump(tester, editing: _existingEntry);

    // The recorded amount, not the instalment -- they happen to match here,
    // so the mode is what proves it: a fresh form always opens on Cash.
    expect(find.textContaining('UPI ₹6,300'), findsOneWidget);
    expect(find.text('Update ₹6,300'), findsOneWidget,
        reason: 'the button must not say Collect on a correction');
  });

  testWidgets('correcting sends the new figure to amend, not to record',
      (tester) async {
    await _pump(tester, editing: _existingEntry);
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.pumpAndSettle();
    await _submit(tester);

    expect(_AmendNotifier.amendedId, 'col-1');
    expect(_AmendNotifier.amendedAmount, 5000);
    expect(_AmendNotifier.previousAmount, 6300,
        reason: 'the running total moves by the difference, not the whole '
            'entry — otherwise a correction counts the money twice');
    expect(_AmendNotifier.amendedSplits!.single.paymentMode, 'UPI',
        reason: 'editing the amount with one mode active keeps that mode');
  });

  testWidgets('a second entry on a loan is refused, with no way to force it',
      (tester) async {
    _AmendNotifier.existing = const ExistingCollection(
      collectionId: 'col-1',
      receiptNumber: 'RCT-20260828-abc123',
      collectedAmount: 6300,
      resultType: 'Full',
      recordedBy: 'Karri Siri Manikanta Reddy',
      mine: true,
    );
    await _pump(tester);
    await _submit(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Already Collected Today'), findsOneWidget);
    expect(find.text('Continue'), findsNothing,
        reason: 'Continue recorded a SECOND payment against the same loan');

    // The two things a second visit can mean, named separately. Neither is
    // "Continue": one adds a dated payment to the receipt, the other amends
    // what is already there.
    expect(find.text('Add Payment'), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('Add Payment sends the receipt it belongs to', (tester) async {
    // A Weekly customer paying Rs 100 a day against a Rs 300 instalment: the
    // second day is not a duplicate, and the server only accepts it when the
    // caller names the receipt.
    _AmendNotifier.existing = const ExistingCollection(
      collectionId: 'receipt-1',
      receiptNumber: 'RCT-20260828-abc123',
      collectedAmount: 100,
      cycleTotal: 200,
      resultType: 'Partial',
      recordedBy: 'Karri Siri Manikanta Reddy',
      mine: true,
      window: 'cycle',
    );
    await _pump(tester);
    await _submit(tester);

    // The note quotes the CYCLE total, not the last day.
    expect(find.textContaining('200'), findsWidgets);

    _AmendNotifier.existing = null; // the retry must be allowed to save
    await tester.tap(find.text('Add Payment'));
    await tester.pumpAndSettle();

    expect(_AmendNotifier.parentSent, 'receipt-1',
        reason: 'without the parent the server refuses it as a duplicate');
  });

  testWidgets('a cycle-window refusal says cycle, and names the day',
      (tester) async {
    // A Weekly loan may be collected once per account period, so the entry
    // that blocks today's may have been taken days ago. Saying "today" here
    // sends the Agent back tomorrow to be refused again.
    _AmendNotifier.existing = ExistingCollection(
      collectionId: 'col-1',
      receiptNumber: 'RCT-20260819-abc123',
      collectedAmount: 6300,
      resultType: 'Full',
      recordedBy: 'Karri Siri Manikanta Reddy',
      mine: true,
      window: 'cycle',
      businessDate: DateTime(2026, 8, 19),
    );
    await _pump(tester);
    await _submit(tester);

    expect(find.text('Already Collected This Account Cycle'), findsOneWidget);
    expect(find.textContaining('19 Aug'), findsOneWidget);
  });
}
