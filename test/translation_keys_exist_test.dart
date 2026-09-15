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

/// Keys that ARE in ui_translations but that NO migration ever created.
///
/// Not the same thing this list held before, and the difference is the whole
/// point of having measured it.
///
/// WHAT THIS WAS. On 2026-09-15 it held 69 names, described as "the ledger
/// drift" -- keys applied to production whose .sql file was never written
/// locally. That was measured: 421 ledger rows against 418 local files, 42
/// applied migrations with no file.
///
/// WHAT HAPPENED. Seventeen of the forty-two were the same migration under a
/// hand-written timestamp, matched by CONTENT fingerprint and renamed with
/// `git mv`. The other twenty-five were restored from
/// supabase_migrations.schema_migrations by tool/restore_missing_migrations.ps1
/// -- psql writing each file directly, because 32 KB of Telugu strings retyped
/// by hand is where a silent corruption enters and a mangled label is
/// invisible to every guard here.
///
/// That took this list from 69 to 21.
///
/// WHAT THE REMAINING 21 WERE, and how the list reached zero. Every ledger
/// row had a local file, but 21 keys were in ui_translations anyway -- which
/// meant they had been inserted OUTSIDE the migration system: the Table
/// Editor, or a statement pasted into the SQL editor. No migration created
/// them, so no migration could recreate them, and a rebuild from an empty
/// database would have come up short by exactly these.
///
/// Deleting the 22 duplicate drafts added 19 more, for 40.
///
/// 20260915140000_restore_orphaned_translation_keys.sql inserts all forty.
/// Its English and Telugu were read out of production by psql and written
/// straight to the file -- see the note there. Against production it is a
/// no-op (INSERT 0 0, confirmed); it exists so the repo can rebuild.
///
/// THE LIST IS NOW EMPTY, AND SHOULD STAY THAT WAY. It is kept rather than
/// deleted because the comment above it is the argument for keeping it empty.
/// A name added here is a key the handset renders raw on a fresh database;
/// the fix is a migration, not an entry. Listed BY NAME rather than skipped by
/// a pattern, because the whole value of this guard is that a NEW key with no
/// migration fails immediately -- a wildcard would have swallowed
/// village_search_by_pin along with these.
const _appliedButFileMissing = <String>{};

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
