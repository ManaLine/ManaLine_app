import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Everyone who opens the add-customer sheet must act on what it pops.
///
/// THE BUG THIS EXISTS FOR. The sheet ends with two buttons -- "Add & Issue
/// Loan" and "Add Only" -- and the ONLY difference between them is the value
/// it pops:
///
///     Navigator.of(context).pop(thenLoan ? id : null);
///
/// Five places opened it. Two read that value and pushed the loan screen.
/// Three wrote `.then((_) => reload())` and threw it away, so on those screens
/// "Add & Issue Loan" added the customer and stopped -- no loan screen, no
/// error, nothing to say it had not happened. One of the three was OW-004,
/// the screen whose entire job is customers.
///
/// It is invisible to `flutter analyze`: discarding a Future's value is
/// ordinary Dart. It is invisible to the layout tests, which never press the
/// button. And it is nearly invisible on a handset, because "Add Only" is a
/// perfectly plausible thing to have happened.
///
/// So the shape is checked instead: a caller either awaits the sheet into a
/// variable, or routes through /customer-new, which forwards the pop as its
/// own route result. `.then(` on this sheet is the exact spelling of the bug
/// and is refused.
void main() {
  final dart = <File>[];
  void walk(Directory d) {
    for (final e in d.listSync()) {
      if (e is Directory) {
        walk(e);
      } else if (e is File && e.path.endsWith('.dart')) {
        dart.add(e);
      }
    }
  }

  walk(Directory('lib'));

  /// Where the sheet is constructed directly, rather than reached by route.
  final direct = RegExp(r'ManaAddCustomerSheet\(');

  test('no caller discards the sheet result with .then', () {
    final offenders = <String>[];
    for (final f in dart) {
      final src = f.readAsStringSync();
      // The declaration itself is not a call site.
      if (f.path.endsWith('ow_004_customer_management.dart')) {
        // This file both declares and opens it; only the opening matters, and
        // the declaration lines cannot contain showModalBottomSheet.
      }
      for (final m in direct.allMatches(src)) {
        // Look back to the statement that opened it, and forward to what was
        // done with the result. 400 characters covers the builder plus the
        // call's tail without running into the next statement.
        final from = (m.start - 400).clamp(0, src.length);
        final to = (m.end + 400).clamp(0, src.length);
        final window = src.substring(from, to);
        if (!window.contains('showModalBottomSheet')) continue;
        if (window.contains(').then(')) {
          offenders.add(f.path);
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these drop the customerId, so "Add & Issue Loan" silently '
            'behaves as "Add Only": $offenders');
  });

  test('the sheet still signals the choice by what it pops', () {
    // If this ever stops being true the guard above is checking a contract
    // that no longer exists, which reads exactly like passing.
    final sheet =
        File('lib/features/owner_workspace/screens/ow_004_customer_management.dart')
            .readAsStringSync();
    expect(sheet, contains('pop(thenLoan ? id : null)'),
        reason: 'the add-customer sheet no longer pops the id, so every '
            'caller checked above is checking nothing');
    expect(sheet, contains('add_and_issue_loan'),
        reason: 'the button that makes the popped id meaningful is gone');
  });

  test('the scan is finding call sites at all', () {
    // A guard that checks nothing reads exactly like one that passes.
    var found = 0;
    for (final f in dart) {
      found += direct.allMatches(f.readAsStringSync()).length;
    }
    expect(found, greaterThanOrEqualTo(4),
        reason: 'only $found mentions of the sheet found; the pattern has '
            'stopped matching');
  });
}
