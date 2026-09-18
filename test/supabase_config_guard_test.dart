import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A build with no credentials must SAY SO, including when the shell handed
/// the build empty ones.
///
/// THE CASE THAT GOT THROUGH. `--dart-define=SUPABASE_URL=$URL` with `$URL`
/// unset does not omit the define — it supplies the empty string. Dart then
/// returns `''` rather than the declared default, dart2js folds the
/// now-unreachable `REPLACE-ME` literal out of the bundle entirely, and
/// `''.contains('REPLACE-ME')` is false. The guard written specifically to
/// catch a misconfigured build waved through the commonest way to make one.
///
/// It is invisible from the source: `SupabaseConfig.url` reads exactly the
/// same either way. It shows up in the ARTEFACT — a bundle containing
/// neither the project ref nor the placeholder is that case and nothing else.
///
/// These tests read the source rather than the build, because the build under
/// test here is produced by whatever command somebody typed. Pair them with
/// the bundle check recorded in docs/DEPLOY.md.
void main() {
  final src = File('lib/shared/supabase_config.dart').readAsStringSync();

  test('isPlaceholder treats an empty define as missing', () {
    expect(src, contains('url.trim().isEmpty'),
        reason: 'an unset shell variable produces an EMPTY define, not an '
            'absent one — the default never applies and the placeholder is '
            'compiled out');
    expect(src, contains('anonKey.trim().isEmpty'));
  });

  test('and still catches the placeholder itself', () {
    // The original case: built with no --dart-define at all, so the defaults
    // apply and the app points at a host that does not exist. Requests there
    // do not fail fast, they HANG — every screen renders raw translation keys
    // and login claims "No internet connection" on a healthy network.
    expect(src, contains("contains('REPLACE-ME')"));
  });

  test('the placeholder defaults are still declared', () {
    // Removing them would make an omitted define compile to '' and land in
    // the empty branch above — which now reports correctly, but the named
    // host is what makes the failure legible in a network log.
    expect(src, contains('https://REPLACE-ME.supabase.co'));
    expect(src, contains('REPLACE-ME-ANON-KEY'));
  });
}
