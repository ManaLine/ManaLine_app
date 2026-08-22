import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

/// The step-4 customer grid built for the live test, run through the app's own
/// parser before it is handed to the Owner. A workbook that only looks right
/// in Excel is how the first live run lost an afternoon.
const _dir = r'C:\Users\SiriPriya\AppData\Local\Temp\claude'
    r'\D--mana-line-app\b81ed8dd-77a4-4bf3-839e-2c347d8fe54a\scratchpad\upload';

void main() {
  _weeklyParses();

  test('the customer grid parses, and its balances tie to the book', () {
    final f = File('$_dir${Platform.pathSeparator}ManaLine-Step4-Customers.xlsx');
    if (!f.existsSync()) {
      markTestSkipped('live-test workbook not present on this machine');
      return;
    }

    final parsed = BulkOnboardingService.parseCustomerGridBytes(
        Uint8List.fromList(f.readAsBytesSync()), 'ManaLine-Step4-Customers.xlsx');

    final all = parsed.loans;
    expect(all, hasLength(54));

    // 56 outstanding loans in the book, less the two entered by hand.
    final balance = all.fold<int>(
        0, (s, r) => s + int.parse(r['remaining_balance'] as String));
    expect(balance, 2890900);
    expect(balance + 114000, 3004900,
        reason: "must tie to the account sheet's line balance");

    // The sheet IS the frequency; every row must have picked one up.
    expect(all.every((r) => ['Daily', 'Weekly', 'Monthly']
        .contains(r['repayment_type'])), isTrue);

    // Every row the RPC casts unconditionally.
    for (final r in all) {
      for (final k in const [
        'amount_given', 'repayment_amount', 'remaining_balance',
        'effective_date', 'installment_amount',
      ]) {
        expect(r[k], isNotNull, reason: 'missing $k');
      }
      expect(r['mlid'] as String, startsWith('MLTI'));
    }
  });
}

/// The weekly account workbook had the same exposure: parseWeeklyBytes also
/// called Excel.decodeBytes directly, so an openpyxl-written book — which is
/// what the Owner has — was rejected as unreadable.
void _weeklyParses() {
  test('the weekly account workbook parses', () {
    final f = File('$_dir${Platform.pathSeparator}ManaLine-Weekly-Account-FILLED.xlsx');
    if (!f.existsSync()) {
      markTestSkipped('live-test workbook not present on this machine');
      return;
    }

    final rows = BulkOnboardingService.parseWeeklyBytes(
        Uint8List.fromList(f.readAsBytesSync()),
        'ManaLine-Weekly-Account-FILLED.xlsx');

    expect(rows, isNotEmpty);
    expect(rows.every((r) => (r['account_date'] as String).isNotEmpty), isTrue);
  });
}
