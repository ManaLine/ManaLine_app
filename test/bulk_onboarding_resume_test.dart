import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart';

import 'support/mana_harness.dart';

/// The wizard is eight pages, several of them a file upload, so it is more than
/// one sitting. It used to reopen on page 1 with every finished page looking
/// untouched — which is also how a book gets imported twice.
///
/// The pointer is per business: two books being migrated from the same handset
/// must not inherit each other's progress.
const _businessId = '0b726425-2338-49e5-bea1-6856624995b4';
String _key(String businessId) => 'mana_bulk_onboarding_step_$businessId';

void main() {
  testWidgets('reopens on the page it stopped at, and says so', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: _businessId),
      storage: {_key(_businessId): '2'},
    );
    await tester.pump(); // the pointer is read after the first frame

    expect(find.textContaining('3. Investors'), findsOneWidget);
    expect(find.textContaining('Carried on where you stopped'), findsOneWidget);
  });

  testWidgets('starts at page 1 when nothing was saved', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: _businessId),
    );
    await tester.pump();

    expect(find.textContaining('1. Identities'), findsOneWidget);
    // No banner when nothing was resumed — it would be noise on a fresh start.
    expect(find.textContaining('Carried on where you stopped'), findsNothing);
  });

  testWidgets('one business does not inherit another\'s progress',
      (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'a-different-business'),
      storage: {_key(_businessId): '5'},
    );
    await tester.pump();

    expect(find.textContaining('1. Identities'), findsOneWidget);
  });

  testWidgets('Start From Page 1 goes back and drops the banner',
      (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: _businessId),
      storage: {_key(_businessId): '4'},
    );
    await tester.pump();
    expect(find.textContaining('5. Agents'), findsOneWidget);

    await tester.tap(find.text('Start From Page 1'));
    await tester.pump();

    expect(find.textContaining('1. Identities'), findsOneWidget);
    expect(find.textContaining('Carried on where you stopped'), findsNothing);
  });

  testWidgets('a pointer past the last page cannot crash the header',
      (tester) async {
    // Written by a build with more pages than this one has.
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: _businessId),
      storage: {_key(_businessId): '99'},
    );
    await tester.pump();

    expect(find.textContaining('8. Finish'), findsOneWidget);
    expectNoLayoutFault(tester, 'the wizard resumed from an out-of-range page');
  });
}
