import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The rule that a loan's status follows its balance, and why it is a trigger.
///
/// The request was "fix record_collection to close the loan at zero". Seven
/// functions assign `loans.remaining_balance` — record_collection,
/// amend_collection, waive_loan_penalty, apply_loan_penalty, soft_delete_record,
/// restore_record and close_loan — so putting the rule in one of them fixes one
/// case in seven, and actively breaks another: deleting a collection from a
/// closed loan gives the money back, and the loan would then owe money while
/// still marked finished, invisible to the round and to the pending list.
///
/// These assertions are about WHERE the rule lives, because that is the part a
/// later change is most likely to undo — somebody adding a balance write to an
/// eighth function will not think to close a loan, and does not have to.
void main() {
  // Comments stripped: this file's own migration explains at length what the
  // code must not do, and a guard that matches its documentation is reporting
  // on prose. That mistake has been made five times in this codebase.
  String sqlOf(String file) => File('supabase/migrations/$file')
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  final trigger = sqlOf('20260917225343_a_loan_status_follows_its_balance.sql');

  test('the rule is a trigger on loans, not a line in one RPC', () {
    expect(trigger, contains('BEFORE UPDATE ON loans'));
    expect(trigger, contains('FOR EACH ROW'));
    expect(trigger, contains('trg_loans_status_follows_balance'));
  });

  test('a paid-off loan closes and is stamped', () {
    expect(trigger, contains("NEW.loan_status := 'Closed'"));
    expect(trigger, contains('NEW.closed_at   := COALESCE(NEW.closed_at, now())'));
  });

  test('a loan that owes money again reopens', () {
    // The half that a fix inside record_collection could not have had, and
    // whose absence would have been a worse bug than the one being fixed.
    expect(trigger, contains("NEW.loan_status := 'Active'"));
    expect(trigger, contains('NEW.closed_at   := NULL'));
  });

  test('only running statuses are closed, and decisions are left alone', () {
    // Cancelled and Defaulted are somebody's decision about a loan, not a fact
    // about its balance.
    expect(trigger,
        contains("NEW.loan_status IN ('Active', 'Grace Period', 'Penalty')"));
    expect(trigger, isNot(contains("'Defaulted'")),
        reason: 'Defaulted must never appear as something the trigger sets');
    expect(trigger, isNot(contains("'Cancelled'")));
  });

  test('a deleted loan is left exactly as it was', () {
    expect(trigger, contains('NEW.deleted_at IS NOT NULL'));
  });

  test('closing by payment recognises the penalty that was paid with it', () {
    // Penalty income lands on the day the balance reached zero. Without this,
    // a loan that closed itself would leave its penalty unrecognised for ever,
    // because app.close_loan — the only thing that ever recognised one — is a
    // manual Owner action nobody would now need to take.
    expect(trigger, contains('UPDATE penalty_entries'));
    expect(trigger, contains('recognised_business_date = CURRENT_DATE'));
    expect(trigger, contains('recognised_business_date IS NULL'));
  });

  test('a write-off can never be recognised as income here', () {
    // close_loan sets the status ITSELF, so the closing branch cannot fire for
    // it — which is what keeps its pay-off/write-off distinction intact. If
    // the branch ever stopped requiring a running status, a written-off
    // penalty would be booked as money somebody paid.
    final closeBranch = trigger.substring(
      trigger.indexOf('IF NEW.remaining_balance <= 0'),
      trigger.indexOf('ELSIF NEW.remaining_balance > 0'),
    );
    expect(closeBranch, contains("'Active', 'Grace Period', 'Penalty'"),
        reason: 'the close branch must only fire from a running status');
  });

  test('record_collection was not the place, and was not edited', () {
    // If a later change moves the rule back into the RPC, this is the line
    // that should make somebody explain why.
    final dir = Directory('supabase/migrations').listSync().whereType<File>();
    final touchingRecordCollection = dir.where((f) {
      final name = f.path.split(RegExp(r'[\\/]')).last;
      if (!name.startsWith('202609172')) return false; // this evening's work
      final body = f.readAsStringSync();
      return body.contains('FUNCTION app.record_collection');
    });
    expect(touchingRecordCollection, isEmpty,
        reason: 'the status rule belongs to every path that moves a balance, '
            'not to the one RPC that happened to be asked about');
  });
}
