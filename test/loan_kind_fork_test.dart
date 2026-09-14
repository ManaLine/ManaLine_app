import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Which kind of loan the search writes, and when it is allowed to ask.
///
/// This is a MONEY FORK chosen by a bottom sheet. A pre-existing loan is a
/// balance carried in through app.migrate_loan and it does not touch BF,
/// because that cash left the till before the app existed. A new loan is cash
/// going out today and it moves BF. Writing one when the Owner meant the other
/// is a wrong number that nothing downstream flags -- the loan simply exists,
/// with the wrong story attached to it.
///
/// The Owner's rule, verbatim: "if the migration is still open - while open -
/// ask pre-existing or new. and once locked only new."
void main() {
  final search = File(
          'lib/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart')
      .readAsStringSync();
  final sheet = File(
          'lib/features/owner_workspace/screens/ow_pre_existing_loan_sheet.dart')
      .readAsStringSync();

  /// _offerLoan, from its signature to the end of _offerAnother's opening.
  String offerLoan() {
    final from = search.indexOf('Future<void> _offerLoan(');
    expect(from, greaterThan(-1), reason: '_offerLoan has been renamed');
    final to = search.indexOf('Future<void> _offerAnother(', from);
    expect(to, greaterThan(from), reason: '_offerAnother has been renamed');
    return search.substring(from, to);
  }

  group('the question is asked only while it has two answers', () {
    test('nothing is asked unless the migration is open', () {
      final body = offerLoan();
      final ask = body.indexOf('which_kind_of_loan');
      final gate = body.indexOf('if (open) {');
      expect(gate, greaterThan(-1),
          reason: 'the open-migration gate around the question is gone');
      expect(ask, greaterThan(gate),
          reason: 'the loan-kind question must sit INSIDE the open check; '
              'asking it on a locked book offers to write a pre-existing '
              'loan against a running one');
    });

    test('pre-existing is false until the Owner says otherwise', () {
      // The default decides what a dismissed sheet writes, and a dismissed
      // sheet must never be read as a choice.
      expect(offerLoan(), contains('var preExisting = false;'));
      expect(offerLoan(), contains('if (choice == null || !mounted) return;'),
          reason: 'backing out of the question must write nothing at all');
    });

    test('a book whose state cannot be read counts as LOCKED', () {
      // Being unable to read the flag is not evidence that a migration is
      // open, and offering a pre-existing loan on a running book is the more
      // damaging of the two mistakes.
      final from = search.indexOf('Future<bool> _migrationOpen()');
      expect(from, greaterThan(-1), reason: '_migrationOpen has been renamed');
      final body = search.substring(from, search.indexOf('\n  }', from));
      expect(body, contains('return false;'),
          reason: 'the catch must answer locked, not open');
      expect(body, contains('migrationLocked == false'),
          reason: 'open is the ABSENCE of the lock, stated explicitly rather '
              'than inferred from a nullable being falsy');
    });
  });

  group('each branch writes what it says', () {
    test('new money goes to the lending screen, not to migrate_loan', () {
      final body = offerLoan();
      // Sliced to the END of that branch, not to the end of the method: both
      // arms return, and taking everything after the `if` would have swept the
      // pre-existing call in and made the assertion below pass for the wrong
      // reason -- or, as it did first time, fail for one.
      final branch = body.substring(
        body.indexOf('if (!preExisting) {'),
        body.indexOf('final saved = await manaEnterPreExistingLoan('),
      );
      expect(branch, contains("context.push('/ow-005?customerId="),
          reason: 'a new loan must go through the lending flow, which is what '
              'moves BF');
      expect(branch, isNot(contains('manaEnterPreExistingLoan')),
          reason: 'the new-loan branch must never reach the migration writer');
    });

    test('an already-running loan goes through the migration writer', () {
      expect(offerLoan(), contains('manaEnterPreExistingLoan('));
    });

    test('there is one write path for a pre-existing loan, not two', () {
      // app.migrate_loan has two doors: directly by customer_id, and through
      // app.import_migrated_loans, which resolves the mlid and then calls
      // migrate_loan itself (verified against pg_proc). The shared sheet takes
      // the second, so the idempotency key, the row-level rejection messages
      // and the mlid resolution the bulk wizard relies on all apply here too.
      expect(sheet, contains('submitCustomerLoans('));
      expect(sheet, isNot(contains('migrateLoan(')),
          reason: 'a second direct route to migrate_loan would have to be kept '
              'in step with the bulk one by hand');
      expect(sheet, contains('idempotencyKey: entry.idempotencyKey'),
          reason: 'the key minted with the entry is what makes a retry on a '
              'village connection safe rather than a second loan');
    });
  });

  test('a loan is only offered to somebody who is a customer here', () {
    // An Agent or Investor who has not accepted yet certainly has no loan,
    // and offering one would be the app acting on an answer nobody has given.
    expect(search, contains('if (types.contains(MemberType.customer)) {'));
  });
}
