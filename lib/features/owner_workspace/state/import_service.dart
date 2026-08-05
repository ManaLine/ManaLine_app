import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// P3 Import — bulk entry of a business's pre-existing loan book.
///
/// The server does the validating. Every row goes through
/// app.import_migrated_loans, which feeds app.migrate_loan — the same function
/// OW-018 uses to enter one loan by hand. This class deliberately does NOT
/// re-check amounts, dates or balances: a second set of money rules on the
/// client would drift from the first, and the client's copy would be the one
/// nobody notices is wrong. What happens here is parsing, and nothing else.
///
/// The one exception is the header row, which has to be understood before
/// anything can be sent at all.
class ImportService {
  ImportService(this._db);

  final SupabaseClient _db;

  /// Column names the template writes and the parser accepts. Matching is done
  /// on a normalised key (lowercased, non-alphanumerics collapsed to
  /// underscore) so "Amount Given", "amount_given" and "AMOUNT GIVEN" are the
  /// same column — an Owner editing a spreadsheet should not have to preserve
  /// capitalisation to be understood.
  static const requiredColumns = <String>[
    'customer_id',
    'amount_given',
    'repayment_amount',
    'remaining_balance',
    'effective_date',
    'repayment_type',
    'installment_amount',
  ];

  static const optionalColumns = <String>[
    'grace_period_days',
    'processing_fee',
    'collection_agent_membership_id',
  ];

