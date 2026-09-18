import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/gen_app_map.dart';

/// docs/APP_MAP.md is generated. This is what stops it becoming a lie.
///
/// WHY A GUARD AND NOT A RULE. Every stale document in this repo went stale
/// the same way: it was true when written, somebody changed the code, and
/// nothing failed. README's Status table lost seven screens and 672 tests
/// that way; CLAUDE.md's test count is older still. Neither was dishonest —
/// they were unguarded. A 84-row route inventory maintained by memory would
/// rot faster than either, because every screen edit is a chance to forget.
///
/// So the document is derived, and this test fails the moment the committed
/// copy stops matching what the sources say. The fix is never to edit the
/// document: run `dart run tool/gen_app_map.dart`.
///
/// THE SECOND HALF OF THIS FILE IS THE MORE IMPORTANT ONE. A generator that
/// silently finds less is worse than no generator, because a shrunken
/// inventory reads exactly like an accurate one. The first run of this tool
/// found 7 routes out of 83 and reported it cheerfully: router.dart's
/// comments are full of apostrophes, each one opened a string literal that
/// never closed, and the parser swallowed the file. So the floors below are
/// not decoration — they are the specific failure this guard exists to catch,
/// and the same reasoning as `sql_enum_literal_guard_test.dart` failing when
/// it stops finding literals to check.
void main() {
  test('docs/APP_MAP.md matches what the routers actually declare', () {
    final committed = File('docs/APP_MAP.md');
    expect(committed.existsSync(), isTrue,
        reason: 'docs/APP_MAP.md is missing. Run: dart run tool/gen_app_map.dart');

    // Line endings are normalised before comparing, and `.gitattributes`
    // pins the file to LF as well. Belt and braces on purpose: this repo has
    // already lost a day to CRLF: `* text=auto` with core.autocrlf=true hands
    // a Windows checkout a CRLF copy of a byte-correct file, and a rebuild
    // died at migration 261 because one side of a text match carried \r and
    // the other did not. A guard that fails on a fresh clone while passing
    // for whoever generated the file teaches people to ignore it.
    String lf(String s) => s.replaceAll('\r\n', '\n');

    expect(
      lf(committed.readAsStringSync()),
      lf(buildAppMap()),
      reason: 'docs/APP_MAP.md is out of date with the source.\n'
          'Do not edit it by hand — run: dart run tool/gen_app_map.dart',
    );
  });

  group('the generator is still reading the routers', () {
    final routes = parsedRoutes();

    test('finds both routers, not just the handset one', () {
      // Reading only router.dart made /web-home look like a dead end at
      // runtime. It is a route on the restricted web build. A generated
      // document that invents a bug costs more than it saves.
      expect(routes.any((r) => r.surfaces.contains('handset')), isTrue,
          reason: 'no handset routes parsed — lib/app/router.dart unreadable?');
      expect(routes.any((r) => r.surfaces.contains('web')), isTrue,
          reason: 'no web routes parsed — lib/app/web_router.dart unreadable?');
    });

    test('finds the whole route list, not a truncated one', () {
      // A floor, not the exact figure: routes get added, and a test that
      // fails on every new screen teaches people to edit the number.
      // It sits far enough below the real count (84 when written) to allow
      // real deletions, and far enough above a parse failure to catch one.
      expect(routes.length, greaterThan(70),
          reason: 'only ${routes.length} routes parsed. The parser has '
              'probably broken, not the app. Check tool/gen_app_map.dart.');
    });

    test('every route builds something or redirects somewhere', () {
      final empty = routes
          .where((r) => r.widgets.isEmpty && r.redirectsTo == null)
          .map((r) => r.path)
          .toList();
      expect(empty, isEmpty,
          reason: 'these routes parsed with no screen and no redirect, which '
              'means the builder was not understood: $empty');
    });

    test('the locked screen-ID routes are all present', () {
      // The routing contract: one route per locked screen ID. These five are
      // load-bearing paths from five different workspaces — if the parser
      // ever stops seeing them, it has stopped seeing most of the file.
      for (final path in ['/lr-001', '/ow-001', '/ag-001', '/cw-001', '/iw-001']) {
        expect(routes.map((r) => r.path), contains(path),
            reason: '$path was not parsed out of the routers');
      }
    });
  });
}
