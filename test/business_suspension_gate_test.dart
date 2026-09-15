import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/business_suspension_gate.dart';

/// SP-001, and the guard that stops it going quiet a second time.
///
/// THE FAILURE THIS PREVENTS. The gate, the redirect helper, the screen and
/// the route all existed for weeks and **nothing called any of them**. The file
/// header claimed it had wired LR-012; it had not. LR-012 drew a red
/// "Suspended" pill on the card and left the card tappable. RLS did not catch
/// it either — no policy on any table references `business_status`. Each layer
/// was written believing the other one had it.
///
/// Nothing in `flutter analyze` or `flutter test` could see this, because an
/// uncalled function is not an error. It took
/// `supabase/tests/multi_tenancy_isolation_tests.sql` executing for the first
/// time, on 2026-09-15, to say so.
///
/// So the census below is the point of this file. The verdict tests are easy;
/// the thing that actually broke was WIRING, and wiring is what goes missing.
void main() {
  group('the verdict', () {
    test('Active is allowed', () {
      expect(
        manaSuspensionVerdictFor(businessStatus: 'Active', roles: const ['Agent']),
        ManaSuspensionVerdict.allowed,
      );
    });

    test('anything else is suspended', () {
      for (final status in ['Suspended', 'Closed', 'Temporarily Disabled']) {
        expect(
          manaSuspensionVerdictFor(businessStatus: status, roles: const ['Agent']),
          ManaSuspensionVerdict.suspended,
          reason: '$status must block',
        );
      }
    });

    test('an unknown status blocks, and is not reported as a suspension', () {
      // fetchMemberships used to default a missing embed to 'Active' — the one
      // value that opens a door. It now passes '', and '' must never resolve
      // to allowed. It must also not resolve to `suspended`: telling somebody
      // their business is suspended when the app could not ask is the same
      // category of mistake as a confidently wrong number on a money screen.
      for (final status in ['', '   ']) {
        expect(
          manaSuspensionVerdictFor(businessStatus: status, roles: const ['Agent']),
          ManaSuspensionVerdict.unconfirmed,
        );
      }
    });

    test('an Owner is never blocked out of their own book', () {
      // SP-001 aims at non-Owners, and the Owner is the person who has to
      // reach the business to lift the suspension. Locking them out of the
      // thing that needs fixing is a closed loop.
      for (final status in ['Suspended', '', 'Closed']) {
        expect(
          manaSuspensionVerdictFor(businessStatus: status, roles: const ['Owner']),
          ManaSuspensionVerdict.allowed,
        );
      }
    });

    test('Owner wins when somebody holds both roles at one business', () {
      expect(
        manaSuspensionVerdictFor(
            businessStatus: 'Suspended', roles: const ['Agent', 'Owner']),
        ManaSuspensionVerdict.allowed,
      );
    });

    test('only a blocking verdict produces a route, and they differ', () {
      expect(manaSuspensionRouteFor(ManaSuspensionVerdict.allowed), isNull);
      expect(manaSuspensionRouteFor(ManaSuspensionVerdict.suspended),
          '/business-suspended');
      expect(manaSuspensionRouteFor(ManaSuspensionVerdict.unconfirmed),
          contains('reason=unconfirmed'));
    });
  });

  group('the wiring, which is the part that went missing', () {
    /// Every file that may carry somebody into a workspace, and the call that
    /// stops it doing so for a suspended business.
    ///
    /// ANSWERED BY LOOKING, NOT BY EDITING. If this list needs changing, a
    /// navigation path was added or moved: open it, confirm it cannot reach a
    /// workspace for a business the person may not enter, and only then record
    /// it here. Shrinking this list is how the original bug is re-introduced.
    const gated = <String, String>{
      // The two entry paths — both read a status already loaded at login, so
      // neither adds a round trip on the collection path.
      'lib/features/login_registration/screens/lr_012_business_selector.dart':
          'blockIfSuspended',
      'lib/features/login_registration/screens/lr_013_role_selector.dart':
          'blockIfSuspended',
      // The three cross-business switches, which bypass LR-012/LR-013 entirely
      // and whose membership models do not carry business_status.
      'lib/features/agent_workspace/screens/ag_009_profile.dart':
          'checkAndRedirect',
      'lib/features/customer_workspace/screens/cw_006_my_profile_memberships.dart':
          'checkAndRedirect',
      'lib/features/investor_workspace/screens/iw_005_my_profile_memberships.dart':
          'checkAndRedirect',
    };

    test('every gated entry point still calls the gate', () {
      final missing = <String>[];
      for (final entry in gated.entries) {
        final f = File(entry.key);
        if (!f.existsSync()) {
          missing.add('${entry.key} (file is gone)');
          continue;
        }
        if (!f.readAsStringSync().contains(entry.value)) {
          missing.add('${entry.key} no longer calls ${entry.value}');
        }
      }
      expect(missing, isEmpty,
          reason: 'SP-001 is enforced ONLY here — no RLS policy references '
              'business_status. Removing one of these calls reopens a '
              'suspended business to a non-Owner, and nothing else in this '
              'suite would notice: ${missing.join('; ')}');
    });

    test('the census has not silently gained a consumer', () {
      // A new file importing the gate is fine and probably right — but it
      // means a new way into a workspace exists, which is exactly the thing
      // worth looking at rather than counting.
      final importers = <String>[];
      void walk(Directory d) {
        for (final e in d.listSync()) {
          if (e is Directory) {
            walk(e);
          } else if (e is File && e.path.endsWith('.dart')) {
            if (e.readAsStringSync().contains('business_suspension_gate.dart')) {
              importers.add(e.path.replaceAll(r'\', '/'));
            }
          }
        }
      }

      walk(Directory('lib'));
      final expected = {
        ...gated.keys,
        // Registers /business-suspended and reads ?reason=unconfirmed.
        'lib/app/router.dart',
        // Does not navigate: it PRODUCES the status the gate consumes, and
        // names the gate in a comment explaining why a missing embed now
        // yields '' rather than 'Active'. Checked when it appeared here —
        // that one-word default was the fail-open hole underneath all of this.
        'lib/features/login_registration/state/auth_api_service.dart',
      };
      expect(importers.toSet(), expected,
          reason: 'the set of files reaching for the suspension gate changed. '
              'Open the new one and check it honours the contract, then record '
              'it in `gated` above with the call it makes');
    });
  });
}
