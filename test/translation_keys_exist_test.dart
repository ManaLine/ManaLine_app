import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every label the app asks for has a row behind it.
///
/// A key with no row renders as the RAW KEY on the handset. This has now
/// happened four times:
///
///   use_my_location             on the live registration form
///   add_this_persons_entry      shipped in build 10
///   village_search_by_pin +3    on the village search, reported from a phone
///   about / account / appearance / restore + 2   found by THIS test, live,
///                               and three of them are screen titles
///
/// The layout tests cannot catch it: they read a vendored fixture and
/// therefore always find a value. The first version of this guard watched the
/// five files of the one-by-one door, which is why it could not see any of the
/// six above. It watches all of lib/ now.
///
/// WHAT IT COMPARES AGAINST, and why that is not the database: a test has no
/// credentials and must pass offline. supabase/migrations is the record of
/// what was applied, so a key with no INSERT anywhere in that folder is a key
/// nothing ever created. The reverse -- a row applied whose local file was
/// never written -- is a separate defect, and finding one is how
/// 20260812142822 came to be restored.

/// Keys that ARE in ui_translations but whose migration file was never
/// written locally.
///
/// This is the ledger drift, not a missing key: every one of these was
/// verified present in the production ui_translations table on 2026-09-13, so
/// none of them renders as a raw key. What is missing is the .sql file that
/// applied it -- the same defect that had 20260812142822 restored from
/// schema_migrations earlier the same day.
///
/// Listed BY NAME rather than skipped by a pattern, because the whole value of
/// this guard is that a NEW key with no migration fails immediately. A
/// wildcard would have swallowed village_search_by_pin along with these.
///
/// The right fix is to restore the .sql files from
/// supabase_migrations.schema_migrations, at which point entries come off this
/// list. Shrinking it is progress; adding to it is not, and a new name here
/// should be challenged rather than accepted.
const _appliedButFileMissing = <String>{
  'add_cheti', 'agent_asked_you_to_check_bf', 'already_availed_lumpsum',
  'amount_availed_field', 'availed', 'availed_on', 'availed_on_note',
  'availing_adds_to_bf_note', 'balance', 'before_migration_suffix',
  'bf_cash_transfer_note', 'bf_transfer_confirmed_note',
  'bf_transfer_sent_note', 'carried_forward', 'cash_out_of_bf',
  'change_user', 'cheti_name_field', 'cheti_net_position',
  'cheti_partway_note', 'collect', 'day_closing', 'dividend_helper',
  'dividend_this_period_field', 'emi', 'existing_customers_only',
  'existing_customers_only_off_note', 'existing_customers_only_on_note',
  'face_value', 'face_value_field', 'final_profit', 'frequency_field',
  'grace_period_note', 'guarantor_loan_scoped_note',
  'instalment_amount_field', 'instalment_required_field', 'instalments',
  'instalments_already_paid_field', 'instalments_still_to_pay_suffix',
  'instalments_x_of_y', 'lending_rules', 'less_than_the_instalment',
  'live_photo_note', 'more_than_the_instalment', 'net_position',
  'no_bf_assignment_note', 'no_chetis_yet_note', 'no_collection',
  'nothing_collected', 'opening_gap_note', 'opening_matches_note',
  'paid_in', 'paid_the_full_instalment', 'payment',
  'penalty_adds_to_balance_note', 'record_availing',
  'record_availing_for_note', 'record_payment', 'record_payment_for_note',
  'save_availing', 'save_cheti', 'save_payment', 'sorted_by', 'start_date',
  'tap_to_open', 'tap_to_open_their_record', 'terms_body',
  'total_already_paid_field', 'total_instalments_field', 'type_field',
};

void main() {
  final migrations = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .map((f) => f.readAsStringSync())
      .join(' ');

  /// `ref.t('key')`, allowing the formatter to have split it.
  ///
  /// It writes `ref` at the end of one line and `.t('key')` at the start of
  /// the next whenever the surrounding expression is long. The first version
  /// of this pattern required the two to touch, so those calls were invisible
  /// to a test whose entire job is finding keys.
  final tCall = RegExp(r"""ref\s*\.\s*t\(\s*'([a-z0-9_]+)'\s*\)""");

  List<File> dartFiles() {
    final out = <File>[];
    void walk(Directory d) {
      for (final e in d.listSync()) {
        if (e is Directory) {
          walk(e);
        } else if (e is File && e.path.endsWith('.dart')) {
          out.add(e);
        }
      }
    }

    walk(Directory('lib'));
    return out;
  }

  test('no screen anywhere asks for a key that was never created', () {
    final missing = <String, String>{};
    for (final f in dartFiles()) {
      for (final m in tCall.allMatches(f.readAsStringSync())) {
        final key = m.group(1)!;
        if (_appliedButFileMissing.contains(key)) continue;
        // The INSERT lists them as ('key', 'English', 'Telugu').
        if (!migrations.contains("('$key',")) {
          missing.putIfAbsent(key, () => f.path);
        }
      }
    }
    final report =
        missing.entries.map((e) => '${e.key} in ${e.value}').join(' | ');
    expect(missing, isEmpty,
        reason: 'these render as raw keys on the handset: $report');
  });

  test('the scan is finding keys at all, not passing on an empty sweep', () {
    // A guard that checks nothing reads exactly like one that passes.
    var found = 0;
    for (final f in dartFiles()) {
      found += tCall.allMatches(f.readAsStringSync()).length;
    }
    expect(found, greaterThan(1000),
        reason: 'only $found keys found across lib/; the pattern has '
            'stopped matching');
  });
}
