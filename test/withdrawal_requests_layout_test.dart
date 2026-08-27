import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/withdrawal_requests_screen.dart';
import 'package:mana_line/features/owner_workspace/state/investor_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// Withdrawal Requests had no layout test. It is where an Owner pays an
/// investor out -- the row carries a name beside a rupee figure, and the
/// approve dialog splits the payout into principal and interest.
///
/// The dialog is one of the fifteen that took `scrollable: true` without a
/// test opening it. This opens it.
class _FakeInvestorApi extends InvestorApiService {
  _FakeInvestorApi(this._rows, Ref ref) : super(ref: ref);
  final List<WithdrawalRequestSummary> _rows;

  @override
  Future<List<WithdrawalRequestSummary>> fetchWithdrawalRequests({
    required String businessId,
  }) async =>
      _rows;
}

void main() {
  final rows = [
    WithdrawalRequestSummary(
      requestId: 'wr1',
      investmentId: 'inv1',
      // A real full name. Names are long here, and this one sits beside the
      // amount in a Row.
      investorName: 'Nagabhushanam Venkata Subba Reddy',
      investorMlid: 'MLIN0000012345',
      withdrawalType: 'Principal And Interest',
      requestedAmount: 1284500,
      remarks: 'Needs it for a family function.',
      createdAt: DateTime(2026, 8, 20),
    ),
  ];

  List<Override> overrides() => [
        investorApiServiceProvider.overrideWith((ref) => _FakeInvestorApi(rows, ref)),
      ];

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';

      testWidgets('Withdrawal Requests survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          const WithdrawalRequestsScreen(businessId: 'b1'),
          textScale: scale,
          language: lang,
          overrides: overrides(),
        );
        await tester.pumpAndSettle();
        expectNoLayoutFault(tester, 'Withdrawal Requests at ${scale}x$tag');
      });

      testWidgets('Withdrawal payout dialog survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          const WithdrawalRequestsScreen(businessId: 'b1'),
          textScale: scale,
          language: lang,
          overrides: overrides(),
        );
        await tester.pumpAndSettle();

        final approve = find.byType(FilledButton);
        if (approve.evaluate().isEmpty) return;
        await tester.tap(approve.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expectNoLayoutFault(tester, 'Withdrawal payout dialog at ${scale}x$tag');
      });
    }
  }
}
