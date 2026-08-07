import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/admin/screens/admin_login_screen.dart';
import 'package:mana_line/features/admin/screens/admin_forgot_password_screen.dart';

import 'support/mana_harness.dart';

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('Admin Login survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(tester, const AdminLoginScreen(), textScale: scale);
      expectNoLayoutFault(tester, 'Admin Login at ${scale}x');
    });

    testWidgets('Admin Forgot Password survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(tester, const AdminForgotPasswordScreen(), textScale: scale);
      expectNoLayoutFault(tester, 'Admin Forgot Password at ${scale}x');
    });
  }

  testWidgets('Admin Login has no username prefilled', (tester) async {
    await pumpManaScreen(tester, const AdminLoginScreen());
    expect(find.text('2889424962'), findsNothing);
  });
}
