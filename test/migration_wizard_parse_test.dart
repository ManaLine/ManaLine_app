import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

/// Parsing for the pre-existing-business wizard. Everything here is a pure
/// function of the bytes — no client, no network — which is exactly why it is
/// the part worth testing directly. Validation of the VALUES stays on the
/// server; these tests only cover what the client is the sole authority on:
/// what column means what, and which sheet a row came off.
void main() {
  group('gender', () {
    test('M/F/O — however the Owner writes it — become the MLID gender digit', () {
      expect(BulkOnboardingService.genderDigit('M'), '1');
      expect(BulkOnboardingService.genderDigit('male'), '1');
      expect(BulkOnboardingService.genderDigit('F'), '0');
      expect(BulkOnboardingService.genderDigit(' o '), '2');
      expect(BulkOnboardingService.genderDigit('Others'), '2');
      // Already a digit: passed through, not re-mapped.
      expect(BulkOnboardingService.genderDigit('1'), '1');
      // Unrecognised stays unrecognised — the server is the one that rejects.
      expect(BulkOnboardingService.genderDigit('mr'), isNull);
    });

    test('an identity sheet is parsed with the digit, not the letter', () {
      final excel = Excel.createExcel();
      final sheet = excel['Identities'];
      sheet.appendRow([
        for (final c in const [
          'Aadhaar Number',
          'Gender (M/F/O)*',
          'Name (Surname + Name)*',
          'C/O Name*',
          'User Type (Agent/Customer/Investor)*',
          'Phone',
          'Door No',
          'Pin Code*',
          'Village*',
        ])
          TextCellValue(c),
      ]);
      sheet.appendRow([
        TextCellValue(''),
        TextCellValue('F'),
        TextCellValue('Gottipati Devendra'),
        TextCellValue('Ramaiah'),
        TextCellValue('Customer'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('517644'),
        TextCellValue('Renigunta'),
      ]);
      excel.delete('Sheet1');

      final parsed = BulkOnboardingService.parseIdentityBytes(
          Uint8List.fromList(excel.save()!), 'identities.xlsx');

      expect(parsed.rows, hasLength(1));
      expect(parsed.rows.first['gender_digit'], '0');
      // One Name column, kept whole — surname/given_name are derived server
      // side, so the Owner never splits a name by hand.
      expect(parsed.rows.first['full_name'], 'Gottipati Devendra');
      // Neither phone nor Aadhaar: legal for a migrated row, and the parser
      // must not invent empty strings for them.
      expect(parsed.rows.first.containsKey('mobile_number'), isFalse);
      expect(parsed.rows.first.containsKey('aadhaar_number'), isFalse);
    });
  });

  group('villagePairs', () {
    test('distinct pairs only, case-insensitive, PIN stripped to digits', () {
      final pairs = BulkOnboardingService.villagePairs([
        {'pin_code': '517 644', 'village': 'Renigunta'},
        {'pin_code': '517644', 'village': 'renigunta'},
        {'pin_code': '517644', 'village': 'Yerpedu'},
        {'pin_code': '', 'village': 'Nowhere'},
        {'pin_code': '517645'},
      ]);

      expect(
        pairs.map((p) => '${p.pinCode}|${p.village}').toList(),
        ['517644|Renigunta', '517644|Yerpedu'],
      );
    });
  });

  group('parseCustomerGridBytes', () {
    Uint8List gridWith(String sheetName) {
      final excel = Excel.createExcel();
      final sheet = excel[sheetName];
      sheet.appendRow([
        TextCellValue('MLID'),
        TextCellValue('Name'),
        TextCellValue('Village'),
        TextCellValue('Amount Given*'),
        TextCellValue('Repayment Amount*'),
        TextCellValue('Remaining Balance*'),
        TextCellValue('Issued Date* (yyyy-mm-dd)'),
        TextCellValue('Instalment Amount*'),
        TextCellValue('EMI 1 Amount'),
        TextCellValue('EMI 1 Date'),
        TextCellValue('EMI 2 Amount'),
        TextCellValue('EMI 2 Date'),
      ]);
      sheet.appendRow([
        TextCellValue('MLTI100000001'),
        TextCellValue('Gottipati Devendra'),
        TextCellValue('Renigunta'),
        TextCellValue('9000'),
        TextCellValue('12000'),
        TextCellValue('6000'),
        TextCellValue('2026-01-05'),
        TextCellValue('200'),
        TextCellValue('200'),
        TextCellValue('2026-01-06'),
        TextCellValue(''),
        TextCellValue(''),
      ]);
      excel.delete('Sheet1');
      return Uint8List.fromList(excel.save()!);
    }

    test('the sheet name IS the frequency — it is never read from a column', () {
      for (final frequency in BulkOnboardingService.customerFrequencies) {
        final parsed =
            BulkOnboardingService.parseCustomerGridBytes(gridWith(frequency), 'customers.xlsx');
        expect(parsed.loans, hasLength(1), reason: frequency);
        expect(parsed.loans.first['repayment_type'], frequency);
      }
    });

    test('EMI pairs come back as history, half-filled pairs skipped', () {
      final parsed =
          BulkOnboardingService.parseCustomerGridBytes(gridWith('Daily'), 'customers.xlsx');
      expect(parsed.schedule, hasLength(1));
      expect(parsed.schedule.first.mlid, 'MLTI100000001');
      expect(parsed.schedule.first.entries, hasLength(1));
      expect(parsed.schedule.first.entries.first.amount, 200);
      expect(parsed.schedule.first.entries.first.date, DateTime(2026, 1, 6));
    });

    test('a frequency the business does not run is not an error', () {
      final parsed =
          BulkOnboardingService.parseCustomerGridBytes(gridWith('Weekly'), 'customers.xlsx');
      expect(parsed.loans, hasLength(1));
    });
  });

  group('parseWeeklyBytes', () {
    test('reads the weekly book positionally and drops empty lines', () {
      final excel = Excel.createExcel();
      final sheet = excel['Weekly Account'];
      sheet.appendRow([
        TextCellValue('Date* (yyyy-mm-dd)'),
        TextCellValue('Type*'),
        TextCellValue('Amount*'),
        TextCellValue('MLID'),
        TextCellValue('Category'),
        TextCellValue('Interest Portion'),
        TextCellValue('Remarks'),
      ]);
      sheet.appendRow([
        TextCellValue('2026-01-05'),
        TextCellValue('Salary'),
        TextCellValue('3000'),
      ]);
      sheet.appendRow([
        TextCellValue('2026-01-06'),
        TextCellValue('Investor Withdrawal'),
        TextCellValue('5000'),
        TextCellValue('MLTI100000002'),
        TextCellValue(''),
        TextCellValue('500'),
        TextCellValue('part'),
      ]);
      sheet.appendRow([TextCellValue(''), TextCellValue(''), TextCellValue('')]);
      excel.delete('Sheet1');

      final rows =
          BulkOnboardingService.parseWeeklyBytes(Uint8List.fromList(excel.save()!), 'weekly.xlsx');

      expect(rows, hasLength(2));
      expect(rows.first['kind'], 'Salary');
      expect(rows.first.containsKey('mlid'), isFalse);
      expect(rows[1]['interest_portion'], '500');
      expect(rows[1]['remarks'], 'part');
    });
  });

  group('parseAttendanceBytes', () {
    test('a row with no date is not an attendance day', () {
      final excel = Excel.createExcel();
      final sheet = excel['Attendance'];
      sheet.appendRow([
        TextCellValue('MLID'),
        TextCellValue('Name'),
        TextCellValue('Date (yyyy-mm-dd)'),
        TextCellValue('Allowance'),
      ]);
      sheet.appendRow([
        TextCellValue('MLTI1'),
        TextCellValue('A'),
        TextCellValue('2026-01-05'),
        TextCellValue('100'),
      ]);
      sheet.appendRow([TextCellValue('MLTI2'), TextCellValue('B')]);
      excel.delete('Sheet1');

      final rows = BulkOnboardingService.parseAttendanceBytes(
          Uint8List.fromList(excel.save()!), 'attendance.xlsx');

      expect(rows, hasLength(1));
      expect(rows.first['allowance_amount'], '100');
    });
  });
}
