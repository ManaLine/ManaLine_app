import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A migration's own assertions must not need somebody else's data.
///
/// WHAT THIS COST. `20260918083013_a_business_can_show_its_qr_and_upi_at_the_door.sql`
/// proved its CHECK constraint worked like this:
///
///     UPDATE businesses SET upi_ids = ARRAY['broken']
///      WHERE business_id = (SELECT business_id FROM businesses LIMIT 1);
///     -- ... EXCEPTION WHEN check_violation THEN v_refused := TRUE;
///     IF NOT v_refused THEN RAISE EXCEPTION 'the CHECK did not fire'; END IF;
///
/// On production that is a real assertion: a book exists, the UPDATE hits it,
/// the CHECK fires. On a database rebuilt from empty there are no businesses.
/// The subquery is NULL, the UPDATE matches zero rows, nothing is asked to
/// fire, and the migration raises. `tool/verify_rebuild.ps1` stopped dead
/// there, 24 files short of the end, and the repo could not rebuild itself
/// from nothing for the twelve days that file sat in the tree.
///
/// THE RULE ALREADY EXISTED, one directory over. `sql_tests_wired_test.dart`
/// fails any file in `supabase/tests/` that matches `FROM businesses ORDER BY`,
/// with the reasoning written out: "a scratch file must build its own
/// fixtures, never adopt an existing row". Nothing extended that to
/// migrations, which run against both a full production database AND an empty
/// rebuild, and therefore need it more.
///
/// A migration that legitimately needs a row must either create one, or
/// guard the assertion with `IF EXISTS (SELECT 1 FROM <table>)` and assert
/// something rowless in the other branch -- which is what the file above does
/// now.
void main() {
  /// Reaching into a table for an arbitrary existing row.
  ///
  /// Deliberately narrow: `LIMIT 1` or `ORDER BY ... LIMIT` with no WHERE
  /// naming a specific key. A subquery that selects a row it just inserted by
  /// id is fine and is the pattern this steers towards.
  final adoptsARow = RegExp(
    r'FROM\s+(businesses|persons|customers|loans|agents|investors)\s*'
    r'(ORDER\s+BY\s+[a-z_]+\s*(ASC|DESC)?\s*)?LIMIT\s+1',
    caseSensitive: false,
  );

  /// The guard is satisfied when the statement is fenced behind a check that
  /// the table has anything in it at all.
  final guarded = RegExp(r'IF\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+\w+',
      caseSensitive: false);

  test('no migration asserts against whichever row happens to exist', () {
    final dir = Directory('supabase/migrations');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(files.length, greaterThan(100),
        reason: 'the scan found almost no migrations, so it is broken rather '
            'than clean -- a guard that checks nothing reads exactly like one '
            'that passes');

    final offenders = <String>[];
    for (final f in files) {
      // Comment lines blanked, not dropped, so a reported line number still
      // points at the real line. This file and the one it describes both
      // QUOTE the pattern they ban, and a guard matching its own prose is a
      // mistake this repo has now made nine times.
      final lines = f
          .readAsStringSync()
          .split('\n')
          .map((l) => l.trimLeft().startsWith('--') ? '' : l)
          .toList();

      for (var i = 0; i < lines.length; i++) {
        if (!adoptsARow.hasMatch(lines[i])) continue;
        // Look back for the fence. Twenty lines covers a DO block's opening
        // and the IF that should be wrapping this.
        final before = lines.sublist((i - 20).clamp(0, i), i).join('\n');
        if (guarded.hasMatch(before)) continue;
        offenders.add('${f.uri.pathSegments.last}:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These migrations assert against whichever row happens to '
          'exist, so they pass on production and fail on a rebuild from '
          'empty:\n  ${offenders.join('\n  ')}\n\n'
          'Create the row the assertion needs, or fence it with '
          'IF EXISTS (SELECT 1 FROM <table>) and assert something that needs '
          'no rows in the ELSE branch.',
    );
  });

  test('the pattern it bans is one it actually recognises', () {
    // Verified against the real statement that broke the rebuild, so a
    // regex that stops matching is caught here rather than by going quiet.
    const real = "     WHERE business_id = (SELECT business_id FROM businesses LIMIT 1);";
    expect(adoptsARow.hasMatch(real), isTrue);

    // And something legitimate is not swept up: a row fetched by its own key.
    const fine = "  SELECT business_id FROM businesses WHERE business_id = p_business_id;";
    expect(adoptsARow.hasMatch(fine), isFalse);
  });
}
