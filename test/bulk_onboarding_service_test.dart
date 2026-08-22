import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

List<List<String>> _readSheet(Uint8List bytes, String sheetName) {
  final book = Excel.decodeBytes(bytes);
  final table = book.tables[sheetName]!;
  return [
    for (final row in table.rows) [for (final cell in row) (cell?.value?.toString() ?? '')],
  ];
}

void main() {
  group('buildIdentityCorrectionFile', () {
    test('keeps every original row and annotates only the failed ones, in order', () {
      final rows = [
        {'full_name': 'Anjali', 'pin_code': '500001'},
        {'full_name': 'Bhanu', 'pin_code': '5AB'},
        {'full_name': 'Chandra', 'pin_code': '500003'},
      ];
      final errors = [const ImportRowError(row: 2, message: 'Pin Code must be numeric.')];

      final bytes = BulkOnboardingService.buildIdentityCorrectionFile(
        rows: rows,
        errors: errors,
        language: 'English',
      );
      final sheet = _readSheet(bytes, 'Identities');

      expect(sheet.length, 4); // header + 3 rows
      expect(sheet[1].last, ''); // Anjali — no error
      expect(sheet[2].last, 'Pin Code must be numeric.'); // Bhanu — flagged
      expect(sheet[3].last, ''); // Chandra — no error
      // By header index, not by position from the end — the sheet has grown a
      // Village column since, and "second from the right" was only ever
      // pin_code by accident.
      final pinColumn = BulkOnboardingService.identityColumns.indexOf('pin_code');
      expect(sheet[2][pinColumn], '5AB'); // original bad value preserved, not stripped
    });
  });

  group('buildEmiCorrectionFile', () {
    test('drops a customer whose whole schedule already recorded — re-upload must not double-collect', () {
      final schedule = [
        EmiScheduleRow(mlid: 'MLID-1', entries: [
          EmiEntry(amount: 500, date: DateTime(2026, 1, 5)),
          EmiEntry(amount: 500, date: DateTime(2026, 1, 12)),
        ]),
      ];
      // No errors at all for MLID-1 — every instalment succeeded.
      final bytes = BulkOnboardingService.buildEmiCorrectionFile(
        schedule: schedule,
        errors: const [],
        language: 'English',
      );
      final sheet = _readSheet(bytes, 'EMI History');
      expect(sheet.length, 1); // header only, MLID-1 dropped entirely
    });

    test('re-uploads only the failed instalments, repacked from EMI 1, leaving the succeeded ones out', () {
      final schedule = [
        EmiScheduleRow(mlid: 'MLID-1', entries: [
          EmiEntry(amount: 100, date: DateTime(2026, 1, 1)), // succeeds (instalment 1)
          EmiEntry(amount: 200, date: DateTime(2026, 1, 8)), // fails (instalment 2)
          EmiEntry(amount: 300, date: DateTime(2026, 1, 15)), // fails (instalment 3)
        ]),
      ];
      final errors = [
        const EmiRowError(mlid: 'MLID-1', instalment: 2, message: 'Loan is Closed.'),
        const EmiRowError(mlid: 'MLID-1', instalment: 3, message: 'Loan is Closed.'),
      ];

      final bytes = BulkOnboardingService.buildEmiCorrectionFile(
        schedule: schedule,
        errors: errors,
        language: 'English',
      );
      final sheet = _readSheet(bytes, 'EMI History');

      expect(sheet.length, 2); // header + MLID-1's row
      final row = sheet[1];
      expect(row[0], 'MLID-1');
      // Only the two failed pairs, repacked starting at EMI 1's slot.
      expect(row[2], '200'); // EMI 1 Amount
      expect(row[3], '2026-01-08'); // EMI 1 Date
      expect(row[4], '300'); // EMI 2 Amount
      expect(row[5], '2026-01-15'); // EMI 2 Date
      expect(row[6], ''); // EMI 3 Amount — nothing left over
    });

    test('a whole-row failure (no loan found) re-uploads every original entry', () {
      final schedule = [
        EmiScheduleRow(mlid: 'MLID-9', entries: [
          EmiEntry(amount: 400, date: DateTime(2026, 2, 1)),
        ]),
      ];
      final errors = [
        const EmiRowError(mlid: 'MLID-9', instalment: 0, message: 'No migrated loan found for this MLID.'),
      ];

      final bytes = BulkOnboardingService.buildEmiCorrectionFile(
        schedule: schedule,
        errors: errors,
        language: 'English',
      );
      final sheet = _readSheet(bytes, 'EMI History');
      expect(sheet.length, 2);
      expect(sheet[1][2], '400');
    });
  });
  _replayResume();
}

/// Resuming the instalment replay.
///
/// The replay is one record_collection per instalment — hundreds of calls, and
/// anything that stops a phone mid-round stops it partway. On 22 Aug 2026 it
/// stopped after 204 of them and the sheet could not simply be re-uploaded:
/// that would have collected those 204 a second time. The sheet is therefore
/// the TARGET STATE, and only the shortfall is recorded.
void _replayResume() {
  group('resuming an instalment replay', () {
    const loan = 'loan-1';
    EmiEntry entry(int amount, String date) =>
        EmiEntry(amount: amount, date: DateTime.parse(date));

    test('an instalment already on the loan is left alone', () {
      final recorded = {
        BulkOnboardingService.instalmentKey(loan, entry(500, '2026-01-09')): 1,
      };
      expect(
        BulkOnboardingService.consumeRecorded(
            recorded, BulkOnboardingService.instalmentKey(loan, entry(500, '2026-01-09'))),
        isTrue,
      );
    });

    test('a second identical payment on the same day is NOT a repeat', () {
      // The sheet asks for two; the loan has one. One is skipped, one recorded.
      final key = BulkOnboardingService.instalmentKey(loan, entry(500, '2026-01-09'));
      final recorded = {key: 1};
      expect(BulkOnboardingService.consumeRecorded(recorded, key), isTrue);
      expect(BulkOnboardingService.consumeRecorded(recorded, key), isFalse);
    });

    test('a different amount or date on the same loan is a new instalment', () {
      final recorded = {
        BulkOnboardingService.instalmentKey(loan, entry(500, '2026-01-09')): 1,
      };
      expect(
        BulkOnboardingService.consumeRecorded(
            recorded, BulkOnboardingService.instalmentKey(loan, entry(600, '2026-01-09'))),
        isFalse,
      );
      expect(
        BulkOnboardingService.consumeRecorded(
            recorded, BulkOnboardingService.instalmentKey(loan, entry(500, '2026-01-16'))),
        isFalse,
      );
    });

    test('the same instalment on a different loan is not skipped', () {
      final recorded = {
        BulkOnboardingService.instalmentKey(loan, entry(500, '2026-01-09')): 1,
      };
      expect(
        BulkOnboardingService.consumeRecorded(
            recorded, BulkOnboardingService.instalmentKey('loan-2', entry(500, '2026-01-09'))),
        isFalse,
      );
    });
  });
}
