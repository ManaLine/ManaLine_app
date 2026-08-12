import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_011_day_closure.dart';
import 'package:mana_line/features/owner_workspace/state/day_closure_state.dart';

import 'support/mana_harness.dart';

/// OW-011 Final Review used to render `_SummaryRow(opening_balance, value: 0)`
/// with a `// TODO: from day_ledger` beside it, while Collections, Adjustments
/// and Closing Balance on the same card were real. The Owner reconciles the
/// till against that card, so a fabricated zero there reads as "the day started
/// empty" on any day that carried cash forward — and the post-close receipt
/// then showed the true opening balance, changing the number after the
/// decision was made.
///
/// `day_ledger.opening_balance` was already being SELECTed by `precheck()` and
/// silently dropped, so this is wiring, not new arithmetic. These tests pin the
/// wire: whatever the ledger says is what Final Review shows.
class _SeededDayClosureNotifier extends DayClosureNotifier {
  _SeededDayClosureNotifier(this._seed);
  final DayClosureState _seed;

  @override
  DayClosureState build() => _seed;

  @override
  Future<void> runPrecheck({required String businessId, required String businessDate}) async {}

  @override
  Future<void> loadForReopen({required String businessId, required String businessDate}) async {}
}

const _translations = <String, Map<String, String>>{
  'opening_balance': {'English': 'Opening Balance'},
  'collections': {'English': 'Collections'},
  'adjustments': {'English': 'Adjustments'},
  'closing_balance_label': {'English': 'Closing Balance'},
  'difference': {'English': 'Difference'},
  'balanced': {'English': 'Balanced'},
  'final_review': {'English': 'Final Review'},
  'remarks_optional': {'English': 'Remarks (Optional)'},
  'confirm_close_business_day': {'English': 'Confirm — Close Business Day'},
};

/// The amount rendered beside [label] on the Final Review card, or null when
/// that row is absent. Reads the row rather than the whole screen because
/// Adjustments and Difference are legitimately ₹0 here — a bare
/// `find.text('₹0')` cannot tell a real zero from the fabricated one.
String? _amountBeside(WidgetTester tester, String label) {
  final labelFinder = find.text(label);
  if (labelFinder.evaluate().isEmpty) return null;
  final row = find.ancestor(of: labelFinder, matching: find.byType(Row)).first;
  final texts = tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)));
  return texts.length >= 2 ? texts.elementAt(1).data : null;
}

void main() {
  Widget screen() => const DayClosureScreen(businessId: 'b1', businessDate: '2026-08-07');

  DayClosureState finalReview({int? openingBalance}) => DayClosureState(
        phase: DayClosurePhase.finalReview,
        businessDate: '2026-08-07',
        openingBalance: openingBalance,
        expected: ExpectedFigures(
            expectedCash: 187500, expectedUpi: 25000, expectedBank: 0, expectedCheque: 0),
        physicalCash: 187500,
        upiBalance: 25000,
      );

  testWidgets('Final Review shows the ledger opening balance, not a fabricated zero',
      (tester) async {
    await pumpManaScreen(
      tester,
      screen(),
      translations: _translations,
      overrides: [
        dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(finalReview(openingBalance: 250000))),
      ],
    );

    // The regression: this row was hardcoded to 0 regardless of the ledger.
    expect(_amountBeside(tester, 'Opening Balance'), '₹2,50,000');
  });

  testWidgets('a genuinely zero opening balance still renders as zero', (tester) async {
    await pumpManaScreen(
      tester,
      screen(),
      translations: _translations,
      overrides: [
        dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(finalReview(openingBalance: 0))),
      ],
    );

    expect(_amountBeside(tester, 'Opening Balance'), '₹0');
  });

  testWidgets('an unknown opening balance is omitted rather than shown as zero',
      (tester) async {
    await pumpManaScreen(
      tester,
      screen(),
      translations: _translations,
      overrides: [
        dayClosureProvider.overrideWith(() => _SeededDayClosureNotifier(finalReview())),
      ],
    );

    // Nothing to state truthfully, so the row is absent — never a stand-in 0.
    expect(find.text('Opening Balance'), findsNothing);
    expect(_amountBeside(tester, 'Opening Balance'), isNull);
  });
}
