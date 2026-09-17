import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/schema_snapshot.dart';

/// Pull-to-refresh on the Owner's dashboard must RE-DERIVE before it reads.
///
/// WHY THIS EXISTS. On 2026-09-16 a handset showed an Owner a BF of
/// Rs 4,90,000 against a day_ledger closing of Rs 2,62,200. Two defects met:
/// app.recompute_day_ledger summed investments.principal_amount (a CURRENT
/// balance) for a day in the PAST, and nothing had re-run the derivation since
/// the row that invalidated it. The first is fixed in
/// 20260917090000_a_past_day_is_not_todays_balance.sql.
///
/// The second has no fix in SQL, because BF is derived and a derived figure is
/// only as fresh as the last thing that recomputed it. The gesture a person
/// already makes when a number looks wrong -- swipe down -- is the repair.
///
/// THE FAILURE MODE THIS CATCHES IS "NOTHING CALLED IT". That is exactly what
/// happened to business_suspension_gate.dart: written for the job, correct,
/// and with no callers, so the rule it enforced was enforced nowhere. An RPC
/// that exists and is never invoked reads identically to one that works.
void main() {
  String read(String p) => File(p).readAsStringSync();

  const screen =
      'lib/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart';
  const state = 'lib/features/owner_workspace/state/owner_workspace_state.dart';
  const api = 'lib/features/owner_workspace/state/owner_api_service.dart';

  test('the swipe-down handler goes through refresh(), not load()', () {
    final src = read(screen);
    expect(
      RegExp(r'_refresh\(\)\s*=>\s*[\s\S]{0,120}\.refresh\(').hasMatch(src),
      isTrue,
      reason: 'ow-001 pull-to-refresh must call the notifier\'s refresh(), '
          'which repairs before it reads. Calling load() only re-reads the '
          'same stale derivation and shows the wrong number again',
    );
  });

  test('refresh() invokes the repair RPC before loading', () {
    final src = read(state);
    final body = RegExp(r'Future<void> refresh\(String businessId\) async \{'
            r'([\s\S]*?)\n  \}')
        .firstMatch(src);
    expect(body, isNotNull, reason: 'OwnerDashboardNotifier.refresh went away');
    final b = body!.group(1)!;
    expect(b, contains('refreshBusinessFigures'),
        reason: 'without this the gesture is just load() with extra steps');
    expect(b.indexOf('refreshBusinessFigures') < b.indexOf('load('), isTrue,
        reason: 'repair must precede the read, or the read shows the figure '
            'the repair was about to correct');
  });

  test('the RPC is reached on the app schema and exists in the snapshot', () {
    expect(read(api), contains("schema('app')"),
        reason: 'a bare .rpc() targets public and 404s');
    expect(manaAppFunctions, contains('refresh_business_figures'));
  });
}
