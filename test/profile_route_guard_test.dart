import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';

/// Tapping your own photo opens your profile. Always.
///
/// THE BUG THIS EXISTS FOR: `manaLastUsedProfileRoute()` resolved the profile
/// screen from whichever role the device last used — /ag-009, /cw-006, /iw-005,
/// /ow-016 — and returned NULL when there was no role to resolve. Both callers
/// then fell back to '/settings'.
///
/// So a person who had registered and joined no business tapped their own
/// profile photo and got general settings. Karri Priyanka, 8897948012: no
/// memberships, owns nothing, every remembered id null.
///
/// The comment at the call site said that case was "a genuinely first-ever
/// login with no profile to show yet". That was the wrong reading and it is
/// what kept the bug alive: she has a name, an MLID, a photo and an address.
/// What she has no WORKSPACE, and all four profile routes are named after one.
///
/// The fix is /profile, which reuses CW-006 — a screen that was never actually
/// customer-scoped, taking a personId and reading persons/person_addresses/
/// locations.
void main() {
  test('a person with no workspace still gets a profile', () {
    // ManaSession.instance starts with every id null and nothing hydrated,
    // which is exactly the state this bug needed: registered, joined nothing.
    final session = ManaSession.instance;
    expect(session.lastAgentId, isNull, reason: 'test assumes a fresh session');
    expect(session.lastCustomerId, isNull);
    expect(session.lastInvestorId, isNull);
    expect(session.lastBusinessId, isNull);

    expect(
      manaLastUsedProfileRoute(),
      '/profile',
      reason: 'With no role to resolve this used to return null, and both '
          'callers fell back to /settings — tapping your own photo opened '
          'general settings.',
    );
  });

  test('every route the resolver can name is registered', () {
    // A resolver pointing at a route GoRouter does not know throws at the tap,
    // which is a worse failure than the one being fixed here.
    final router = File('lib/app/router.dart').readAsStringSync();
    for (final route in const [
      '/ag-009',
      '/cw-006',
      '/iw-005',
      '/ow-016',
      '/profile',
    ]) {
      expect(
        router.contains("path: '$route'"),
        isTrue,
        reason: '$route is a possible answer from manaLastUsedProfileRoute '
            'but no GoRoute declares it.',
      );
    }
  });

  test('no caller still falls back to settings', () {
    // The resolver is total now. A `?? '/settings'` left behind would be dead
    // code that reads as a live branch, and the next person to see it would
    // reasonably assume the null case still happens.
    for (final path in const [
      'lib/features/login_registration/screens/lr_012_business_selector.dart',
      'lib/shared/settings_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        RegExp(r"manaLastUsedProfileRoute\(\)\s*\?\?").hasMatch(source),
        isFalse,
        reason: '$path still guards manaLastUsedProfileRoute() with ?? — it '
            'cannot return null any more.',
      );
    }
  });
}
