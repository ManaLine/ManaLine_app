import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

import 'support/mana_harness.dart';

/// Going back a page in the wizard used to show a page that looked untouched
/// whether it held 55 customers or none — nothing is kept in memory across a
/// page turn, and the resume pointer can drop the Owner on page 5 of a book
/// someone else's handset half-migrated. The only way to find out what was in
/// was to import again, which is exactly how this business ended up with 108
/// loans instead of 54.
const _businessId = '0b726425-2338-49e5-bea1-6856624995b4';

class _FakeService implements BulkOnboardingService {
  _FakeService({this.step, this.progress, this.fails = false});
  final int? step;
  final Map<String, dynamic>? progress;
  final bool fails;

  @override
  Future<int?> wizardStep(String businessId) async => step;

  @override
  Future<void> saveWizardStep(String businessId, int step) async {}

  @override
  Future<MigrationProgress> migrationProgress(String businessId) async {
    if (fails) throw Exception('offline');
    return MigrationProgress(progress ?? const {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeService service) async {
  await pumpManaScreen(
    tester,
    const BulkOnboardingWizardScreen(businessId: _businessId),
    overrides: [bulkOnboardingServiceProvider.overrideWithValue(service)],
  );
  await tester.pump(); // the counts are fetched after the first frame
}

void main() {
  testWidgets('page 1 says how many people are already in', (tester) async {
    await _pump(
      tester,
      _FakeService(progress: {'customers': 55, 'investors': 3, 'agents': 1}),
    );

    expect(find.textContaining('55 customers'), findsOneWidget);
    expect(find.textContaining('3 investors'), findsOneWidget);
    // Singular, not "1 agents" — it is the last item, so no trailing comma.
    expect(find.textContaining('1 agent'), findsOneWidget);
    expect(find.textContaining('1 agents'), findsNothing);
  });

  testWidgets('the customers page reports loans and what is outstanding',
      (tester) async {
    await _pump(
      tester,
      _FakeService(
        step: 3,
        progress: {'loans': 54, 'line_balance': 2890900, 'collections': 250},
      ),
    );

    expect(find.textContaining('54 loans'), findsOneWidget);
    // The number the Owner reconciles against, in Indian grouping.
    expect(find.textContaining('28,90,900'), findsOneWidget);
    expect(find.textContaining('250 instalments'), findsOneWidget);
  });

  testWidgets('a page with nothing in it draws no line at all', (tester) async {
    // Zero is not "already in". A line reading "0 loans" on a page the Owner
    // has not reached yet is noise, and worse, reads as a result.
    await _pump(tester, _FakeService(step: 3, progress: {'loans': 0}));
    expect(find.textContaining('Already In'), findsNothing);
  });

  testWidgets('a failed count leaves the page silent, never claiming zero',
      (tester) async {
    await _pump(tester, _FakeService(step: 3, fails: true));
    expect(find.textContaining('Already In'), findsNothing);
  });
}
