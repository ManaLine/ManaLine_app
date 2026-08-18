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
    /// The first two weeks of the Owner's real 2026 book. Week 1 is the one
    /// that proves the gross-in/gross-out identity: 112,800 interest and 6,280
    /// fee come back in against 626,800 of loans written out.
    Uint8List realBook() {
      final excel = Excel.createExcel();
      final weeks = excel['Weeks'];
      weeks.appendRow([
        TextCellValue('Date* (yyyy-mm-dd)'),
        TextCellValue('Opening BF*'),
        TextCellValue('Collection (vasool)'),
        TextCellValue('Interest (vaddi)'),
        TextCellValue('Processing Fee (agreement)'),
        TextCellValue('Investor In'),
        TextCellValue('Investor In - Interest'),
        TextCellValue('Loans Out (gross repayment)'),
        TextCellValue('Investor Out'),
        TextCellValue('Investor Out - Interest'),
        TextCellValue('Cheeti'),
        TextCellValue('Expenses Total'),
        TextCellValue('Closing BF*'),
      ]);
      weeks.appendRow([
        TextCellValue('2026-01-02'), TextCellValue('0'), TextCellValue('0'),
        TextCellValue('112800'), TextCellValue('6280'), TextCellValue('1000000'),
        TextCellValue('39000'), TextCellValue('626800'), TextCellValue(''),
        TextCellValue(''), TextCellValue(''), TextCellValue('900'),
        TextCellValue('491380'),
      ]);
      weeks.appendRow([
        TextCellValue('2026-01-09'), TextCellValue('491380'), TextCellValue('33020'),
        TextCellValue('76600'), TextCellValue('4940'), TextCellValue(''),
        TextCellValue(''), TextCellValue('423600'), TextCellValue(''),
        TextCellValue(''), TextCellValue(''), TextCellValue('900'),
        TextCellValue('181440'),
      ]);
      weeks.appendRow([for (var i = 0; i < 13; i++) TextCellValue('')]);

      final expenses = excel['Expenses'];
      expenses.appendRow([
        TextCellValue('Date* (yyyy-mm-dd)'),
        TextCellValue('What it was*'),
        TextCellValue('Amount*'),
      ]);
      for (final e in const [
        ['2026-01-02', 'Petrol', '500'],
        ['2026-01-02', 'Sadaru', '400'],
        ['2026-01-09', 'Petrol', '500'],
        ['2026-01-09', 'Sadaru', '400'],
      ]) {
        expenses.appendRow([for (final c in e) TextCellValue(c)]);
      }
      excel.delete('Sheet1');
      return Uint8List.fromList(excel.save()!);
    }

    test('one map per week, expense lines nested under their own date', () {
      final rows = BulkOnboardingService.parseWeeklyBytes(realBook(), 'weekly.xlsx');

      expect(rows, hasLength(2));
      expect(rows.first['account_date'], '2026-01-02');
      expect(rows.first['interest'], '112800');
      expect(rows.first['fee'], '6280');
      expect(rows.first['loans_gross_out'], '626800');
      expect(rows.first['closing_bf'], '491380');
      expect(rows.first['expenses'], hasLength(2));
      expect((rows.first['expenses'] as List).first['label'], 'Petrol');

      // One week's closing is the next week's opening — the chain the server
      // refuses to import without.
      expect(rows[1]['opening_bf'], rows.first['closing_bf']);
    });

    test('a blank cell is left out rather than sent as zero', () {
      final rows = BulkOnboardingService.parseWeeklyBytes(realBook(), 'weekly.xlsx');
      expect(rows[1].containsKey('investor_in'), isFalse);
      expect(rows[1].containsKey('investor_out_interest'), isFalse);
    });

    test('a workbook with no Weeks sheet is refused, not silently empty', () {
      final excel = Excel.createExcel();
      excel['Something Else'].appendRow([TextCellValue('x')]);
      excel.delete('Sheet1');
      expect(
        () => BulkOnboardingService.parseWeeklyBytes(
            Uint8List.fromList(excel.save()!), 'weekly.xlsx'),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });

  group('parseShareholderBytes', () {
    test('reads the share list, skipping unnamed rows', () {
      final excel = Excel.createExcel();
      final sheet = excel['Shareholders'];
      sheet.appendRow([
        TextCellValue('Name*'),
        TextCellValue('Share %*'),
        TextCellValue('Share Amount'),
        TextCellValue('ROI (Rs per 100 / month)'),
        TextCellValue('Paid On (yyyy-mm-dd)'),
        TextCellValue('Amount Received'),
      ]);
      sheet.appendRow([
        TextCellValue('TADI SRINIVASA REDDY'), TextCellValue('15'), TextCellValue(''),
        TextCellValue('1.5'), TextCellValue('2026-03-31'), TextCellValue('75300'),
      ]);
      sheet.appendRow([TextCellValue(''), TextCellValue('10')]);
      excel.delete('Sheet1');

      final rows = BulkOnboardingService.parseShareholderBytes(
          Uint8List.fromList(excel.save()!), 'shareholders.xlsx');

      expect(rows, hasLength(1));
      expect(rows.first['full_name'], 'TADI SRINIVASA REDDY');
      expect(rows.first['share_percent'], '15');
      // Left blank: the server works it out from the percent and the declared
      // profit rather than being handed a zero.
      expect(rows.first.containsKey('share_amount'), isFalse);
      expect(rows.first['amount_received'], '75300');
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
