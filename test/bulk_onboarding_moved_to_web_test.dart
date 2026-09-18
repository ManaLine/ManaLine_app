import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The bulk onboarding wizard lives on the web build, and the handset points
/// at it.
///
/// The Owner's judgement, 2026-09-18: "for an user onboarding wizard via app
/// is difficult and messy and may go wrong - so we remove it from app, just so
/// a message there upon click redirects to website".
///
/// These are source assertions rather than widget tests on purpose. What has
/// to stay true is which ROUTER builds which screen, and that is a fact about
/// two files — a widget test would pump one of them and prove nothing about
/// the other.
/// Comments stripped before matching. The route in `router.dart` is now
/// documented with a paragraph explaining what it no longer builds, and that
/// paragraph names `BulkOnboardingWizardScreen` — so a naive search finds the
/// class in the very comment saying it is gone. This codebase has made that
/// mistake six times in two days.
String codeOf(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final handset = codeOf('lib/app/router.dart');
  final web = codeOf('lib/app/web_router.dart');

  test('nothing in the app navigates to the wizard', () {
    // The ROUTE still exists and still builds the real wizard, because
    // web_router_guard_test requires every web route to exist on Android AND
    // to resolve to the same widget class on both. That rule is why a bug
    // fixed once is fixed everywhere a screen is reachable, so the removal is
    // done by cutting the link rather than by forking the screen.
    //
    // What must stay true is that no UI path leads there.
    final appSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        // TWO EXCLUSIONS, and getting either wrong flags a file that is
        // meant to link there:
        //   lib/features/web/** is the web build's own UI -- web_home_screen
        //     SHOULD offer the wizard, that is the menu the signpost names.
        //   both routers register the route by definition. Excluded by NAME,
        //     because lib/app/web_router.dart has no path segment called
        //     'web' -- its segments are lib, app, web_router.dart.
        .where((f) => !f.uri.pathSegments.contains('web'))
        .where((f) => !const {'router.dart', 'web_router.dart'}
            .contains(f.uri.pathSegments.last));

    final linkers = <String>[];
    for (final f in appSources) {
      for (final line in f.readAsStringSync().split('\n')) {
        final code = line.trim();
        if (code.startsWith('//')) continue;
        // The signpost's own route shares this prefix, so match it exactly.
        if (RegExp(r"'/ow-bulk-onboarding'").hasMatch(code)) {
          linkers.add(f.uri.pathSegments.last);
        }
      }
    }
    expect(linkers, isEmpty,
        reason: 'these still send a phone into the seven-page wizard: '
            '$linkers');
  });

  test('the handset has a signpost route of its own', () {
    expect(handset, contains("path: '/ow-bulk-onboarding-web'"));
    expect(handset, contains('BulkOnboardingOnWebScreen'));
    // Android only. On the web build the wizard is right there, and telling
    // somebody to visit the website they are already on would be absurd.
    expect(web, isNot(contains('/ow-bulk-onboarding-web')));
  });

  test('the web build still runs the real wizard', () {
    // Moved, not deleted. If this ever fails the feature is gone from the
    // product, not merely from the handset.
    expect(web, contains('BulkOnboardingWizardScreen'));
  });

  test('both routers still register the route', () {
    // Keeping it in both is what makes the old entry point in OW-018 lead
    // somewhere that explains itself. A route removed from one router alone
    // also trips the two-router agreement test.
    expect(handset, contains("path: '/ow-bulk-onboarding'"));
    expect(web, contains("path: '/ow-bulk-onboarding'"));
    expect(web, contains("'/ow-bulk-onboarding'"));
  });

  test('the web menu offers it by name', () {
    // The signpost tells an Owner to "choose Bulk Onboarding from the menu".
    // If the menu does not say that, the instruction is false.
    final home =
        File('lib/features/web/screens/web_home_screen.dart').readAsStringSync();
    expect(home, contains("ref.t('bulk_onboarding')"));
    expect(home, contains("go('/ow-bulk-onboarding')"));
  });

  test('the signpost sends people to the front door, not a deep link', () {
    // A link straight to the wizard lands on a login screen and loses the
    // destination on the way through, because the handset session does not
    // travel to the browser.
    final screen = File(
            'lib/features/owner_workspace/screens/ow_bulk_onboarding_on_web.dart')
        .readAsStringSync();
    expect(screen, contains("websiteUrl = 'https://manaline.in/app/'"));
    expect(screen, isNot(contains('app/#/ow-bulk-onboarding')));
  });

  test('the signpost offers a way out when no browser answers', () {
    // launchUrl can fail on a device with no browser, and an Owner standing
    // with a laptop still needs the address.
    final screen = File(
            'lib/features/owner_workspace/screens/ow_bulk_onboarding_on_web.dart')
        .readAsStringSync();
    expect(screen, contains('Clipboard.setData'));
    expect(screen, contains("ref.t('no_browser_on_this_device')"));
  });

  test('one-at-a-time entry is still offered on the phone', () {
    // OW-018 has two doors and only one of them moved. Somebody arriving for
    // three investors must not be sent to a laptop for them.
    final screen = File(
            'lib/features/owner_workspace/screens/ow_bulk_onboarding_on_web.dart')
        .readAsStringSync();
    expect(screen, contains("ref.t('one_by_one_still_works_here')"));
  });
}
