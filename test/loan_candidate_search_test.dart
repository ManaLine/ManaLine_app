import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';

/// What these pin: Confirm Loan died on
/// `invalid input syntax for type uuid: ""` because Step 1 searched a GLOBAL
/// identity RPC and happily selected somebody who was not a customer of this
/// business at all. The empty customer_id travelled six steps.
///
/// The fix is NOT "never return a row without a customer_id" — the Owner may
/// choose to lend to new borrowers, and those rows legitimately have none yet.
/// It is that such a row must be *identifiable*, so the screen can create the
/// customer before the loan is written.
void main() {
  group('manaLoanCandidates', () {
    test('keeps a not-yet-customer row, because the wizard can add them', () {
      final out = manaLoanCandidates([
        {'customer_id': null, 'person_id': 30, 'full_name': 'Ramesh Reddy', 'is_customer': false},
        {'customer_id': 'c1', 'person_id': 5, 'full_name': 'Pothula Aruna Reddy', 'is_customer': true},
      ]);
      expect(out.length, 2);
      expect(out.first.customerId, isEmpty);
      expect(out.first.personId, '30');
      expect(out.last.customerId, 'c1');
    });

    test('drops a row that identifies nobody at all', () {
      // Neither a customer of this book nor a person to add: nothing the
      // screen could do with it, and an empty customerId travelling on is the
      // exact fault this path was rebuilt to close.
      final out = manaLoanCandidates([
        {'customer_id': null, 'person_id': null, 'full_name': 'Ghost'},
        {'customer_id': '', 'person_id': '', 'full_name': 'Also Nobody'},
      ]);
      expect(out, isEmpty);
    });

    test('keeps the details that tell two same-named people apart', () {
      final out = manaLoanCandidates([
        {
          'customer_id': 'c1',
          'person_id': 5,
          'full_name': 'somayajulu',
          'father_husband_name': 'venkat',
          'mlid': 'MLPI100000014',
          'mobile_number': '9876543210',
          'village': 'Uranduru',
          'active_loans': 2,
        },
      ]);
      final c = out.single;
      expect(c.village, 'Uranduru');
      expect(c.mlid, 'MLPI100000014');
      expect(c.phoneNumber, '9876543210');
      expect(c.activeLoanCount, 2);
      // Title Case is enforced in code, not hoped for from the data.
      expect(c.fullName, 'Somayajulu');
      expect(c.fatherHusbandName, 'Venkat');
    });

    test('a missing village is empty, never the string "null"', () {
      final out = manaLoanCandidates([
        {'customer_id': 'c1', 'person_id': 5, 'full_name': 'No Address', 'village': null},
      ]);
      expect(out.single.village, '');
      expect(out.single.activeLoanCount, 0);
    });
  });
}