  static String normalise(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  // ---------------------------------------------------------------------
  // Template
  // ---------------------------------------------------------------------

  /// A template with the loan columns, plus a reference sheet of this
  /// business's customers.
  ///
  /// The reference sheet is the point. migrate_loan takes a customer_id UUID,
  /// and no Owner is going to type 36 hex characters correctly forty times —
  /// they copy them from the sheet beside the one they are filling in.
  Future<Uint8List> buildTemplate({required String businessId}) async {
    final members = await _db
        .from('business_members')
        .select('membership_id, person_id, role')
        .eq('business_id', businessId)
        .eq('role', 'Customer');

    final personIds = <int>{
      for (final m in members)
        if (m['person_id'] != null) (m['person_id'] as num).toInt(),
    }.toList();

    final persons = personIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('persons')
            .select('person_id, full_name, mlid')
            .inFilter('person_id', personIds);
    final personById = {
      for (final p in persons) (p['person_id'] as num).toInt(): p,
    };

    final membershipIds = [
      for (final m in members) m['membership_id'] as String,
    ];
    final customers = membershipIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('customers')
            .select('customer_id, membership_id')
            .inFilter('membership_id', membershipIds);

    final excel = Excel.createExcel();

    final loans = excel['Loans'];
    loans.appendRow([
      for (final c in [...requiredColumns, ...optionalColumns])
        TextCellValue(c),
    ]);

    final ref = excel['Customers (Reference)'];
    ref.appendRow([
      TextCellValue('customer_id'),
      TextCellValue('name'),
      TextCellValue('mlid'),
    ]);
    for (final c in customers) {
      final m = members.firstWhere(
        (m) => m['membership_id'] == c['membership_id'],
        orElse: () => <String, dynamic>{},
      );
      final p = m['person_id'] == null
          ? null
          : personById[(m['person_id'] as num).toInt()];
      ref.appendRow([
        TextCellValue(c['customer_id'].toString()),
        TextCellValue((p?['full_name'] ?? '').toString()),
        TextCellValue((p?['mlid'] ?? '').toString()),
      ]);
    }

    final notes = excel['Notes'];
    for (final line in const [
      'Fill in the Loans sheet. One row per pre-existing loan.',
      '',
      'customer_id            copy from the Customers (Reference) sheet',
      'amount_given           cash that actually left your hand',
      'repayment_amount       total the customer repays',
      'remaining_balance      still owed today (0 if fully repaid)',
      'effective_date         yyyy-mm-dd, the date the loan was given',
      'repayment_type         Daily, Weekly or Monthly',
      'installment_amount     one instalment',
      '',
      'grace_period_days, processing_fee and',
      'collection_agent_membership_id are optional.',
      '',
      'Rupees only - paise cannot be stored.',
      'If any row is wrong, nothing is imported. You fix the sheet and',
      'upload again, so the book is never half-entered.',
    ]) {
      notes.appendRow([TextCellValue(line)]);
    }

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('The template could not be generated.');
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> shareTemplate(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ManaLine-Loan-Import-Template.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, name: 'ManaLine-Loan-Import-Template.xlsx')],
        subject: 'MANA LINE loan import template',
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------

  /// Turns a picked file into rows. Accepts .xlsx and .csv.
  ///
  /// Throws [ImportFormatException] when the file cannot be understood at all
  /// — an unreadable workbook or a missing required column. Anything that is
  /// merely a bad VALUE is left for the server to reject, so there is exactly
  /// one authority on what a valid loan is.
  /// Static because it is a pure function of the bytes — no client, no
  /// network, no business. That is also what makes it the part of this feature
  /// worth testing directly.
  static ImportParse parseBytes(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();
    final table = lower.endsWith('.csv')
        ? _parseCsv(utf8.decode(bytes, allowMalformed: true))
        : _parseXlsx(bytes);

    if (table.isEmpty) {
      throw const ImportFormatException('The file has no rows.');
    }

    final header = [for (final c in table.first) normalise(c)];
    final missing = [
      for (final c in requiredColumns)
        if (!header.contains(c)) c,
    ];
    if (missing.isNotEmpty) {
      throw ImportFormatException(
        'These columns are missing: ${missing.join(", ")}. '
        'Use the template to be sure of the headings.',
      );
    }

    final rows = <Map<String, dynamic>>[];
    for (final raw in table.skip(1)) {
      // A trailing blank line is normal in a hand-edited sheet and must not be
      // reported as an invalid loan.
      if (raw.every((c) => c.trim().isEmpty)) continue;

      final row = <String, dynamic>{};
      for (var i = 0; i < header.length && i < raw.length; i++) {
        final key = header[i];
        if (!requiredColumns.contains(key) && !optionalColumns.contains(key)) {
          continue; // an extra column the Owner added for their own notes
        }
        final v = raw[i].trim();
        if (v.isNotEmpty) row[key] = v;
      }
      rows.add(row);
    }

    return ImportParse(rows: rows, sheetColumns: header);
  }

  static List<List<String>> _parseXlsx(Uint8List bytes) {
    final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (e) {
      throw ImportFormatException('This file could not be read as a '
          'spreadsheet. If it came from another app, save it as .xlsx or .csv '
          'and try again. ($e)');
    }

    // Prefer the sheet the template creates; otherwise the first one with
    // content, so a file exported from another program still works.
    final sheet = book.tables['Loans'] ??
        book.tables.values.firstWhere(
          (t) => t.rows.isNotEmpty,
          orElse: () => throw const ImportFormatException(
              'The workbook has no sheet with any rows in it.'),
        );

    return [
      for (final row in sheet.rows)
        [
          for (final cell in row) _cellText(cell?.value),
        ],
    ];
  }

  /// Dates are rendered back to yyyy-mm-dd rather than passed through
  /// toString(). Excel hands back a DateTime, and its default string form
  /// carries a time component the date column would then reject.
  static String _cellText(CellValue? v) {
    if (v == null) return '';
    if (v is TextCellValue) return v.value.toString().trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      // Whole rupees. 12000.0 must reach the server as "12000", because the
      // money columns are numeric(_,0) and a trailing .0 is noise.
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    if (v is DateCellValue) {
      return '${v.year.toString().padLeft(4, '0')}-'
          '${v.month.toString().padLeft(2, '0')}-'
          '${v.day.toString().padLeft(2, '0')}';
    }
    if (v is BoolCellValue) return v.value.toString();
    return v.toString().trim();
  }

  /// Minimal RFC4180 reader: quoted fields, doubled quotes, embedded commas
  /// and newlines. Written rather than pulled in as a dependency because it is
  /// forty lines and this project has just been bitten by a package that
  /// would not build.
  static List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
        continue;
      }
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        row.add(field.toString());
        field = StringBuffer();
      } else if (ch == '\n') {
        row.add(field.toString());
        field = StringBuffer();
        rows.add(row);
        row = <String>[];
      } else if (ch != '\r') {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  // ---------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------

  /// Sends every row in one call. The server imports all of them or none.
  ///
  /// A rejection arrives as a PostgrestException whose message carries
  /// `IMPORT_REJECTED {json}`; the JSON is pulled back out so the screen can
  /// list the problems row by row instead of showing one opaque database
  /// error.
  Future<ImportOutcome> submit({
    required String businessId,
    required List<Map<String, dynamic>> rows,
  }) async {
    try {
      final res = await _db.schema('app').rpc('import_migrated_loans', params: {
        'p_business_id': businessId,
        'p_rows': rows,
      });
      final map = Map<String, dynamic>.from(res as Map);
      return ImportOutcome(
        imported: (map['imported'] as num?)?.toInt() ?? 0,
        errors: const [],
      );
    } on PostgrestException catch (e) {
      final parsed = _rejectionFrom(e.message);
      if (parsed == null) rethrow;
      return parsed;
    }
  }

  static ImportOutcome? _rejectionFrom(String message) {
    final start = message.indexOf('IMPORT_REJECTED');
    if (start < 0) return null;
    final brace = message.indexOf('{', start);
    if (brace < 0) return null;
    try {
      final decoded = jsonDecode(message.substring(brace)) as Map<String, dynamic>;
      return ImportOutcome(
        imported: 0,
        errors: [
          for (final e in (decoded['errors'] as List? ?? const []))
            ImportRowError(
              row: ((e as Map)['row'] as num?)?.toInt() ?? 0,
              message: (e['error'] ?? '').toString(),
            ),
        ],
      );
    } catch (_) {
      // The payload was truncated or reshaped — fall back to the raw error
      // rather than inventing a row list.
      return null;
    }
  }
}

class ImportParse {
  final List<Map<String, dynamic>> rows;
  final List<String> sheetColumns;
  const ImportParse({required this.rows, required this.sheetColumns});
}

class ImportRowError {
  /// 1-based, matching the spreadsheet row the Owner is looking at (header
  /// excluded).
  final int row;
  final String message;
  const ImportRowError({required this.row, required this.message});
}

class ImportOutcome {
  final int imported;
  final List<ImportRowError> errors;
  const ImportOutcome({required this.imported, required this.errors});
  bool get rejected => errors.isNotEmpty;
}

class ImportFormatException implements Exception {
  final String message;
  const ImportFormatException(this.message);
  @override
  String toString() => message;
}

final importServiceProvider =
    Provider<ImportService>((ref) => ImportService(Supabase.instance.client));
