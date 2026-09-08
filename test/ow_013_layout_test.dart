// OW-013 Account Review's card grid (Plan 2a Task 5): one column on a
// phone, two at medium width, three at expanded width. Branches on
// LayoutBuilder constraints (ManaBreakpoints.of), never MediaQuery -- see
// _SettlementCardGrid's doc comment in ow_013_account_review.dart for why
// that distinction matters inside ManaWebFrame's clamp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_013_account_review.dart';
import 'package:mana_line/features/owner_workspace/state/account_review_state.dart';

import 'support/mana_harness.dart';

AccountSettlementSummary _settlement(String id, String agentName) => AccountSettlementSummary(
      settlementId: id,
      accountPeriodId: 'ap-$id',
      businessDate: DateTime(2026, 8, 7),
      agentName: agentName,
      totalCollections: 100000,
      totalLoansIssued: 50000,
      totalInterest: 3000,
      totalProcessingFee: 500,
      expenses: 0,
      short: 0,
      excess: 0,
      difference: 0,
      status: 'Pending Owner Review',
      handOverCash: 100000,
      handOverUpi: 0,
      handOverCheque: 0,
    );

final _seed = AccountReviewState(
  settlements: [
    _settlement('s1', 'Agent Alpha'),
    _settlement('s2', 'Agent Bravo'),
    _settlement('s3', 'Agent Charlie'),
  ],
);

class _SeededAccountReviewNotifier extends AccountReviewNotifier {
  @override
  AccountReviewState build() => _seed;

  @override
  Future<void> load(String businessId) async {}
}

void main() {
  final overrides = [accountReviewProvider.overrideWith(_SeededAccountReviewNotifier.new)];

  Future<void> pumpAtWidth(WidgetTester tester, double width) => pumpManaScreen(
        tester,
        const AccountReviewScreen(businessId: 'b1'),
        surfaceSize: Size(width, 900),
        location: '/ow-013',
        overrides: overrides,
      );

  testWidgets('OW-013 renders one column at 390 (compact)', (tester) async {
    await pumpAtWidth(tester, 390);
    final x0 = tester.getTopLeft(find.text('Agent Alpha')).dx;
    final y0 = tester.getTopLeft(find.text('Agent Alpha')).dy;
    final x1 = tester.getTopLeft(find.text('Agent Bravo')).dx;
    final y1 = tester.getTopLeft(find.text('Agent Bravo')).dy;

    expect(x1, x0, reason: 'a single column keeps every card at the same left edge');
    expect(y1, greaterThan(y0), reason: 'cards stack vertically in a single column');
    expectNoLayoutFault(tester, 'OW-013 at 390');
  });

  testWidgets('OW-013 renders two columns at 820 (medium)', (tester) async {
    await pumpAtWidth(tester, 820);
    final p0 = tester.getTopLeft(find.text('Agent Alpha'));
    final p1 = tester.getTopLeft(find.text('Agent Bravo'));
    final p2 = tester.getTopLeft(find.text('Agent Charlie'));

    // Card 1 sits beside card 0 in the same row.
    expect(p1.dx, greaterThan(p0.dx), reason: 'two columns places card 1 to the right of card 0');
    expect((p1.dy - p0.dy).abs(), lessThan(4), reason: 'cards 0 and 1 share the same row at medium width');
    // Card 2 wraps to a new row, back at the left edge.
    expect(p2.dx, p0.dx, reason: 'the third card wraps to a new row at the same left edge as card 0');
    expect(p2.dy, greaterThan(p0.dy), reason: 'the third card sits on the row below');

    expectNoLayoutFault(tester, 'OW-013 at 820');
  });

  testWidgets('OW-013 renders three columns at 1440 (expanded)', (tester) async {
    await pumpAtWidth(tester, 1440);
    final p0 = tester.getTopLeft(find.text('Agent Alpha'));
    final p1 = tester.getTopLeft(find.text('Agent Bravo'));
    final p2 = tester.getTopLeft(find.text('Agent Charlie'));

    expect(p1.dx, greaterThan(p0.dx), reason: 'card 1 sits to the right of card 0');
    expect(p2.dx, greaterThan(p1.dx), reason: 'card 2 sits to the right of card 1');
    expect((p1.dy - p0.dy).abs(), lessThan(4), reason: 'all three cards share the same row at expanded width');
    expect((p2.dy - p0.dy).abs(), lessThan(4), reason: 'all three cards share the same row at expanded width');

    expectNoLayoutFault(tester, 'OW-013 at 1440');
  });

  for (final width in [390.0, 820.0, 1440.0]) {
    testWidgets('OW-013 at width $width survives text scale 2.0x', (tester) async {
      await pumpManaScreen(
        tester,
        const AccountReviewScreen(businessId: 'b1'),
        surfaceSize: Size(width, 900),
        location: '/ow-013',
        overrides: overrides,
        textScale: 2.0,
      );
      expectNoLayoutFault(tester, 'OW-013 at width $width, scale 2.0x');
    });
  }
}
