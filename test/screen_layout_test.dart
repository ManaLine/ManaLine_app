import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/screens/lr_003_login_registration_choice.dart';
import 'package:mana_line/features/login_registration/screens/lr_007_first_login.dart';
import 'package:mana_line/features/login_registration/screens/lr_009_daily_login.dart';
import 'package:mana_line/features/login_registration/screens/lr_012_business_selector.dart';
import 'package:mana_line/features/login_registration/screens/lr_013_role_selector.dart';
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// Whole-screen layout tests — the class of bug that `flutter analyze` is
/// structurally incapable of seeing.
///
/// Overflow only exists once real constraints are applied, so it cannot be
/// caught by analysis, by a unit test, or by looking at the screen on one
/// phone at one font size. Two of these shipped this week (LR-007's login
/// button, LR-003) and both were found by a human squinting at a device.
///
/// The two axes that actually break layouts here are SYSTEM FONT SIZE and
/// TRANSLATED TEXT WIDTH. Both are user data, neither is under the developer's
/// control, and a layout that only survives English at 1.0x is not finished.
void main() {
  group('LR-009 Daily Login', () {
    // The screen's own entry condition: a remembered device with a PIN length.
    // Without this it redirects to /lr-001 and never lays out, so the test
    // would pass while asserting nothing.
    final storage = rememberedDeviceStorage();

    for (final scale in kManaTextScales) {
      testWidgets('survives text scale ${scale}x on a 360x640 phone',
          (tester) async {
        await pumpManaScreen(
          tester,
          const DailyLoginScreen(),
          textScale: scale,
          storage: storage,
        );

        expectNoLayoutFault(tester, 'LR-009 at ${scale}x');
      });
    }

    // The footer here is four TextButtons whose labels come from
    // ui_translations. It overflowed as a Row and is now a Wrap; this is the
    // regression guard for that fix, in every language it has to survive.
    for (final language in ManaLanguage.values) {
      testWidgets('renders in ${language.enumValue} without overflowing',
          (tester) async {
        await pumpManaScreen(
          tester,
          const DailyLoginScreen(),
          language: language,
          storage: storage,
        );

        expectNoLayoutFault(tester, 'LR-009 in ${language.enumValue}');
      });

      // The combination is the real worst case, and it is what a
      // Kannada-speaking Owner with large system fonts actually sees.
      testWidgets('renders in ${language.enumValue} at 2.0x text scale',
          (tester) async {
        await pumpManaScreen(
          tester,
          const DailyLoginScreen(),
          language: language,
          textScale: 2.0,
          storage: storage,
        );

        expectNoLayoutFault(
            tester, 'LR-009 in ${language.enumValue} at 2.0x');
      });
    }

    testWidgets('shows the PIN pad once the remembered length is read',
        (tester) async {
      // Guards the harness itself as much as the screen: if secure storage
      // were not seeded, the screen would bail to /lr-001 and every test above
      // would be asserting "an empty error page did not overflow".
      await pumpManaScreen(
        tester,
        const DailyLoginScreen(),
        storage: storage,
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('⌫'), findsOneWidget);
    });
  });

  // LR-003 is one of the two screens that shipped an overflow this week.
  group('LR-003 Login / Registration Choice', () {
    for (final scale in kManaTextScales) {
      testWidgets('survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          const LoginRegistrationChoiceScreen(),
          textScale: scale,
        );

        expectNoLayoutFault(tester, 'LR-003 at ${scale}x');
      });
    }

    for (final language in ManaLanguage.values) {
      testWidgets('${language.enumValue} at 1.6x', (tester) async {
        await pumpManaScreen(
          tester,
          const LoginRegistrationChoiceScreen(),
          language: language,
          textScale: 1.6,
        );

        expectNoLayoutFault(tester, 'LR-003 in ${language.enumValue} at 1.6x');
      });
    }
  });

  // LR-007 is the other. Its login button overflowed in 4fddbb8.
  group('LR-007 First Login', () {
    for (final scale in kManaTextScales) {
      testWidgets('survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(tester, const FirstLoginScreen(), textScale: scale);

        expectNoLayoutFault(tester, 'LR-007 at ${scale}x');
      });
    }

    for (final language in ManaLanguage.values) {
      testWidgets('${language.enumValue} at 1.6x', (tester) async {
        await pumpManaScreen(
          tester,
          const FirstLoginScreen(),
          language: language,
          textScale: 1.6,
        );

        expectNoLayoutFault(tester, 'LR-007 in ${language.enumValue} at 1.6x');
      });
    }

    testWidgets('the step-down banner does not overflow at 2.0x',
        (tester) async {
      // The BR-201 arrival adds a banner above the form — extra vertical
      // content on the screen that was already the tightest.
      await pumpManaScreen(
        tester,
        const FirstLoginScreen(stepDownFromFailedPin: true),
        textScale: 2.0,
        language: ManaLanguage.telugu,
        storage: rememberedDeviceStorage(),
      );

      expectNoLayoutFault(tester, 'LR-007 step-down banner');
    });
  });

  group('LR-012 Business Selector', () {
    // Real business names from production. Name length is data too — a long
    // one in a fixed-width row is the same bug class as a long translation.
    const seeded = AuthFlowState(
      personId: '2',
      memberships: [
        Membership(
          membershipId: 'm1',
          businessId: '3dcf3578-7788-4226-ba2f-028619bee5e3',
          businessName: 'sri tirumala finance',
          role: 'Owner',
          membershipStatus: 'Active',
        ),
        Membership(
          membershipId: 'm2',
          businessId: '3dcf3578-7788-4226-ba2f-028619bee5e3',
          businessName: 'sri tirumala finance',
          role: 'Agent',
          membershipStatus: 'Active',
        ),
        Membership(
          membershipId: 'm3',
          businessId: 'b2',
          businessName: 'sri satyanarayana business',
          role: 'Owner',
          membershipStatus: 'Active',
        ),
      ],
    );

    for (final scale in kManaTextScales) {
      testWidgets('survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          const BusinessSelectorScreen(),
          textScale: scale,
          authState: seeded,
        );

        expectNoLayoutFault(tester, 'LR-012 at ${scale}x');
      });
    }

    testWidgets('Kannada at 2.0x with the longest real business name',
        (tester) async {
      await pumpManaScreen(
        tester,
        const BusinessSelectorScreen(),
        language: ManaLanguage.telugu,
        textScale: 2.0,
        authState: seeded,
      );

      expectNoLayoutFault(tester, 'LR-012 worst case');
    });
  });

  group('LR-013 Role Selector', () {
    // Both roles in one business — the case that regressed in 7cc4bf0 when
    // the Agent membership was filtered out by BR-191.
    const seeded = AuthFlowState(
      personId: '2',
      selectedBusinessId: '3dcf3578-7788-4226-ba2f-028619bee5e3',
      memberships: [
        Membership(
          membershipId: 'm1',
          businessId: '3dcf3578-7788-4226-ba2f-028619bee5e3',
          businessName: 'sri tirumala finance',
          role: 'Owner',
          membershipStatus: 'Active',
        ),
        Membership(
          membershipId: 'm2',
          businessId: '3dcf3578-7788-4226-ba2f-028619bee5e3',
          businessName: 'sri tirumala finance',
          role: 'Agent',
          membershipStatus: 'Active',
        ),
      ],
    );

    for (final scale in kManaTextScales) {
      testWidgets('survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          const RoleSelectorScreen(),
          textScale: scale,
          authState: seeded,
        );

        expectNoLayoutFault(tester, 'LR-013 at ${scale}x');
      });
    }

    for (final language in ManaLanguage.values) {
      testWidgets('${language.enumValue} at 1.6x', (tester) async {
        await pumpManaScreen(
          tester,
          const RoleSelectorScreen(),
          language: language,
          textScale: 1.6,
          authState: seeded,
        );

        expectNoLayoutFault(tester, 'LR-013 in ${language.enumValue} at 1.6x');
      });
    }
  });
}
