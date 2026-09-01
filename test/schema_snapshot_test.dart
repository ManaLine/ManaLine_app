import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/schema_snapshot.dart';

/// The app and the database agree about what exists.
///
/// Two failure modes this catches, both of which have happened here and
/// neither of which the analyzer can see, because every one of them is a
/// perfectly ordinary Dart string:
///
///   * calling an RPC that is not there — a rename, a typo, or a function
///     dropped without its callers. `.schema('app').rpc('x')` for a missing
///     `x` is a runtime 404 on a screen that then says it could not load;
///   * a second overload on a function the app calls, which makes PostgREST
///     answer HTTP 300 (PGRST203) because it cannot choose between them. That
///     has bitten five times — `ledger_history` twice, `request_bf_update`,
///     `import_migrated_loans`, `record_collection` — and the standing rule
///     is to count overloads by hand after every signature change. Counting
///     is a machine's job.
///
/// The enum table is here for the third: literals invented for enum columns.
/// A Dart-side list that mirrors a database enum is asserted against the real
/// values, so a value that does not exist fails here rather than at the first
/// call in production.
final _rpcCall = RegExp(r"""rpc\(\s*['"]([a-z0-9_]+)['"]""");

Iterable<File> get _dartFiles => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('the guard catches a call to a function that is not there', () {
    // A scanner that finds nothing proves nothing.
    const bad = "await _db.schema('app').rpc('settlment_preview');";
    final name = _rpcCall.firstMatch(bad)!.group(1);
    expect(name, 'settlment_preview');
    expect(manaAppFunctions.contains(name), isFalse,
        reason: 'the typo is what must fail');

    const good = "await _db.schema('app').rpc('settlement_preview');";
    expect(manaAppFunctions.contains(_rpcCall.firstMatch(good)!.group(1)),
        isTrue);
  });

  test('every RPC the app calls exists in the schema', () {
    final missing = <String>[];
    for (final file in _dartFiles) {
      final source = file.readAsStringSync();
      for (final m in _rpcCall.allMatches(source)) {
        final name = m.group(1)!;
        if (manaAppFunctions.contains(name)) continue;
        final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        missing.add('${file.path}:$line calls $name');
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'These call an app function the snapshot has never heard of. '
          'Either the name is wrong, or the schema moved and '
          'test/support/schema_snapshot.dart needs regenerating — the header '
          'of that file has the query. Offenders:\n  ${missing.join('\n  ')}',
    );
  });

  test('no RPC the app calls has more than one overload', () {
    final called = <String>{};
    for (final file in _dartFiles) {
      for (final m in _rpcCall.allMatches(file.readAsStringSync())) {
        called.add(m.group(1)!);
      }
    }

    final ambiguous = called
        .where((n) => (manaAppFunctionOverloads[n] ?? 1) > 1)
        .toList()
      ..sort();

    expect(
      ambiguous,
      isEmpty,
      reason: 'PostgREST cannot choose between two functions of the same name '
          'and answers HTTP 300 (PGRST203). Changing a parameter list is DROP '
          'then CREATE, never CREATE OR REPLACE. Ambiguous: $ambiguous',
    );
  });

  test('functions with overloads are the ones known to be SQL-internal', () {
    // An overload is only harmless while nothing reaches it through
    // PostgREST. If one of these ever gains a Dart caller the test above
    // starts failing, which is the intended alarm.
    final overloaded = manaAppFunctionOverloads.entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toSet();
    expect(
      overloaded.difference(manaInternalOnlyOverloads),
      isEmpty,
      reason: 'A function grew a second overload without being recorded as '
          'SQL-internal. Either collapse it, or add it to '
          'manaInternalOnlyOverloads with the reason.',
    );
  });

  group('Dart lists that mirror a database enum', () {
    // Where the app writes enum values as strings, the set it can produce must
    // be a subset of what the column accepts. Invented values are exactly the
    // 'General' / 'Self Request' / 'Full Payment' class of bug.
    void expectSubsetOf(String enumName, Iterable<String> used) {
      final valid = manaDbEnums[enumName];
      expect(valid, isNotNull, reason: '$enumName is not in the snapshot');
      final bad = used.where((v) => !valid!.contains(v)).toList();
      expect(bad, isEmpty,
          reason: '$bad are not values of $enumName. Valid: $valid');
    }

    test('withdrawal types the app derives', () {
      expectSubsetOf('withdrawal_type_enum', [
        'Interest Only',
        'Principal Partial',
        'Principal Full',
        'Principal + Interest',
      ]);
    });

    test('roles a person can request', () {
      expectSubsetOf(
          'membership_request_role_enum', ['Agent', 'Investor', 'Customer']);
    });

    test('collection results the round can record', () {
      expectSubsetOf('collection_result_type_enum',
          ['Full', 'Partial', 'Excess', 'No Collection']);
    });

    test('payment modes the settlement splits by', () {
      expectSubsetOf(
          'payment_mode_enum', ['Cash', 'UPI', 'Bank Transfer', 'Cheque']);
    });

    test('notification types the server writes', () {
      // 'General' lived here for one migration and threw on first call.
      expectSubsetOf('notification_type_enum',
          ['Owner Approval Confirmation', 'Pending Approval', 'Other']);
    });

    test('onboarding methods a membership can be created with', () {
      // 'Self Request' lived here for one migration and threw on first call.
      expectSubsetOf('onboarding_method_enum',
          ['Direct Registration', 'ID Lookup', 'Migration/Pre-Existing']);
    });

    test('repayment types the collection window branches on', () {
      expectSubsetOf('repayment_frequency_enum', ['Daily', 'Weekly', 'Monthly']);
    });
  });
}
