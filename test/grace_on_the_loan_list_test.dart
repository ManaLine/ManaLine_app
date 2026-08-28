import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';

/// Grace is a condition on top of a status, not a status.
///
/// loans.loan_status holds Active, Closed and so on; granting grace writes
/// grace_period_days instead, and nothing in this codebase has ever written
/// loan_status = 'Grace Period'. So a loan carrying granted grace reads
/// "Active" wherever the status is printed literally -- true, and incomplete.
///
/// The loan detail, its pill and the round's tag derive it. These pin the
/// model the two customer loan lists read, so the tag cannot quietly go back
/// to asking the status.
void main() {
  CustomerLoanSummary loan({required String status, bool inGrace = false}) =>
      CustomerLoanSummary(
        loanId: 'l1',
        loanNumber: 'LN-MIG-20260822-7c969b',
        issueDate: DateTime(2026, 1, 15),
        loanAmount: 600000,
        outstanding: 500000,
        todaysDue: 30000,
        progressPercent: 16.6,
        status: status,
        inGrace: inGrace,
      );

  test('a loan carries grace separately from its status', () {
    final g = loan(status: 'Active', inGrace: true);
    expect(g.status, 'Active',
        reason: 'the status is still Active, and that is correct');
    expect(g.inGrace, isTrue,
        reason: 'and the list has to be able to say so anyway');
  });

  test('grace defaults to off, so a loan is never wrongly tagged', () {
    expect(loan(status: 'Active').inGrace, isFalse);
  });
}
