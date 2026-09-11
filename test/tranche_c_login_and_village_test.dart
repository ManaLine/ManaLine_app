import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two small things that each cost somebody real work every single day.
void main() {
  group('the login already knows the number', () {
    final source =
        File('lib/features/login_registration/screens/lr_007_first_login.dart')
            .readAsStringSync();
    final initState = source.substring(
        source.indexOf('void initState()'), source.indexOf('void dispose()'));

    test('the last mobile number is read on every arrival', () {
      // The screen greets the person BY NAME over an empty Mobile Number box.
      // It knew who they were and made them type their own phone number
      // anyway, ten digits, every day.
      expect(initState, contains('readLastMobileNumber'),
          reason: 'the number is saved on every successful login; not reading '
              'it back is asking for something already known');
    });

    test('the prefill is not gated on the failed-PIN step-down', () {
      // It USED to be. So it fired only for somebody who had just got their
      // PIN wrong three times -- the one arrival where the stored number was
      // least likely to be the one they wanted -- and never on the ordinary
      // daily login this screen exists for.
      // The code shape, not the prose -- the comment above the fix names the
      // flag, so a plain text search finds it and proves nothing.
      expect(initState,
          isNot(contains('else if (widget.stepDownFromFailedPin)')),
          reason: 'the read-back is behind the step-down flag again, which is '
              'the narrowest possible case rather than the common one');
      expect(initState.substring(initState.indexOf('readLastMobileNumber')),
          isNotEmpty);
    });

    test('an explicit prefill still wins', () {
      // LR-010 hands over the number just typed. That one beats storage.
      expect(initState.indexOf('widget.prefilledMobile'),
          lessThan(initState.indexOf('readLastMobileNumber')),
          reason: 'the number typed a moment ago must take precedence over '
              'the one in storage');
    });

    test('the cursor moves to the password, but only when the number is there',
        () {
      expect(source, contains('focusNode: _passwordFocus'),
          reason: 'the password field has nothing to focus');
      final focus = source.substring(source.indexOf('void _focusPasswordIfNumberKnown('));
      expect(focus.substring(0, focus.indexOf('}')),
          contains("_mobile.text.trim().length != 10"),
          reason: 'focusing the password over a BLANK number hides the empty '
              'field behind the keyboard');
    });
  });

  group('adding a village searches the way registration does', () {
    final source =
        File('lib/features/owner_workspace/screens/ow_012_business_management.dart')
            .readAsStringSync();

    test('both village entry points use the shared field', () {
      // There were two hand-rolled copies in this one file -- the Add Area
      // form and the "add a village to <area>" sheet -- both PIN-first with a
      // village-name box that could not search on its own. They were the
      // ninth and tenth private copies of a village search in the app, and
      // the ones Plan 4 missed when it consolidated eight, because they
      // returned LocationOption rather than ManaVillage.
      // String implements Pattern, so this is the built-in allMatches.
      expect('ManaVillageSearchField('.allMatches(source).length,
          greaterThanOrEqualTo(3),
          reason: 'business address, Add Area and the add-village sheet should '
              'each use the shared two-mode field');
    });

    test('the screen no longer drives its own village search', () {
      expect(source, isNot(contains('operatingAreaSearchProvider.notifier')),
          reason: 'a private village search has come back; PIN-or-name lives '
              'in ManaVillageSearchField now');
    });

    test('the sheet and its caller agree on the type', () {
      // Navigator.pop takes a dynamic, so a stale type argument here does NOT
      // fail to compile -- it throws on the cast the first time somebody
      // picks a village.
      expect(source, contains('showModalBottomSheet<ManaVillage>'),
          reason: 'the sheet pops a ManaVillage; a LocationOption type '
              'argument would throw at the first pick');
      expect(source, isNot(contains('resolveLocationId(picked)')),
          reason: 'a ManaVillage resolves through LocationApiService.resolveId');
    });
  });
}
