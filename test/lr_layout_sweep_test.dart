import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/screens/lr_004_registration_form.dart';
import 'package:mana_line/features/login_registration/screens/lr_005_otp_verification.dart';
import 'package:mana_line/features/login_registration/screens/lr_006_registration_result.dart';
import 'package:mana_line/features/login_registration/screens/lr_008_create_pin.dart';
import 'package:mana_line/features/login_registration/screens/lr_011_forgot_pin.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// The login and registration screens were never laid out at text scale by
/// anything. They are the screens every single user meets first, and they are
/// the most field-dense in the app: LR-004 alone builds fourteen controllers.
///
/// Both languages, because translated width is data -- an English-only pass
/// measures text that is narrower than what ships.
void main() {
  final screens = <String, Widget Function()>{
    'LR-004 Registration Form': () => const RegistrationFormScreen(),
    'LR-005 OTP Verification': () => const OtpVerificationScreen(),
    'LR-006 Registration Result': () => const RegistrationResultScreen(),
    'LR-008 Create PIN': () => const CreatePinScreen(),
    'LR-008 Create PIN (upgrade)': () => const CreatePinScreen(isUpgrade: true),
    'LR-011 Forgot PIN': () => const ForgotPinScreen(),
  };

  for (final entry in screens.entries) {
    for (final scale in kManaTextScales) {
      testWidgets('${entry.key} survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(tester, entry.value(), textScale: scale);
        expectNoLayoutFault(tester, '${entry.key} at ${scale}x');
      });

      testWidgets('${entry.key} survives text scale ${scale}x in Telugu', (tester) async {
        await pumpManaScreen(tester, entry.value(),
            textScale: scale, language: ManaLanguage.telugu);
        expectNoLayoutFault(tester, '${entry.key} at ${scale}x in Telugu');
      });
    }
  }
}
