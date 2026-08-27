import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards a client list that has to match a database enum exactly.
///
/// The round offered four visit reasons -- Customer Not Available, Customer
/// Refused, Requested Later Visit, Other -- and exactly ONE of them was a
/// real value of no_collection_reason_enum. The string in that dropdown is
/// the wire value, so saving a visit failed with
///
///   invalid input value for enum no_collection_reason_enum: "Customer Refused"
///
/// on three choices out of four. Save Visit worked only if the Agent happened
/// to pick the bottom of the list.
///
/// It is invisible to flutter analyze, invisible to every widget test -- the
/// dropdown renders perfectly with wrong values in it -- and only fails
/// against the real database, at a doorstep, after the Agent has already
/// decided what to record.
///
/// Regenerate with:
///
///   select enumlabel from pg_enum e
///     join pg_type t on t.oid = e.enumtypid
///    where t.typname = 'no_collection_reason_enum'
///    order by e.enumsortorder;
const _enumValues = <String>[
  'Customer Not Home',
  'House Locked',
  'Customer Out Of Village',
  'Requested Extension',
  'Medical Emergency',
  'Festival',
  'Natural Disaster',
  'Phone Call Not Answered',
  'Shifted Village',
  'Refused Payment',
  'Other',
];

void main() {
  const source =
      'lib/features/owner_workspace/screens/ow_006_collection_mode.dart';

  /// The `_reasons` list as the screen actually declares it.
  List<String> declaredReasons() {
    final text = File(source).readAsStringSync();
    final start = text.indexOf('static const _reasons = [');
    expect(start, isNot(-1), reason: '_reasons has moved or been renamed');
    final end = text.indexOf('];', start);
    final body = text.substring(start, end);
    return RegExp("'([^']+)'")
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toList();
  }

  test('every reason offered is a value the database accepts', () {
    final offered = declaredReasons();
    final unknown = offered.where((r) => !_enumValues.contains(r)).toList();

    expect(
      unknown,
      isEmpty,
      reason: 'These are not values of no_collection_reason_enum, so saving a '
          'visit with one raises invalid input value and the Agent loses the '
          'visit they just recorded:\n  ${unknown.join('\n  ')}',
    );
  });

  test('every reason the database accepts is offered', () {
    // The other direction matters too: a reason that exists in the schema and
    // not in the app is a reason an Agent standing at a locked house cannot
    // record, so they pick something else and the record says the wrong thing.
    final offered = declaredReasons();
    final missing = _enumValues.where((v) => !offered.contains(v)).toList();

    expect(missing, isEmpty,
        reason: 'The database accepts these and the round does not offer '
            'them:\n  ${missing.join('\n  ')}');
  });

  test('each reason has a label key, and no key is left over', () {
    final text = File(source).readAsStringSync();
    final start = text.indexOf('static const _reasonKeys = {');
    expect(start, isNot(-1), reason: '_reasonKeys has moved or been renamed');
    final body = text.substring(start, text.indexOf('};', start));

    final mapped = RegExp("'([^']+)':\\s*'([^']+)'")
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();

    // A value with no key renders as the raw key at a doorstep; a key with no
    // value is dead weight that outlived whatever used it.
    expect(mapped, containsAll(_enumValues),
        reason: 'a reason with no label key renders as the key itself');
    expect(mapped.difference(_enumValues.toSet()), isEmpty,
        reason: 'a label key for a reason that no longer exists');
  });
}
