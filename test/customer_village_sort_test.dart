import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';

CustomerSummary _c(String name, String village, {int outstanding = 0, int due = 0}) =>
    CustomerSummary(
      customerId: '$name-$village',
      fullName: name,
      fatherHusbandName: '',
      village: village,
      phoneNumber: '',
      mlid: '',
      activeLoanCount: 0,
      todaysDue: due,
      outstandingBalance: outstanding,
      lineRepaymentIndex: 0,
      customerStatus: 'Active',
      membershipStatus: 'Active',
    );

List<String> _villagesOf(List<CustomerSummary> l) => l.map((c) => c.village).toList();

void main() {
  group('customer list ordering', () {
    test('village leads, so a round reads in one block per village', () {
      // The point of the change: outstanding-first scattered each village's
      // customers down the whole list, and both Owner and Agent work one
      // village at a time.
      final state = CustomerListState(customers: [
        _c('A', 'Uranduru', outstanding: 100),
        _c('B', 'Someswaram', outstanding: 90000),
        _c('C', 'Uranduru', outstanding: 200),
        _c('D', 'Someswaram', outstanding: 50),
      ]);
      expect(_villagesOf(state.filtered),
          ['Someswaram', 'Someswaram', 'Uranduru', 'Uranduru']);
    });

    test('within a village the old money order still decides', () {
      final state = CustomerListState(customers: [
        _c('Small', 'Uranduru', outstanding: 100),
        _c('Big', 'Uranduru', outstanding: 900),
        _c('Middle', 'Uranduru', outstanding: 500),
      ]);
      expect(state.filtered.map((c) => c.fullName).toList(),
          ['Big', 'Middle', 'Small']);
    });

    test("today's due breaks an outstanding tie, then name", () {
      final state = CustomerListState(customers: [
        _c('Zed', 'Uranduru', outstanding: 100, due: 10),
        _c('Amy', 'Uranduru', outstanding: 100, due: 10),
        _c('Owes Today', 'Uranduru', outstanding: 100, due: 500),
      ]);
      expect(state.filtered.map((c) => c.fullName).toList(),
          ['Owes Today', 'Amy', 'Zed']);
    });

    test('a customer with no village sorts last, not first', () {
      // An empty string would otherwise sort above every real village name and
      // put the exception at the top of the round.
      final state = CustomerListState(customers: [
        _c('NoVillage', ''),
        _c('Someone', 'Someswaram'),
        _c('Another', 'Uranduru'),
      ]);
      expect(_villagesOf(state.filtered), ['Someswaram', 'Uranduru', '']);
    });
  });
}
