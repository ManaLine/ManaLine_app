import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/schema_snapshot.dart';

/// Every `app.` function a migration calls is a function that exists.
///
/// THE GAP THIS CLOSES. `sql_enum_literal_guard_test.dart` catches an invented
/// enum VALUE. It does not catch an invented function NAME, and I walked into
/// exactly that an hour after writing it: a migration called
/// `app.person_current_village`, which I had not written. It applied perfectly.
/// plpgsql bodies are not type-checked at CREATE time, so a call to a function
/// that has never existed is indistinguishable from a correct one right up
/// until something invokes it — which, for a search RPC, means the next time a
/// person types a name into a box.
///
/// Same failure shape as the enum literals and the same reason: CREATE says
/// yes to almost anything inside a function body.
///
/// WHAT IT CHECKS: every `app.<name>(` appearing in migration SQL, against
/// `manaAppFunctions` in the snapshot — the set of functions that exist NOW.
/// Line comments are stripped first, because these files explain their own
/// history and naming a dead function in prose is not calling it.
///
/// WHY "EXISTS NOW" IS THE RIGHT QUESTION for a historical file: a migration
/// that ran last March against a function since dropped is not a problem — it
/// ran. A migration that names a function nobody has ever written is. The
/// difference is unknowable from the file alone, so the handful of genuinely
/// retired names are listed below and everything else must resolve.
const _appCall = r'\bapp\.([a-z_][a-z0-9_]*)\s*\(';

/// Functions that existed when their migration ran and have since been dropped.
///
/// Verified against pg_proc rather than assumed — both return zero rows today.
/// A name belongs here only when the migration naming it ALREADY RAN
/// successfully; a name that has never existed is the bug this file is for.
const _retired = <String, String>{
  'owner_search_customer':
      'replaced by owner_search_person; the two migrations naming it '
          '(20260825074846, 20260825100741) both applied at the time',
  'support_apply_suspension':
      'support-admin RPC from the module 19/20 migrations, dropped since; '
          'those migrations applied at the time',
};

void main() {
  final dir = Directory('supabase/migrations');
  final files = dir.existsSync()
      ? (dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  final called = <String, Set<String>>{};
  for (final file in files) {
    // Strip line comments: these migrations describe the bugs they fix, and a
    // dead function named in prose is not a call.
    final sql = file
        .readAsStringSync()
        .replaceAll(RegExp(r'--[^\n]*'), '');
    for (final m in RegExp(_appCall, caseSensitive: false).allMatches(sql)) {
      called
          .putIfAbsent(m.group(1)!.toLowerCase(), () => <String>{})
          .add(file.uri.pathSegments.last);
    }
  }

  test('there are migrations, and they call app functions', () {
    expect(files, isNotEmpty);
    // A matcher that stops matching turns the assertion below into a
    // guarantee about nothing — the failure this repo keeps meeting.
    expect(called, isNotEmpty,
        reason: 'No app.* call found in any migration. The matcher has '
            'drifted, or these calls moved somewhere this test cannot see.');
  });

  test('every app function a migration calls exists today', () {
    final unknown = <String>[];
    called.forEach((name, inFiles) {
      if (manaAppFunctions.contains(name)) return;
      if (_retired.containsKey(name)) return;
      final where = inFiles.toList()..sort();
      unknown.add('app.$name — called in ${where.take(3).join(', ')}'
          '${where.length > 3 ? ' (+${where.length - 3} more)' : ''}');
    });

    expect(
      unknown,
      isEmpty,
      reason: 'These migrations call an app function that does not exist. '
          'plpgsql applies that cleanly and throws 42883 on the first '
          'invocation, which may be months later:\n  ${unknown.join('\n  ')}\n\n'
          'Either the function was never written, or the snapshot is stale — '
          'regenerate it (see schema_snapshot.dart) before assuming the '
          'former. If it is genuinely retired and its migration already ran, '
          'add it to _retired with the reason.',
    );
  });

  test('the retired list has no stale entries', () {
    // An entry covering a name no migration mentions any more is protecting
    // nothing, and reads as though it still matters.
    final stale = _retired.keys.toSet().difference(called.keys.toSet());
    expect(stale, isEmpty,
        reason: 'Listed as retired but no longer called by any migration. '
            'Remove:\n  ${stale.join('\n  ')}');
  });

  test('a retired name is not also a live function', () {
    // If one comes back, the exemption silently stops meaning what it says.
    final resurrected =
        _retired.keys.where(manaAppFunctions.contains).toList();
    expect(resurrected, isEmpty,
        reason: 'These exist again, so they are not retired. Remove them from '
            '_retired:\n  ${resurrected.join('\n  ')}');
  });
}
