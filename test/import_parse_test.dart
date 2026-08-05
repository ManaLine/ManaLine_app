// ignore_for_file: prefer_const_constructors
//
// excel's CellValue subclasses are inconsistently const: TextCellValue and
// IntCellValue have const constructors, DateCellValue and DoubleCellValue do
// not. Marking only some of them const makes these fixture rows harder to read
// than the lint is worth, and a const list is impossible while any member is
// non-const.

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/import_service.dart';

/// Parsing is the only part of Import that is the client's job — the server
/// owns every rule about what a valid loan is. So these tests cover reading a
/// file and nothing about money.
void main() {
  Uint8List csv(String s) => Uint8List.fromList(utf8.encode(s));

  const header =
      'customer_id,amount_given,repayment_amount,remaining_balance,'
      'effective_date,repayment_type,installment_amount';

  group('csv', () {
    test('reads a well-formed sheet', () {
      final p = ImportService.parseBytes(
        csv('$header\nabc,10000,12000,9000,2026-07-01,Daily,120\n'),
        'book.csv',
      );
      expect(p.rows, hasLength(1));
      expect(p.rows.first['customer_id'], 'abc');
      expect(p.rows.first['amount_given'], '10000');
      expect(p.rows.first['repayment_type'], 'Daily');
    });

    test('headings are matched loosely', () {
      // An Owner editing a spreadsheet should not have to preserve
      // capitalisation or underscores to be understood.
      final p = ImportService.parseBytes(
        csv('Customer ID,Amount Given,REPAYMENT_AMOUNT,Remaining Balance,'
            'Effective Date,Repayment Type,Installment Amount\n'
            'abc,10000,12000,9000,2026-07-01,Daily,120\n'),
        'book.csv',
      );
      expect(p.rows.first['customer_id'], 'abc');
      expect(p.rows.first['installment_amount'], '120');
    });

    test('a trailing blank line is not a loan', () {
      final p = ImportService.parseBytes(
        csv('$header\nabc,10000,12000,9000,2026-07-01,Daily,120\n\n\n'),
        'book.csv',
      );
      expect(p.rows, hasLength(1));
    });

    test('columns the Owner added for themselves are ignored', () {
      final p = ImportService.parseBytes(
        csv('$header,my notes\nabc,10000,12000,9000,2026-07-01,Daily,120,ask Ravi\n'),
        'book.csv',
      );
      expect(p.rows.first.containsKey('my_notes'), isFalse);
      expect(p.rows.first['customer_id'], 'abc');
    });

    test('quoted fields survive commas', () {
      final p = ImportService.parseBytes(
        csv('$header\n"ab,c",10000,12000,9000,2026-07-01,Daily,120\n'),
        'book.csv',
      );
      expect(p.rows.first['customer_id'], 'ab,c');
    });

    test('a missing required column names what is missing', () {
      expect(
        () => ImportService.parseBytes(
          csv('customer_id,amount_given\nabc,10000\n'),
          'book.csv',
        ),
        throwsA(isA<ImportFormatException>().having(
          (e) => e.message, 'message', contains('repayment_amount'))),
      );
    });

    test('an empty file is refused rather than imported as nothing', () {
      expect(
        () => ImportService.parseBytes(csv(''), 'book.csv'),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });

  group('xlsx', () {
    /// Builds a real workbook so the reader is tested against the format it
    /// will actually meet, not a hand-made fixture.
    Uint8List workbook(List<List<CellValue?>> rows, {String sheet = 'Loans'}) {
      final x = Excel.createExcel();
      final s = x[sheet];
      for (final r in rows) {
        s.appendRow(r);
      }
      if (x.sheets.containsKey('Sheet1') && sheet != 'Sheet1') {
        x.delete('Sheet1');
      }
      return Uint8List.fromList(x.save()!);
    }

    test('whole-rupee doubles lose the trailing .0', () {
      // Excel hands back 12000.0 for a number typed as 12000. The money
      // columns are numeric(_,0), so a trailing .0 is noise the server would
      // have to strip.
      final bytes = workbook([
        [for (final h in header.split(',')) TextCellValue(h)],
        [
          TextCellValue('abc'),
          DoubleCellValue(10000.0),
          DoubleCellValue(12000.0),
          DoubleCellValue(9000.0),
          TextCellValue('2026-07-01'),
          TextCellValue('Daily'),
          IntCellValue(120),
        ],
      ]);
      final p = ImportService.parseBytes(bytes, 'book.xlsx');
      expect(p.rows.first['amount_given'], '10000');
      expect(p.rows.first['repayment_amount'], '12000');
      expect(p.rows.first['installment_amount'], '120');
    });

    test('a real date cell becomes yyyy-mm-dd', () {
      // Excel's own toString carries a time component the date column rejects.
      final bytes = workbook([
        [for (final h in header.split(',')) TextCellValue(h)],
        [
          TextCellValue('abc'),
          IntCellValue(10000),
          IntCellValue(12000),
          IntCellValue(9000),
          DateCellValue(year: 2026, month: 7, day: 1),
          TextCellValue('Daily'),
          IntCellValue(120),
        ],
      ]);
      final p = ImportService.parseBytes(bytes, 'book.xlsx');
      expect(p.rows.first['effective_date'], '2026-07-01');
    });

    test('a sheet named something else is still read', () {
      // Files exported from other software will not have a "Loans" tab.
      final bytes = workbook([
        [for (final h in header.split(',')) TextCellValue(h)],
        [
          TextCellValue('abc'),
          IntCellValue(10000),
          IntCellValue(12000),
          IntCellValue(9000),
          TextCellValue('2026-07-01'),
          TextCellValue('Daily'),
          IntCellValue(120),
        ],
      ], sheet: 'Old Book');
      final p = ImportService.parseBytes(bytes, 'book.xlsx');
      expect(p.rows, hasLength(1));
    });

    test('a file that is not a workbook is refused clearly', () {
      expect(
        () => ImportService.parseBytes(
            Uint8List.fromList([1, 2, 3, 4]), 'book.xlsx'),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });

  test('required and optional columns do not overlap', () {
    // A column in both lists would be silently optional, which is how a
    // required field stops being enforced without anyone editing a check.
    for (final c in ImportService.requiredColumns) {
      expect(ImportService.optionalColumns, isNot(contains(c)));
    }
  });
}
