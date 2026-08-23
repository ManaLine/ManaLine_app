import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';

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
  _memberSearch();
}

/// Searching the people already on the books.
///
/// Investors and shareholders are picked, not retyped. Every MLID an Owner
/// copies from one screen into a spreadsheet is a chance to attach money to
/// the wrong person, and a business has a handful of investors — this one has
/// three — so the spreadsheet was overhead the task never asked for.
void _memberSearch() {
  group('finding a person to add', () {
    const people = [
      ManaMemberRef(mlid: 'MLPI142496231', fullName: 'karri bhaskara reddy', village: 'Uranduru'),
      ManaMemberRef(mlid: 'MLPI142496230', fullName: 'tadi srinivasa reddy', village: 'Someswaram'),
      ManaMemberRef(mlid: 'MLPI142496232', fullName: 'Karri Siri Manikanta Reddy'),
    ];

    List<String> search(String q) =>
        [for (final p in people) if (p.matches(q)) p.mlid];

    test('an empty search shows everyone', () {
      expect(search('').length, 3);
      expect(search('   ').length, 3);
    });

    test('finds by name, whatever the case', () {
      expect(search('bhaskara'), ['MLPI142496231']);
      expect(search('TADI'), ['MLPI142496230']);
    });

    test('finds by MLID, including a fragment of it', () {
      expect(search('MLPI142496232'), ['MLPI142496232']);
      expect(search('496230'), ['MLPI142496230']);
    });

    test('finds by village, which is often what an Owner remembers', () {
      expect(search('uranduru'), ['MLPI142496231']);
    });

    test('a person with no village on file is still searchable by name', () {
      expect(search('Manikanta'), ['MLPI142496232']);
    });

    test('a search matching nobody returns nobody rather than everybody', () {
      expect(search('zzz'), isEmpty);
    });
  });
  _villageLabel();
}

/// The Village column carries its pincode, and gets split back apart.
///
/// The dropdown offers the Owner's own villages as "Uranduru (517640)",
/// because a village name alone is not unique — this business works two
/// villages on 517640.
void _villageLabel() {
  group('a village picked from the list', () {
    Map<String, dynamic> split(String village, {String pin = ''}) {
      final row = <String, dynamic>{'village': village, 'pin_code': pin};
      BulkOnboardingService.splitVillageAndPin(row);
      return row;
    }

    test('splits into the village and its pincode', () {
      final r = split('Uranduru (517640)');
      expect(r['village'], 'Uranduru');
      expect(r['pin_code'], '517640');
    });

    test('handles a village whose own name has brackets in it', () {
      final r = split('Panagallu (Rural) (517640)');
      expect(r['village'], 'Panagallu (Rural)');
      expect(r['pin_code'], '517640');
    });

    test('leaves a hand-typed village exactly as written', () {
      final r = split('Some New Village', pin: '533261');
      expect(r['village'], 'Some New Village');
      expect(r['pin_code'], '533261');
    });

    test('never overwrites a pincode the Owner typed themselves', () {
      // A disagreement between the two is the import's to raise, not this
      // function's to paper over.
      final r = split('Uranduru (517640)', pin: '999999');
      expect(r['village'], 'Uranduru');
      expect(r['pin_code'], '999999');
    });

    test('ignores anything that is not a six digit pincode', () {
      expect(split('Village (12)')['village'], 'Village (12)');
      expect(split('Village (abcdef)')['village'], 'Village (abcdef)');
    });

    test('an empty village is left alone', () {
      expect(split('')['village'], '');
    });
  });
  _sheetDates();
}

/// Reading a date out of a spreadsheet cell.
///
/// The templates now ask for dd/mm/yyyy, which is what an Indian book writes.
/// Every date is normalised to yyyy-MM-dd here rather than handed to Postgres
/// as typed: a raw "03/04/2026" is read by the server's DateStyle, and on an
/// MDY setting that is 4 March rather than 3 April — a month's error with
/// nothing on screen to show for it.
void _sheetDates() {
  group('a date out of a spreadsheet cell', () {
    String? parse(String s) => BulkOnboardingService.normaliseSheetDate(s);

    test('reads dd/mm/yyyy, which is what the template asks for', () {
      expect(parse('20/03/2026'), '2026-03-20');
      expect(parse('2/1/2026'), '2026-01-02');
    });

    test('reads dd-mm-yyyy too', () {
      expect(parse('20-03-2026'), '2026-03-20');
    });

    test('still reads yyyy-mm-dd, which older templates asked for', () {
      expect(parse('2026-03-20'), '2026-03-20');
    });

    test('reads a real date cell, which arrives with a time attached', () {
      expect(parse('2026-03-20 00:00:00.000'), '2026-03-20');
    });

    test('a day over 12 settles the order outright', () {
      // 20 cannot be a month, so this is unambiguous however it was written.
      expect(parse('20/03/2026'), '2026-03-20');
    });

    test('refuses a date that does not exist rather than rolling it forward', () {
      // DateTime(2026, 2, 31) silently becomes 3 March — a wrong date wearing
      // a right one's clothes.
      expect(parse('31/02/2026'), isNull);
      expect(parse('32/01/2026'), isNull);
      expect(parse('20/13/2026'), isNull);
    });

    test('refuses nothing and nonsense', () {
      expect(parse(''), isNull);
      expect(parse('   '), isNull);
      expect(parse('last Tuesday'), isNull);
      expect(parse('20/03/26'), isNull);
    });
  });
  _retiredHeadingsStillWork();
}

/// A heading is a contract with the files already on someone's phone.
///
/// The date columns used to say (yyyy-mm-dd) and now say (dd/mm/yyyy).
/// Headings are matched by their text, so that rename alone would have made
/// every previously downloaded template unreadable — the Owner told "These
/// columns are missing: effective_date" about a file this app generated for
/// them.
void _retiredHeadingsStillWork() {
  test('a customer sheet with the old date headings still imports', () {
    final excel = Excel.createExcel();
    final sheet = excel['Weekly'];
    sheet.appendRow([
      TextCellValue('MLID'),
      TextCellValue('Name'),
      TextCellValue('Village'),
      TextCellValue('Amount Given*'),
      TextCellValue('Repayment Amount*'),
      TextCellValue('Remaining Balance*'),
      // The retired wording, exactly as an older template wrote it.
      TextCellValue('Issued Date* (yyyy-mm-dd)'),
      TextCellValue('Instalment Amount*'),
    ]);
    sheet.appendRow([
      TextCellValue('MLTI001'),
      TextCellValue('Someone'),
      TextCellValue('Uranduru'),
      TextCellValue('5880'),
      TextCellValue('7200'),
      TextCellValue('1800'),
      TextCellValue('2026-01-15'),
      TextCellValue('600'),
    ]);
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final parse = BulkOnboardingService.parseCustomerGridBytes(
        Uint8List.fromList(excel.save()!), 'old.xlsx');
    expect(parse.loans, hasLength(1));
    expect(parse.loans.single['effective_date'], '2026-01-15');
  });
}
