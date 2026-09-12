import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "MLPI142496232 · Not Provided", drawn in the line that identifies a person.
///
/// It was never a UI placeholder. The literal string was STORED, in
/// persons.father_husband_name, put there by a one-off bootstrap script that
/// needed something for a NOT NULL column and wrote a sentence. Universal
/// Search then showed it beside real fathers' names, in the line an Owner uses
/// to tell two people of the same name apart.
///
/// An absent fact should render as absent, not as a sentence about its
/// absence.
void main() {
  group('nothing writes a sentence into a name column', () {
    test('no SQL in this repo seeds a placeholder name', () {
      // Narrowed twice, because the obvious version cried wolf. Scanning raw
      // text flagged this guard's OWN explanatory comment in the bootstrap
      // script, and an 'n/a' that was a log-message argument in the schema
      // tests. Neither is a value in a name column, and a guard that reports
      // things that are fine is one people learn to skip.
      //
      // So: comments are stripped first, and a placeholder only counts when it
      // appears in the SAME STATEMENT as a name column. That is the shape of
      // the actual defect -- an INSERT that put a sentence where a father's
      // name goes.
      final offenders = <String>[];
      final placeholders = RegExp(
          r"'(Not Provided|Not Available|N/A|Unknown|None|NIL)'",
          caseSensitive: false);

      for (final f in Directory('supabase')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))) {
        // RegExp('--.*') rather than splitting on lines: Dart's dot does
        // not match a newline, so this strips each comment to the end of
        // its own line and nothing further.
        final withoutComments =
            f.readAsStringSync().replaceAll(RegExp('--.*'), '');

        for (final statement in withoutComments.split(';')) {
          if (!statement.contains('father_husband_name') &&
              !statement.contains('full_name')) {
            continue;
          }
          // The migration that REMOVED the value has to name it in its own
          // WHERE clause. It is the cure, not the disease.
          if (f.path.contains('not_provided_is_not_a_fathers_name')) continue;
          final hit = placeholders.firstMatch(statement);
          if (hit != null) offenders.add('${f.path}: ${hit.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'a name column is being seeded with a sentence about a '
              'missing fact, which is what reached Universal Search: '
              '$offenders');
    });

    test('the guard is looking at real files, not an empty directory', () {
      // A guard that finds nothing to scan reads exactly like one that passes.
      final sqlFiles = Directory('supabase')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .length;
      expect(sqlFiles, greaterThan(10),
          reason: 'found $sqlFiles SQL files; the scan above is checking '
              'nothing if this is near zero');
    });
  });

  group('an absent fact leaves no mark on screen', () {
    test('the customer row joins only the parts that exist', () {
      // A missing father's name used to leave the line starting with " · ",
      // and a missing village left two separators together -- which reads as a
      // rendering fault rather than as an absent fact.
      final source = File('lib/shared/customer_row.dart').readAsStringSync();
      expect(source, contains("part.trim().isNotEmpty"),
          reason: 'empty segments are being interpolated into the identity '
              'line again');
      expect(source, isNot(contains(r"'${customer.fatherHusbandName} · ")),
          reason: 'the bare interpolation is back, and it cannot drop an '
              'empty part');
    });

    test('the screens that identify people all drop empty segments', () {
      // Universal Search and the Add Customer sheet were already correct; this
      // keeps them that way, since they are where two people of one name are
      // told apart.
      for (final path in const [
        'lib/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart',
        'lib/features/owner_workspace/screens/ow_004_customer_management.dart',
      ]) {
        expect(File(path).readAsStringSync(),
            contains('fatherHusbandName.isNotEmpty'),
            reason: '$path draws a father/husband name without checking it is '
                'there');
      }
    });
  });
}
