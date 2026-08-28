import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/app/router.dart';
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';

import 'support/mana_harness.dart';

/// The defect these pin: nineteen routes fell back to a fabricated id --
/// 'stub-business-id', 'stub-agent-id' and the rest -- whenever the session
/// had lost the real one. The screen opened, queried with a string Postgres
/// cannot cast to uuid, and reported "Something went wrong". The session had
/// simply expired, which the app knew and never said.
void main() {
  // The session writes through flutter_secure_storage, which needs both the
  // binding and an in-memory store standing in for the platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    seedSecureStorage();
    await ManaSession.instance.clear();
  });

  group('a route that cannot work does not open', () {
    test('no person at all goes back to the start', () {
      expect(manaSessionRedirectFor('/ow-006'), '/lr-001');
      expect(manaSessionRedirectFor('/ag-002'), '/lr-001');
    });

    test('a person with no business picks one', () async {
      await ManaSession.instance.setSession(accessToken: 't', personId: '2');
      expect(manaSessionRedirectFor('/ow-006'), '/lr-012');
      expect(manaSessionRedirectFor('/ag-002'), '/lr-012');
    });

    test('a person with a business is left alone', () async {
      await ManaSession.instance.setSession(accessToken: 't', personId: '2');
      ManaSession.instance.rememberBusinessId('b1');
      expect(manaSessionRedirectFor('/ow-006'), isNull);
    });
  });

  group('choosing a business is what makes the workspace reachable', () {
    // The bug: pick a business on LR-012, pick a role on LR-013, and land
    // back on LR-012.
    //
    // The chosen business lived only in Riverpod, and ManaSession's copy --
    // the one this guard reads -- was written by _resolveBusinessId inside the
    // route BUILDER. GoRouter runs redirect BEFORE the builder, so on the
    // first navigation to /ow-001 the guard saw no business, bounced to
    // /lr-012, and the builder that would have recorded it never ran. It only
    // showed up on a session with nothing stored yet: a fresh install, or the
    // first login after a logout, since clear() nulls it.
    test('selecting the business is enough to reach its workspace', () async {
      await ManaSession.instance.setSession(accessToken: 't', personId: '2');
      expect(manaSessionRedirectFor('/ow-001'), '/lr-012',
          reason: 'nothing chosen yet');

      // LR-012's own selection, nothing else -- no route has built.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(authFlowProvider.notifier).selectBusiness('b1');

      expect(manaSessionRedirectFor('/ow-001'), isNull,
          reason: 'the business was chosen; the workspace is reachable');
      expect(manaSessionRedirectFor('/ag-001'), isNull);
    });

    test('a route carrying its own business is usable whatever is stored',
        () async {
      // Belt and braces: the redirect can see `extra`, and a navigation that
      // names a business does not need the session to have remembered one.
      await ManaSession.instance.setSession(accessToken: 't', personId: '2');
      expect(manaSessionRedirectFor('/ow-001', carriedBusinessId: 'b1'), isNull);
      expect(manaSessionRedirectFor('/ow-001', carriedBusinessId: ''), '/lr-012',
          reason: 'an empty string is not a business');
    });
  });

  group('what it must never intercept', () {
    test('login and registration are how a session is obtained', () {
      // Redirecting these to /lr-001 with no person would loop forever.
      expect(manaSessionRedirectFor('/lr-001'), isNull);
      expect(manaSessionRedirectFor('/lr-004'), isNull);
      expect(manaSessionRedirectFor('/lr-012'), isNull);
    });

    test('admin has its own identity system', () {
      // admin_accounts, not persons — currentPersonId is null for an admin
      // and always will be.
      expect(manaSessionRedirectFor('/admin-login'), isNull);
      expect(manaSessionRedirectFor('/admin-panel'), isNull);
    });
  });
}
