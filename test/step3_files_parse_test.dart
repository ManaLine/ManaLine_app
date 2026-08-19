import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

/// The two step-3 workbooks built for the live test must survive the app's own
/// parsers before they are handed to the Owner. A file that only looks right in
/// Excel is how the first live run lost an afternoon.
const _dir = r'C:\Users\SiriPriya\AppData\Local\Temp\claude'
    r'\D--mana-line-app\b81ed8dd-77a4-4bf3-839e-2c347d8fe54a\scratchpad\upload';

void main() {
  test('the Investors file parses and carries one profit share per person', () {
    final f = File('$_dir${Platform.pathSeparator}ManaLine-Step3-Investors.xlsx');
    if (!f.existsSync()) {
      markTestSkipped('step-3 workbook not present on this machine');
      return;
    }
    final parsed = BulkOnboardingService.parseInvestorBytes(
        Uint8List.fromList(f.readAsBytesSync()), 'ManaLine-Step3-Investors.xlsx');

    expect(parsed.rows, hasLength(5));
    // Every row must carry the four fields the RPC casts unconditionally.
    for (final r in parsed.rows) {
      for (final k in ['invested_amount', 'roi', 'interest_type', 'invested_date']) {
        expect(r[k], isNotNull, reason: '$k missing — the cast would fail');
      }
    }
    final total = parsed.rows
        .fold<int>(0, (s, r) => s + int.parse(r['invested_amount'] as String));
    expect(total, 3526000, reason: "ties to the account sheet's investment total");

    // profit_percent on exactly one row per MLID, or profit_share_accrued
    // claims a multiple of the whole business profit.
    final withShare = parsed.rows.where((r) => r['profit_percent'] != null).toList();
    expect(withShare, hasLength(3));
    expect(withShare.map((r) => r['mlid']).toSet(), hasLength(3));
    expect(
      withShare.fold<int>(0, (s, r) => s + int.parse(r['profit_percent'] as String)),
      80,
    );
  });

  test('the Shareholders file parses and its shares total 100', () {
    final f = File('$_dir${Platform.pathSeparator}ManaLine-Step3-Shareholders.xlsx');
    if (!f.existsSync()) {
      markTestSkipped('step-3 workbook not present on this machine');
      return;
    }
    final rows = BulkOnboardingService.parseShareholderBytes(
        Uint8List.fromList(f.readAsBytesSync()), 'ManaLine-Step3-Shareholders.xlsx');

    expect(rows, hasLength(5));
    final pct = rows.fold<double>(
        0, (s, r) => s + double.parse(r['share_percent'] as String));
    // import_shareholders refuses a total over 100.
    expect(pct, 100);
    expect(
      rows.fold<int>(0, (s, r) => s + int.parse(r['share_amount'] as String)),
      500000,
    );
    for (final r in rows) {
      expect(r['paid_on'], isNotNull);
      expect(r['roi_rate'], '1.5');
    }
  });
}
