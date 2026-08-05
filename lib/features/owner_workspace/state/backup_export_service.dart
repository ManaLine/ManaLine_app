import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/mana_time.dart';

/// P3 Backup — an Owner's records as a spreadsheet they can keep.
///
/// SCOPE: the six core ledger sheets — customers, loans, collections,
/// expenses, investments, day ledger. That is what an Owner hands an
/// accountant, and it maps onto the same source tables the BF work already
/// established. Deliberately NOT everything readable: audit_log alone would
/// dwarf the rest and is the row count most likely to exhaust memory on the
/// cheap handsets this app targets.
///
/// DELETED ROWS ARE EXCLUDED. A backup is of the live book. Since the delete
/// feature is a 30-day recoverable window, a deleted row is not yet gone — but
/// it is not part of the business's current position either, and exporting it
/// unmarked would put money back into a total the app itself no longer counts.
///
/// DATES ARE WRITTEN AS TEXT, not as spreadsheet dates. Every date and
/// timestamp in this schema is IST with no offset stored. Handing Excel a real
/// date cell invites it to reinterpret that against the reader's locale, and a
/// business_date that shifts by a day in someone's spreadsheet is exactly the
/// class of silently-wrong number this codebase treats as a safety issue. The
/// exported string is the stored string.
class BackupExportService {
  BackupExportService(this._db);

  final SupabaseClient _db;

  /// Excel's own hard ceiling is 1,048,575 data rows per sheet, but the real
  /// limit here is the handset: the whole workbook is built in memory before
  /// it is written. This caps any single sheet well below the point where a
  /// 2GB phone would die, and the cap is REPORTED rather than applied
  /// silently — a truncated backup that looks complete is worse than a refused
  /// one.
  static const int maxRowsPerSheet = 20000;

