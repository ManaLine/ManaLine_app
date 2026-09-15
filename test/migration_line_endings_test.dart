import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No migration file carries a carriage return.
///
/// THE FAILURE THIS PREVENTS, which cost an afternoon on 2026-09-15.
///
/// Six migrations patch a live function instead of rewriting it: they read
/// `pg_get_functiondef()` and run `replace()` on its text, so that the eight
/// branches already in a nine-branch UNION are left exactly as they are rather
/// than retyped from a paste. That is the right instinct. It also makes the
/// migration depend on the BYTES of an earlier migration file, because the
/// stored function body keeps whatever line endings that file had.
///
/// `20260823051953` was CRLF and `20260824172008` was LF. The anchor text was
/// present in the body, visibly identical, character for character in any
/// editor — and could not match, because one side carried `\r` and the other
/// did not. The migration's own guard fired and a rebuild from empty stopped at
/// 261 of 426 with a message that reads like the function had changed. It had
/// not. Nothing had changed. The two files had simply been checked out by
/// different rules.
///
/// 97 of 426 migration files were CRLF at that point, and no rule said which
/// they should be, so which ones a checkout produced depended on the machine's
/// `core.autocrlf`. `.gitattributes` now pins `*.sql text eol=lf`; this test is
/// what notices when something writes CRLF anyway — a PowerShell `Set-Content`
/// or `Out-File`, both of which default to CRLF, and both of which have written
/// files into this directory before.
void main() {
  test('every migration is LF, because six of them match on exact text', () {
    final offenders = <String>[];
    for (final f in Directory('supabase/migrations').listSync().whereType<File>()) {
      if (!f.path.endsWith('.sql')) continue;
      if (f.readAsBytesSync().contains(13)) {
        offenders.add(f.uri.pathSegments.last);
      }
    }
    expect(offenders, isEmpty,
        reason: 'these hold a carriage return: ${offenders.join(', ')}. A '
            'migration that patches a function body by text will silently fail '
            'to match against one of these. Rewrite with LF endings — '
            'PowerShell Set-Content and Out-File default to CRLF');
  });

  test('the sweep is reading files at all', () {
    // A guard that checks nothing reads exactly like one that passes.
    final count = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .length;
    expect(count, greaterThan(400), reason: 'only $count migrations found');
  });
}
