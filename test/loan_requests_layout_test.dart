import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/loan_requests_screen.dart';
import 'package:mana_line/features/owner_workspace/state/loan_wizard_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// Loan Requests had no layout test. It is the Owner's queue of customers
/// asking to borrow -- a name, an MLID and an amount per row, plus whatever
/// approve and reject put on screen.
class _FakeLoanApi extends LoanApiService {
  _FakeLoanApi(this._rows, Ref ref) : super(ref: ref);
  final List<LoanRequestSummary> _rows;

  @override
  Future<List<LoanRequestSummary>> fetchLoanRequests({required String businessId}) async => _rows;
}

void main() {
  final rows = [
    LoanRequestSummary(
      requestId: 'lr1',
      customerId: 'c1',
      customerName: 'Nagabhushanam Venkata Subba Reddy',
      customerMlid: 'MLCU0000012345',
      requestedAmount: 1284500,
      purposeRemark: 'Seed and fertiliser for the season, and a pump repair.',
      preferredFrequency: 'Daily',
      createdAt: DateTime(2026, 8, 20),
    ),
  ];

  List<Override> overrides() =>
      [loanApiServiceProvider.overrideWith((ref) => _FakeLoanApi(rows, ref))];

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('Loan Requests survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          const LoanRequestsScreen(businessId: 'b1'),
          textScale: scale,
          language: lang,
          overrides: overrides(),
        );
        await tester.pumpAndSettle();
        expectNoLayoutFault(tester, 'Loan Requests at ${scale}x$tag');
      });
    }
  }
}
