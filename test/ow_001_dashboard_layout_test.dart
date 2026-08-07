import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart';
import 'package:mana_line/features/owner_workspace/state/owner_api_service.dart';
import 'package:mana_line/features/owner_workspace/state/owner_workspace_state.dart';

import 'support/mana_harness.dart';

/// Seeded to a known value with a no-op load() — the real load() reaches
/// Supabase, which is never initialised in a test process. Long business
/// name deliberately, since a business name is data and the header Row
/// around it has already overflowed once for exactly that reason
/// (LR-013's own fix note).
class _SeededOwnerDashboardNotifier extends OwnerDashboardNotifier {
  _SeededOwnerDashboardNotifier(this._seed);
  final OwnerDashboardData _seed;

  @override
  Future<OwnerDashboardData> build() async => _seed;

  @override
  Future<void> load(String businessId) async {}
}

void main() {
  final seed = OwnerDashboardData.zero(
    businessName: 'Sri Venkateswara Rural Finance and Chit Fund Society',
  );

  for (final scale in kManaTextScales) {
    testWidgets('OW-001 Owner Dashboard survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const OwnerHomeDashboardScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [ownerDashboardProvider.overrideWith(() => _SeededOwnerDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-001 Owner Dashboard at ${scale}x');
    });
  }

  testWidgets('OW-001 shows the business name', (tester) async {
    await pumpManaScreen(
      tester,
      const OwnerHomeDashboardScreen(businessId: 'b1'),
      overrides: [ownerDashboardProvider.overrideWith(() => _SeededOwnerDashboardNotifier(seed))],
    );
    expect(find.textContaining('Sri Venkateswara'), findsWidgets);
  });
}
