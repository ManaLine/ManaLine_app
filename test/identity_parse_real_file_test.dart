import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

/// Reproduces the live-test failure: an Identities workbook written by openpyxl
/// (i.e. by anything other than the `excel` package itself) made
/// parseIdentityBytes throw "Null check operator used on a null value", which
/// the screen then reported to the Owner as "this file could not be read as a
/// spreadsheet" — blaming their file for the app's crash.
void main() {
  test('an Identities sheet written by another tool parses', () {
    final f = File(r'C:\Users\SiriPriya\AppData\Local\Temp\claude'
        r'\D--mana-line-app\b81ed8dd-77a4-4bf3-839e-2c347d8fe54a'
        r'\scratchpad\upload\ManaLine-Identity-FILLED.xlsx');
    if (!f.existsSync()) {
      markTestSkipped('live-test workbook not present on this machine');
      return;
    }

    final parsed = BulkOnboardingService.parseIdentityBytes(
        Uint8List.fromList(f.readAsBytesSync()), 'ManaLine-Identity-FILLED.xlsx');

    expect(parsed.rows, hasLength(55));
    expect(parsed.rows.first['user_type'], 'Customer');
    // Gender arrives as M/F in the sheet and must be the MLID digit by now.
    expect(parsed.rows.every((r) => ['0', '1', '2'].contains(r['gender_digit'])), isTrue);
    expect(parsed.rows.every((r) => (r['pin_code'] as String).length == 6), isTrue);
    expect(parsed.rows.every((r) => (r['village'] as String).isNotEmpty), isTrue);
  });
}
