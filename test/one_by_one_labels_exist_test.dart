import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every label the one-by-one door asks for has a row behind it.
///
/// A key with no row renders as the RAW KEY on the handset. This project has
/// shipped exactly that to a live screen -- the registration form's address
/// section showed "use_my_location" to real users -- and it was caught on a
/// phone rather than by any test, because the layout tests read a vendored
/// fixture and therefore always found a value.
///
/// The door is new and large: three stages, a village book, a loan form and
/// five problem messages. Checking them by opening the app means noticing one
/// raw key among dozens of correct ones.
void main() {
  final migrations = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  /// The files that make up this door.
  const screens = [
    'lib/features/owner_workspace/screens/ow_one_by_one_migration.dart',
    'lib/features/owner_workspace/screens/ow_village_book.dart',
    'lib/features/owner_workspace/screens/ow_village_customers.dart',
    // The two screens that signpost it. ow_018 is where an Owner migrating a
    // book actually stands, and the wizard's Finish page is the last moment
    // anything can be added -- both gained cheti labels, and a raw key on
    // either is the same failure as one inside the door itself.
    'lib/features/owner_workspace/screens/ow_018_business_migration.dart',
    'lib/features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart',
  ];

  test('no screen in the one-by-one door asks for a key that does not exist', () {
    final missing = <String>[];
    for (final path in screens) {
      final source = File(path).readAsStringSync();
      for (final m in RegExp(r"""ref\.t\('([a-z0-9_]+)'\)""").allMatches(source)) {
        final key = m.group(1)!;
        // The INSERT lists them as ('key', 'English', 'Telugu').
        if (!migrations.contains("('$key',")) missing.add('$path: $key');
      }
    }
    expect(missing, isEmpty,
        reason: 'these render as raw keys on the handset: $missing');
  });

  test('the scan is finding keys at all, not passing on an empty sweep', () {
    // A guard that checks nothing reads exactly like one that passes.
    var found = 0;
    for (final path in screens) {
      found += RegExp(r"""ref\.t\('([a-z0-9_]+)'\)""")
          .allMatches(File(path).readAsStringSync())
          .length;
    }
    expect(found, greaterThan(15),
        reason: 'only $found keys found across the door; the pattern has '
            'stopped matching');
  });
}
