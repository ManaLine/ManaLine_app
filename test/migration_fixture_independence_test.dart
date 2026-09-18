import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A migration's own assertions must hold on a database with no books in it.
///
/// WHAT THIS EXISTS FOR. `20260918083013_a_business_can_show_its_qr_and_upi_at
/// _the_door.sql` ended with a DO block proving its CHECK actually fires:
///
///     UPDATE businesses SET upi_ids = ARRAY['broken']
///      WHERE business_id = (SELECT business_id FROM businesses LIMIT 1);
///
/// against a live book that is a real probe — the CHECK refuses the write and
/// the block catches check_violation. Against a database rebuilt from nothing
/// the subquery is NULL, the UPDATE matches zero rows, no CHECK fires, and the
/// block raised `the CHECK did not fire on a bad handle`. It had been applied
/// to production for a day and read as fine, because production has five
/// businesses. `tool/verify_rebuild.ps1` stopped there, 473 of 479, so the
/// seven migrations after it had never been applied to an empty database by
/// anything at all.
///
/// This is the same defect `test/sql_tests_wired_test.dart` already fails
/// `supabase/tests/*.sql` for — "builds its own fixtures rather than adopting
/// a real row". That rule simply did not cover `supabase/migrations/`. This is
/// that rule, pointed at the other directory.
///
/// WHY `LIMIT` AND NOT `ORDER BY`. The sibling rule matches `FROM businesses
/// ORDER BY`, because a test file has no business reading the table at all. A
/// migration does: a backfill that loops every row (`FOR r IN SELECT
/// business_id FROM businesses LOOP`) is exactly right, and is empty-safe by
/// construction — with no rows it does nothing. What is not safe is picking
/// *a* row: `LIMIT` is the word that turns "every book" into "whichever book
/// happens to be there", and it is the word that was in the failing file.
///
/// ONLY DO BLOCKS ARE READ. A `CREATE FUNCTION` body runs later, against a
/// database that by then has rows, so `ORDER BY ... LIMIT 1` inside one is
/// ordinary code. A DO block runs NOW, during the migration, on whatever the
/// database holds at that moment — which, on a rebuild, is nothing.
/// A DO block's body with its comments and its string literals removed, so
/// what is left is only SQL that runs.
///
/// A SCANNER AND NOT TWO `replaceAll`s, which is what this was first, and it
/// silently checked nothing. Strip comments first and
/// `RAISE EXCEPTION 'an empty list must be allowed -- it is the default';`
/// loses its closing quote, because the `--` is inside the literal. Every
/// literal after it is then paired off by one, and the second pass eats the
/// real code between them — including the `FROM businesses LIMIT 1` this guard
/// exists to find. Strip literals first and a comment holding an apostrophe
/// does the same damage in the other direction. There is no order that works,
/// because the two constructs quote each other; only reading left to right
/// once, knowing which one you are inside, does.
String _executableSql(String body) {
  final out = StringBuffer();
  var i = 0;
  while (i < body.length) {
    final c = body[i];
    if (c == '-' && i + 1 < body.length && body[i + 1] == '-') {
      while (i < body.length && body[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == "'") {
      i++;
      while (i < body.length) {
        if (body[i] == "'") {
          // '' is an escaped quote inside the literal, not the end of it.
          if (i + 1 < body.length && body[i + 1] == "'") {
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      // A literal is data. Leave a placeholder so `FROM x` and `LIMIT` on
      // either side of one are not accidentally joined into a match.
      out.write(" '' ");
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

void main() {
  final dir = Directory('supabase/migrations');

  // Dollar-quoted DO blocks, tag matched to tag: `DO $$ … $$`, `DO $mig$ … $mig$`.
  final doBlock = RegExp(r'\bDO\s+(\$[A-Za-z_]*\$)([\s\S]*?)\1', caseSensitive: false);

  // A single row lifted out of a table this block did not fill. Catalog reads
  // are the point of most of these blocks — `FROM pg_proc … LIMIT 1` asserts
  // something about the schema, which is there on any database.
  final adoptsARow = RegExp(
    r'\bFROM\s+(?!pg_|information_schema\.)([A-Za-z_][\w.]*)[^;]*?\bLIMIT\b',
    caseSensitive: false,
  );

  /// Named, with the reason, because a guard that is quietly narrowed stops
  /// being a guard. Each entry is a file that matches and is allowed to.
  const allowed = <String, String>{
    // Two selects, both inside `IF v_bid IS NOT NULL THEN`. It cannot stop a
    // rebuild — with no account_periods the whole block is skipped. What it
    // does do is pass trivially on an empty database while reading as an
    // assertion, which is the weaker half of the same fault. Left as it is
    // because it is already applied and fixing it would mean fabricating an
    // account period inside a migration that also runs against real books;
    // raised with the Owner rather than edited.
    '20260917234150_a_period_that_starts_at_ten_at_night_still_owns_that_day.sql':
        'guarded by IF v_bid IS NOT NULL, so it skips rather than raises',
  };

  test('migrations exist to check', () {
    expect(dir.existsSync(), isTrue);
  });

  test('no migration asserts against a row it did not create', () {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    var blocksRead = 0;
    final offenders = <String>[];

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      for (final block in doBlock.allMatches(file.readAsStringSync())) {
        blocksRead++;
        // Comments explain these patterns and quoting one is not committing
        // it. Single-quoted literals matter more: six migrations patch a
        // function by running replace() over pg_get_functiondef, and the text
        // being searched for is a quoted copy of the old body — including its
        // own ORDER BY … LIMIT 1, which is data here, not a statement.
        final code = _executableSql(block.group(2)!);

        for (final hit in adoptsARow.allMatches(code)) {
          if (allowed.containsKey(name)) continue;
          offenders.add('$name: a DO block reads a single row from '
              '`${hit.group(1)}` (FROM … LIMIT) without creating it');
        }
      }
    }

    // A guard that checks nothing reads exactly like one that passes. If the
    // dollar-quote shape ever changes and this stops finding blocks, that is a
    // failure, not a pass.
    expect(blocksRead, greaterThan(0),
        reason: 'no DO blocks were found in supabase/migrations at all, so '
            'this guard checked nothing. The block-matching regex has gone '
            'stale — fix it rather than trusting the green.');

    expect(
      offenders,
      isEmpty,
      reason: 'A DO block in a migration runs during the migration, against '
          'whatever the database holds at that moment. On a rebuild from '
          'nothing that is no rows, so an assertion that picks a row finds '
          'NULL and either raises or proves nothing:\n  '
          '${offenders.join('\n  ')}\n'
          'Build what the assertion needs, or assert something that needs no '
          'rows — the catalog (pg_constraint, pg_proc, pg_policies) says what '
          'the schema is without any data in it.',
    );
  });

  test('every allowance names a file that is still there and still matches',
      () {
    // An allowance for a file that no longer matches is an allowance that
    // would silently cover the next offence in that file.
    for (final entry in allowed.entries) {
      final file = File('${dir.path}/${entry.key}');
      expect(file.existsSync(), isTrue,
          reason: '${entry.key} is allowed by name but is not in '
              'supabase/migrations. Remove the allowance.');

      final matched = doBlock.allMatches(file.readAsStringSync()).any((b) {
        return adoptsARow.hasMatch(_executableSql(b.group(2)!));
      });
      expect(matched, isTrue,
          reason: '${entry.key} no longer adopts a row, so its allowance '
              '("${entry.value}") is dead. Remove it.');
    }
  });
}
