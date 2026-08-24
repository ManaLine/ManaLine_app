import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

import 'support/mana_harness.dart';

/// The wizard is eight pages, several of them a file upload, so it is more than
/// one sitting — and more than one device. It used to reopen on page 1 with
/// every finished page looking untouched, which is also how a book gets
/// imported twice.
///
/// The pointer lives on the server (businesses.migration_wizard_step) so it
/// follows the Owner; the secure-storage copy is an offline fallback only.
const _businessId = '0b726425-2338-49e5-bea1-6856624995b4';
String _key(String businessId) => 'mana_bulk_onboarding_step_$businessId';

/// `implements`, not `extends` — the real service reaches Supabase.instance,
/// which is not initialised in a test process.
class _FakeService implements BulkOnboardingService {
  _FakeService({this.step, this.offline = false});
  final int? step;
  final bool offline;
  int? saved;

  @override
  Future<int?> wizardStep(String businessId) async {
    if (offline) throw Exception('no internet');
    return step;
  }

  @override
  Future<void> saveWizardStep(String businessId, int step) async {
    saved = step;
  }


  /// A book with everything in it, so every page is present and the page
  /// numbers in these tests mean what they say. A wizard with no plan shows
  /// only the chooser, which is correct but not what most of these are about.
  @override
  Future<MigrationPlan?> migrationPlan(String businessId) async =>
      MigrationPlan(
        investors: true,
        shareholders: true,
        customers: true,
        emiHistory: true,
        attendance: true,
        weekly: true,
        profit: true,
        cutoff: DateTime(2026, 3, 20),
      );

  @override
  Future<List<String>> migrationPlanGaps(String businessId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeService service,
  Map<String, String> storage = const {},
  String businessId = _businessId,
}) async {
  await pumpManaScreen(
    tester,
    BulkOnboardingWizardScreen(businessId: businessId),
    storage: storage,
    overrides: [bulkOnboardingServiceProvider.overrideWithValue(service)],
  );
  // Two, not one: the plan is fetched first — it decides which pages exist —
  // and the saved position after it, so the restore takes an extra turn of the
  // event loop before it can be shown.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('reopens on the page the server remembers, and says so',
      (tester) async {
    await _pump(tester, service: _FakeService(step: 2));

    expect(find.textContaining('3. Investors'), findsOneWidget);
    expect(find.textContaining('Carried on where you stopped'), findsOneWidget);
  });

  testWidgets('the server wins over what this device remembers', (tester) async {
    // The Owner got to the Opening Snapshot on their other phone. This
    // handset last saw Customers and must not drag them backwards.
    await _pump(
      tester,
      service: _FakeService(step: 5),
      storage: {_key(_businessId): '3'},
    );

    expect(find.textContaining('6. Opening Snapshot'), findsOneWidget);
  });

  testWidgets('offline, it falls back to what this device saw', (tester) async {
    // Losing the signal must not restart a half-migrated book at page 1.
    await _pump(
      tester,
      service: _FakeService(offline: true),
      storage: {_key(_businessId): '3'},
    );

    expect(find.textContaining('4. Customers'), findsOneWidget);
  });

  testWidgets('starts at page 1 when neither remembers anything',
      (tester) async {
    await _pump(tester, service: _FakeService());

    expect(find.textContaining('1. What Your Book Has'), findsOneWidget);
    // No banner on a fresh start — it would be noise.
    expect(find.textContaining('Carried on where you stopped'), findsNothing);
  });

  testWidgets('one business does not inherit another\'s progress',
      (tester) async {
    await _pump(
      tester,
      service: _FakeService(offline: true),
      storage: {_key(_businessId): '5'},
      businessId: 'a-different-business',
    );

    expect(find.textContaining('1. What Your Book Has'), findsOneWidget);
  });

  testWidgets('turning a page saves the new position', (tester) async {
    final service = _FakeService(step: 2);
    await _pump(tester, service: service);

    await tester.ensureVisible(find.text('next'));
    await tester.pump();
    await tester.tap(find.text('next'));
    await tester.pump();

    // Investors (index 2) -> Customers (index 3).
    expect(service.saved, 3);
  });

  testWidgets('Start From Page 1 goes back and records it', (tester) async {
    final service = _FakeService(step: 4);
    await _pump(tester, service: service);
    expect(find.textContaining('5. Agents'), findsOneWidget);

    await tester.ensureVisible(find.text('Start From Page 1'));
    await tester.pump();
    await tester.tap(find.text('Start From Page 1'));
    await tester.pump();

    expect(find.textContaining('1. What Your Book Has'), findsOneWidget);
    expect(find.textContaining('Carried on where you stopped'), findsNothing);
    // Recorded, not just shown: reopening must not bounce them to page 5.
    expect(service.saved, 0);
  });

  testWidgets('a pointer past the last page cannot crash the header',
      (tester) async {
    await _pump(tester, service: _FakeService(step: 99));

    expect(find.textContaining('8. Finish'), findsOneWidget);
    expectNoLayoutFault(tester, 'the wizard resumed from an out-of-range page');
  });
}
