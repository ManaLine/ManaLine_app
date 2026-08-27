import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/screens/lr_010_forgot_password.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// LR-010 Forgot Password had no layout test -- the last login screen without
/// one. It holds a mobile field, a six-box OTP row and two password fields,
/// and the OTP row is six fixed boxes side by side, which is the shape that
/// stops fitting first.
void main() {
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('LR-010 Forgot Password survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          const ForgotPasswordScreen(),
          textScale: scale,
          language: lang,
        );
        expectNoLayoutFault(tester, 'LR-010 Forgot Password at ${scale}x$tag');
      });
    }
  }
}
