// ManaWebHomeScreen (Plan 3a Task 2) — the landing place a signed-in person
// reaches on the web now that the four workspace dashboards are gone from
// that build. What matters:
//   1. Each role sees exactly its own destinations, and NO OTHERS — an
//      Owner-only link leaking to a Customer is the failure this file exists
//      to catch.
//   2. The Agent gets the app download as the PRIMARY action, because their
//      whole role is field work and there is nothing else here for them.
//   3. No layout fault at phone/tablet/desk width.
//   4. No digit anywhere in the rendered text — this pins "no figures" as a
//      property of the screen, not a one-time intention. Adding a balance or
//      a count back to this screen later fails this test.
//
// Expected label text below is the fixture's ENGLISH translation, not the
// raw key — 'account_review' renders as "Account Review" via ManaText.raw
// (see web_home_screen.dart's comment on why titles are .raw, not
// title-cased). The two web_home_* app-card keys are NOT in the fixture, so
// they render as their own raw key text — that is deliberate (see the task
// report: those keys do not exist in ui_translations yet) and doubles as a
// stable, un-mistakable string to assert against.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';
import 'package:mana_line/features/web/screens/web_home_screen.dart';

import 'support/mana_harness.dart';

void main() {
  Future<void> pumpForRole(WidgetTester tester, String role, {double width = 390}) {
    return pumpManaScreen(
      tester,
      const ManaWebHomeScreen(),
      authState: AuthFlowState(selectedRole: role),
      surfaceSize: Size(width, 900),
      location: '/web-home',
    );
  }

  group('role-aware destinations', () {
    testWidgets('Owner sees exactly the owner destination set', (tester) async {
      await pumpForRole(tester, 'Owner');

      for (final present in ['Account Review', 'Pre-Existing Business', 'Subscription', 'Profile', 'Settings']) {
        expect(find.text(present), findsWidgets, reason: 'Owner should see $present');
      }
      for (final absent in ['My Investments', 'My Loans', 'web_home_agent_app_title']) {
        expect(find.text(absent), findsNothing, reason: 'Owner should NOT see $absent');
      }
    });

    testWidgets('Investor sees exactly the investor destination set', (tester) async {
      await pumpForRole(tester, 'Investor');

      for (final present in ['My Investments', 'Profile', 'Settings']) {
        expect(find.text(present), findsWidgets, reason: 'Investor should see $present');
      }
      for (final absent in [
        'Account Review',
        'Pre-Existing Business',
        'Subscription',
        'My Loans',
        'web_home_agent_app_title',
      ]) {
        expect(find.text(absent), findsNothing, reason: 'Investor should NOT see $absent');
      }
    });

    testWidgets('Customer sees exactly the customer destination set', (tester) async {
      await pumpForRole(tester, 'Customer');

      for (final present in ['My Loans', 'Profile', 'Settings']) {
        expect(find.text(present), findsWidgets, reason: 'Customer should see $present');
      }
      for (final absent in [
        'Account Review',
        'Pre-Existing Business',
        'Subscription',
        'My Investments',
        'web_home_agent_app_title',
      ]) {
        expect(find.text(absent), findsNothing, reason: 'Customer should NOT see $absent');
      }
    });

    testWidgets('Agent sees only profile, settings and the app card — no business destinations', (tester) async {
      await pumpForRole(tester, 'Agent');

      for (final present in ['Profile', 'Settings', 'web_home_agent_app_title']) {
        expect(find.text(present), findsWidgets, reason: 'Agent should see $present');
      }
      for (final absent in [
        'Account Review',
        'Pre-Existing Business',
        'Subscription',
        'My Investments',
        'My Loans',
        // The secondary (non-agent) app card copy must not also appear.
        'web_home_secondary_app_title',
      ]) {
        expect(find.text(absent), findsNothing, reason: 'Agent should NOT see $absent');
      }
    });
  });

  testWidgets('the Agent app card leads, because it is the whole answer',
      (tester) async {
    await pumpForRole(tester, 'Agent');

    // THIS USED TO READ THE NAV BAR, and the nav has moved out from under
    // it: the rail is drawn by ManaWebShell around every signed-in route
    // now, not by this screen. Pumping the screen alone therefore has no
    // nav to inspect, which is correct rather than broken.
    //
    // The fact being pinned is unchanged and still lives here -- the app
    // card is FIRST for an Agent, because an Agent's whole job is field work
    // and the card is the answer rather than a fallback. Ordering is checked
    // where it is decided (manaWebDestinations) and rendering where it is
    // rendered; web_navigation_test covers the rail.
    final cards = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    final appIndex = cards.indexOf('web_home_agent_app_title');
    final profileIndex = cards.indexOf('Profile');
    expect(appIndex, isNonNegative, reason: 'expected the app card');
    expect(profileIndex, isNonNegative, reason: 'expected the profile card');
    expect(appIndex, lessThan(profileIndex),
        reason: 'the app card leads for an Agent');
  });

  group('layout', () {
    for (final width in [390.0, 820.0, 1440.0]) {
      testWidgets('renders with no layout fault at width $width', (tester) async {
        await pumpForRole(tester, 'Owner', width: width);
        expectNoLayoutFault(tester, 'ManaWebHomeScreen at width $width');
      });
    }
  });

  group('no figures', () {
    testWidgets('no digit appears anywhere in the rendered text', (tester) async {
      for (final role in const ['Owner', 'Agent', 'Customer', 'Investor']) {
        await pumpForRole(tester, role);

        final allText = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' ');
        expect(
          RegExp(r'\d').hasMatch(allText),
          isFalse,
          reason: 'a digit appeared for role $role — this screen must never show a figure: "$allText"',
        );
      }
    });
  });
}
