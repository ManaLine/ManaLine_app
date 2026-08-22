import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The transfer policy, pinned against the migration that implements it.
///
/// Selling a shop does not cancel the money you put into it. Accepting a
/// transfer used to remove EVERY membership the outgoing owner held — with no
/// role filter — so on the live book it would have marked the owner's Investor
/// membership Removed while the business still owed him 15,26,000, and the
/// liability would have vanished from the lists that show it. A borrower who
/// was also the owner lost their Customer row the same way.
///
/// Read from the migration rather than mocked: this rule lives in plpgsql, and
/// a Dart mock of it would only ever agree with itself.
void main() {
  final sql = File('supabase/migrations/'
          '20260822070055_a_transfer_swaps_the_owner_and_nothing_else.sql')
      .readAsStringSync();

  test('only the Owner role is removed from the outgoing owner', () {
    // The role filter IS the fix. Without it the statement takes every role.
    expect(sql, contains("AND role = 'Owner'"));

    final removal = sql.substring(
        sql.indexOf('ONLY the Owner role'), sql.indexOf('GET DIAGNOSTICS'));
    expect(removal, contains("person_id = t.from_person_id"));
    expect(removal, contains("role = 'Owner'"));
  });

  test('the transfer alters no business data beyond ownership', () {
    // Per the Owner's spec: the old owner prepares the business first, and the
    // handover itself changes nothing but who owns it. Anything that rewrote
    // loans, collections or investments here would be outside that contract.
    for (final table in const [
      'loans', 'collections', 'investments', 'customers', 'expenses',
    ]) {
      expect(sql.contains('UPDATE $table'), isFalse,
          reason: 'a transfer must not rewrite $table');
      expect(sql.contains('DELETE FROM $table'), isFalse,
          reason: 'a transfer must not delete from $table');
    }
  });

  test('both sides are told', () {
    // Each previously wrote an audit row and nothing else, so a business could
    // be handed to someone who never found out.
    expect('business_transfer'.allMatches(sql).length, greaterThanOrEqualTo(2));
    expect(sql.contains('wants to hand you'), isTrue);
    expect(sql.contains('accepted the handover of'), isTrue);
  });

  test('the pre-conditions are still re-checked at accept time', () {
    // An offer can sit for days; the outgoing owner may take a float or have a
    // settlement land in their queue in the meantime.
    final accept = sql.substring(sql.indexOf('IF NOT p_accept'));
    expect(accept, contains('assert_business_transferable'));
  });
}
