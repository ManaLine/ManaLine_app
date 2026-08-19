import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_003_investor_management.dart';
import 'package:mana_line/features/owner_workspace/state/investor_state.dart';

import 'support/mana_harness.dart';

/// Reported from a handset: "add existing investor screen — bottom overflowed
/// by 51 pixels".
///
/// The sheet asks for a search box, two folded narrowers, a whole first
/// investment (amount, ROI, interest type, profit %, date) AND a results list,
/// in a Column that never scrolled. It fits on a tall phone with the keyboard
/// down and nothing else; raise the text scale, open the narrowers, or let the
/// keyboard eat the bottom half and it runs out of room. This is the overflow
/// class CLAUDE.md calls the recurring bug here, and it is invisible to
/// `flutter analyze`.
class _SeededInvestors extends InvestorWorkforceNotifier {
  @override
  InvestorWorkforceState build() => const InvestorWorkforceState(loading: false);

  @override
  Future<void> load(String businessId) async {}
}

void main() {
  for (final scale in [1.0, 1.3, 1.6, 2.0]) {
    testWidgets('Add Existing Investor survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const InvestorManagementScreen(
          businessId: 'b1',
          initialAction: 'existing', // opens the sheet on first frame
        ),
        textScale: scale,
        overrides: [investorWorkforceProvider.overrideWith(_SeededInvestors.new)],
      );

      expectNoLayoutFault(tester, 'Add Existing Investor at ${scale}x');
    });
  }

  testWidgets('the sheet scrolls rather than clipping its own fields',
      (tester) async {
    await pumpManaScreen(
      tester,
      const InvestorManagementScreen(businessId: 'b1', initialAction: 'existing'),
      textScale: 1.6,
      overrides: [investorWorkforceProvider.overrideWith(_SeededInvestors.new)],
    );

    // Whatever else changes, the fields below the fold have to be reachable —
    // the date row is the last thing before the results list, and an Owner who
    // cannot reach it cannot backdate the first investment.
    expect(find.byType(Scrollable), findsWidgets);
    expectNoLayoutFault(tester, 'Add Existing Investor while scrolling');
  });
}