  Future<BackupResult> generate({
    required String businessId,
    required String businessName,
  }) async {
    final members = await _db
        .from('business_members')
        .select('membership_id, person_id, role')
        .eq('business_id', businessId);

    final personIds = <int>{
      for (final m in members)
        if (m['person_id'] != null) (m['person_id'] as num).toInt(),
    }.toList();

    final persons = personIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('persons')
            .select('person_id, full_name, mobile_number, mlid')
            .inFilter('person_id', personIds);

    final personById = {
      for (final p in persons) (p['person_id'] as num).toInt(): p,
    };

    final customerMembershipIds = [
      for (final m in members)
        if (m['role'] == 'Customer') m['membership_id'] as String,
    ];

    final customers = customerMembershipIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('customers')
            .select('customer_id, membership_id, customer_since, occupation')
            .inFilter('membership_id', customerMembershipIds);

    final loans = await _db
        .from('loans')
        .select('loan_number, customer_id, amount_given, repayment_amount, '
            'interest_amount, processing_fee, remaining_balance, '
            'installment_amount, repayment_type, effective_date, loan_status')
        .eq('business_id', businessId)
        .isFilter('deleted_at', null)
        .order('effective_date');

    // Collections carry loan_id, not business_id, so they are reached through
    // this business's loans. Named embed avoided on purpose: PostgREST needs
    // the FK spelled out when two exist between the same tables, and a
    // PGRST201 here would fail the whole backup.
    final loanIdRows = await _db
        .from('loans')
        .select('loan_id')
        .eq('business_id', businessId)
        .isFilter('deleted_at', null);
    final loanIds = [for (final l in loanIdRows) l['loan_id'] as String];

    final collections = loanIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('collections')
            .select('receipt_number, loan_id, collected_amount, business_date, '
                'result_type, payer_type')
            .inFilter('loan_id', loanIds)
            .isFilter('deleted_at', null)
            .order('business_date');

    final expenses = await _db
        .from('expenses')
        .select('business_date, category, amount, remarks')
        .eq('business_id', businessId)
        .isFilter('deleted_at', null)
        .order('business_date');

    final investments = await _db
        .from('investments')
        .select('investment_id, principal_amount, effective_date, status')
        .eq('business_id', businessId)
        .isFilter('deleted_at', null)
        .order('effective_date');

    final ledger = await _db
        .from('day_ledger')
        .select('business_date, opening_balance, total_collections, '
            'total_loan_distribution, investor_deposits, investor_withdrawals, '
            'total_expenses, cheti_paid, cheti_received, short_amount, '
            'excess_amount, closing_balance')
        .eq('business_id', businessId)
        .order('business_date');

    final excel = Excel.createExcel();
    final truncated = <String>[];

    void sheet(String name, List<String> headers,
        List<Map<String, dynamic>> rows, List<CellValue?> Function(Map<String, dynamic>) toRow) {
      final s = excel[name];
      s.appendRow([for (final h in headers) TextCellValue(h)]);
      final capped = rows.length > maxRowsPerSheet;
      if (capped) truncated.add('$name (${rows.length} rows)');
      for (final r in rows.take(maxRowsPerSheet)) {
        s.appendRow(toRow(r));
      }
    }

    CellValue? txt(Object? v) =>
        v == null ? null : TextCellValue(v.toString());
    CellValue? money(Object? v) =>
        v == null ? null : IntCellValue((v as num).toInt());

    sheet(
      'Customers',
      ['Customer Id', 'Name', 'MLID', 'Mobile', 'Customer Since', 'Occupation'],
      List<Map<String, dynamic>>.from(customers),
      (c) {
        final m = members.firstWhere(
          (m) => m['membership_id'] == c['membership_id'],
          orElse: () => <String, dynamic>{},
        );
        final p = m['person_id'] == null
            ? null
            : personById[(m['person_id'] as num).toInt()];
        return [
          txt(c['customer_id']),
          txt(p?['full_name']),
          txt(p?['mlid']),
          txt(p?['mobile_number']),
          txt(c['customer_since']),
          txt(c['occupation']),
        ];
      },
    );

    sheet(
      'Loans',
      [
        'Loan Number', 'Customer Id', 'Amount Given', 'Repayment Amount',
        'Interest', 'Processing Fee', 'Remaining Balance', 'Installment',
        'Repayment Type', 'Effective Date', 'Status',
      ],
      List<Map<String, dynamic>>.from(loans),
      (l) => [
        txt(l['loan_number']),
        txt(l['customer_id']),
        money(l['amount_given']),
        money(l['repayment_amount']),
        money(l['interest_amount']),
        money(l['processing_fee']),
        money(l['remaining_balance']),
        money(l['installment_amount']),
        txt(l['repayment_type']),
        txt(l['effective_date']),
        txt(l['loan_status']),
      ],
    );

    sheet(
      'Collections',
      ['Receipt', 'Loan Id', 'Amount', 'Business Date', 'Result', 'Payer'],
      List<Map<String, dynamic>>.from(collections),
      (c) => [
        txt(c['receipt_number']),
        txt(c['loan_id']),
        money(c['collected_amount']),
        txt(c['business_date']),
        txt(c['result_type']),
        txt(c['payer_type']),
      ],
    );

    sheet(
      'Expenses',
      ['Business Date', 'Category', 'Amount', 'Remarks'],
      List<Map<String, dynamic>>.from(expenses),
      (e) => [
        txt(e['business_date']),
        txt(e['category']),
        money(e['amount']),
        txt(e['remarks']),
      ],
    );

    sheet(
      'Investments',
      ['Investment Id', 'Principal', 'Effective Date', 'Status'],
      List<Map<String, dynamic>>.from(investments),
      (i) => [
        txt(i['investment_id']),
        money(i['principal_amount']),
        txt(i['effective_date']),
        txt(i['status']),
      ],
    );

    sheet(
      'Day Ledger',
      [
        'Business Date', 'Opening', 'Collections', 'Loans Given', 'Deposits',
        'Withdrawals', 'Expenses', 'Cheti Paid', 'Cheti Received', 'Short',
        'Excess', 'Closing',
      ],
      List<Map<String, dynamic>>.from(ledger),
      (d) => [
        txt(d['business_date']),
        money(d['opening_balance']),
        money(d['total_collections']),
        money(d['total_loan_distribution']),
        money(d['investor_deposits']),
        money(d['investor_withdrawals']),
        money(d['total_expenses']),
        money(d['cheti_paid']),
        money(d['cheti_received']),
        money(d['short_amount']),
        money(d['excess_amount']),
        money(d['closing_balance']),
      ],
    );

    // createExcel() seeds a default sheet. Left in place it ships an empty
    // "Sheet1" as the first tab, which reads as a failed export.
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('The backup file could not be generated.');
    }

    return BackupResult(
      bytes: Uint8List.fromList(bytes),
      fileName: _fileNameFor(businessName),
      truncatedSheets: truncated,
      counts: {
        'Customers': customers.length,
        'Loans': loans.length,
        'Collections': collections.length,
        'Expenses': expenses.length,
        'Investments': investments.length,
        'Day Ledger': ledger.length,
      },
    );
  }

  /// Business name plus the IST business date, so two backups taken on
  /// different days never collide in a Downloads folder.
  static String _fileNameFor(String businessName) {
    final safe = businessName
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    return 'ManaLine-${safe.isEmpty ? 'Backup' : safe}-${manaBusinessDate()}.xlsx';
  }

  /// Writes to the temporary directory and hands the file to the system share
  /// sheet. Temp rather than Documents on purpose: the file is a copy of data
  /// the server already holds, so it does not need to survive on a shared
  /// handset, and leaving customer names in app storage is a privacy cost with
  /// no upside.
  Future<void> shareWorkbook(BackupResult result) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${result.fileName}');
    await file.writeAsBytes(result.bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, name: result.fileName)],
        subject: result.fileName,
      ),
    );
  }
}

class BackupResult {
  final Uint8List bytes;
  final String fileName;

  /// Sheets that hit [BackupExportService.maxRowsPerSheet]. Surfaced to the
  /// user rather than swallowed — a backup missing rows must say so.
  final List<String> truncatedSheets;
  final Map<String, int> counts;

  const BackupResult({
    required this.bytes,
    required this.fileName,
    required this.truncatedSheets,
    required this.counts,
  });
}

final backupExportServiceProvider = Provider<BackupExportService>(
  (ref) => BackupExportService(Supabase.instance.client),
);
