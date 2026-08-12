import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/screens/lr_004_registration_form.dart';

import 'support/mana_harness.dart';

/// LR-004 must not let a person register without a date of birth.
///
/// `persons.dob` has been nullable and optional since the schema was written,
/// and LR-004 never asked for it — DOB was only offered later, optionally, in
/// OW-014 Profile Completion. All 37 existing rows have a null dob, so the
/// column cannot be made NOT NULL without a backfill; compulsory therefore has
/// to be enforced at the point of registration, which is what these pin.
///
/// The screen lists every unmet requirement rather than silently disabling the
/// button, so asserting on that list is the honest check: it is exactly what
/// the user sees.
const _translations = <String, Map<String, String>>{
  'create_your_account': {'English': 'Create Your Account'},
  'still_needed_to_register': {'English': 'Still Needed To Register'},
  'register': {'English': 'Register'},
  'accept_terms_conditions': {'English': 'Accept Terms & Conditions'},
  'accept_privacy_policy': {'English': 'Accept Privacy Policy'},
  'capture_live_photo': {'English': 'Capture Live Photo'},
  'add_new_village': {'English': 'Add New Village'},
  'cancel': {'English': 'Cancel'},
  'save_and_select': {'English': 'Save And Select'},
  'retake_photo': {'English': 'Retake Photo'},
};

void main() {
  testWidgets('a blank form lists Date of Birth as still required', (tester) async {
    await pumpManaScreen(
      tester,
      const RegistrationFormScreen(),
      translations: _translations,
      // The form body is a lazy ListView and the "still needed" panel sits
      // well below the fold, so on a phone-sized surface it is never built
      // and find.text sees nothing. A tall surface builds the whole form.
      surfaceSize: const Size(360, 3000),
    );

    // Rendered as a bullet in the "still needed" panel.
    expect(find.text('• Date of Birth'), findsOneWidget);
  });

  testWidgets('the form shows a Date of Birth field', (tester) async {
    await pumpManaScreen(
      tester,
      const RegistrationFormScreen(),
      translations: _translations,
      // The form body is a lazy ListView and the "still needed" panel sits
      // well below the fold, so on a phone-sized surface it is never built
      // and find.text sees nothing. A tall surface builds the whole form.
      surfaceSize: const Size(360, 3000),
    );

    expect(find.text('Date of Birth *'), findsOneWidget);
  });

  testWidgets('DOB sits with the other mandatory identity fields', (tester) async {
    await pumpManaScreen(
      tester,
      const RegistrationFormScreen(),
      translations: _translations,
      // The form body is a lazy ListView and the "still needed" panel sits
      // well below the fold, so on a phone-sized surface it is never built
      // and find.text sees nothing. A tall surface builds the whole form.
      surfaceSize: const Size(360, 3000),
    );

    // If DOB were optional it would not appear alongside these in the
    // outstanding list; this is the regression that matters.
    for (final required in <String>[
      '• Full Name',
      '• Gender',
      '• Date of Birth',
    ]) {
      expect(find.text(required), findsOneWidget, reason: '$required missing from the list');
    }
  });
}
