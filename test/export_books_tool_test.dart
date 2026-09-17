import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tool/export_books.py writes people's names, mobile numbers and addresses
/// into files. This guards the three things that makes dangerous.
///
/// A SOURCE-TEXT GUARD, like sql_enum_literal_guard_test and friends. It
/// cannot run the Python -- that needs a database -- so it checks the
/// properties that would be catastrophic to lose and that a reader would not
/// notice going missing. The tool itself was run against the rebuild cluster
/// when it was written: both queries executed, which is also what proved
/// every column name in them is real.
void main() {
  final tool = File('tool/export_books.py').readAsStringSync();

  test('it refuses to write inside the repository', () {
    // The files are a dump of real people. A working tree is one `git add -A`
    // from publishing them, and that mistake is not recoverable from a public
    // remote. The default output is a temp folder; this catches the slip when
    // somebody passes --out explicitly.
    expect(tool, contains('Refusing to write inside the repository'));
    expect(tool, contains('os.path.abspath(outdir).startswith(repo + os.sep)'));
  });

  test('the password never reaches a command line', () {
    // Both reasons are recorded in tool/run_sql_tests.ps1, and the second one
    // actually happened here: a password containing a `$` broke libpq's URI
    // parsing, and libpq printed the mis-parsed HOST -- with the password in
    // it -- to stderr.
    expect(tool, contains("env['PGPASSWORD'] = conn['password']"));
    final call = tool.substring(tool.indexOf('proc = subprocess.run('));
    expect(call.substring(0, call.indexOf('capture_output')),
        isNot(contains("conn['password']")),
        reason: 'the credential must not be an argv entry -- a command line is '
            'readable by any other process on the machine for the life of '
            'the call');
  });

  test('the session it opens is read-only', () {
    // A report has no business writing, and saying so at runtime is stronger
    // than saying so in a comment -- the same reasoning run_sql_tests.ps1
    // records after finding a test file whose writes were hidden inside a
    // function it called.
    expect(tool,
        contains("env['PGOPTIONS'] = '-c default_transaction_read_only=on'"));
  });

  test('it exports the last four of an Aadhaar, never the hash', () {
    // The full number is not in the database at all -- aadhaar_number is NULL
    // for every row. Exporting the hash would be exporting a secret that
    // identifies nobody.
    expect(tool, contains('p.aadhaar_last4'));
    expect(tool.contains('aadhaar_hash'), isFalse,
        reason: 'a hash in a spreadsheet is a secret with no use');
    expect(tool.contains('p.aadhaar_number'), isFalse,
        reason: 'the column is NULL for every person; selecting it would put '
            'an empty column in front of somebody and imply it could fill');
  });

  test('a loan with no customer row is exported, not dropped', () {
    // A Customer membership with no `customers` row is a real state this
    // project found on 2026-09-17. An INNER JOIN here would silently shorten
    // the export, which is worse than a row with blanks in it.
    final loans = tool.substring(tool.indexOf('LOANS_SQL = """'));
    final body = loans.substring(0, loans.indexOf('"""', 20));
    expect(body, contains('LEFT JOIN customers cu'));
    expect(body, contains('LEFT JOIN persons cp'));
  });

  test('deleted collections are excluded from the totals', () {
    expect(RegExp(r'c\.deleted_at IS NULL').allMatches(tool).length,
        greaterThanOrEqualTo(3),
        reason: 'collections_count, last_collection and collected_total must '
            'each exclude deleted rows, or a deleted collection still counts '
            'as money received');
  });

  test('the SQL it sends contains no write', () {
    // SCOPED TO THE TWO QUERY CONSTANTS, not the whole file. The first
    // version of this searched the entire source and failed on "DROP" -- in
    // a Python constant named DROP that lists spreadsheet columns to omit,
    // and in a comment explaining that a LEFT JOIN is used so that no loan
    // gets dropped.
    //
    // That is the third time in this batch a guard was written to find a WORD
    // and found it in prose instead: `roleLetters` and `PageView` did the
    // same, and "stub picker" before them. A source-text check has to look
    // where the thing being guarded lives, not across the file that explains
    // it.
    String constant(String name) {
      final start = tool.indexOf('$name = """');
      final open = start + name.length + ' = """'.length;
      return tool.substring(open, tool.indexOf('"""', open));
    }

    for (final sql in [constant('PEOPLE_SQL'), constant('LOANS_SQL')]) {
      // Comment lines stripped: these queries carry long explanations, and an
      // explanation naming a verb is not a verb being sent.
      final code = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n')
          .toUpperCase();
      for (final verb in const [
        'INSERT ',
        'UPDATE ',
        'DELETE ',
        'DROP ',
        'ALTER ',
        'CREATE ',
        'TRUNCATE ',
        'GRANT ',
      ]) {
        expect(code.contains(verb), isFalse,
            reason: 'a query in export_books.py contains "$verb" -- this tool '
                'reads the database and writes files, and nothing else');
      }
      expect(code.trimLeft(), startsWith('SELECT'));
    }
  });
}
