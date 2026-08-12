/// Period-scoped statement export for the history screen.
///
/// Separate from BackupExportService on purpose. That one produces a whole-
/// business backup and takes no period at all; wiring a period picker to it
/// would offer the user a choice the file then ignores — a statement labelled
/// "Last 30 days" containing everything since the business opened. Same
/// `excel` dependency, same temp-file-and-share mechanism, different job.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'ledger_history_service.dart';
import 'mana_time.dart';

/// A statement period the user picked.
class StatementPeriod {
  final String labelKey;
  final DateTime from;
  final DateTime to;

  const StatementPeriod({
    required this.labelKey,
    required this.from,
    required this.to,
  });

  static StatementPeriod lastDays(int days, String labelKey) {
    final today = manaNowIst();
    return StatementPeriod(
      labelKey: labelKey,
      from: today.subtract(Duration(days: days - 1)),
      to: today,
    );
  }

  /// The Indian financial year, April to March. [startYear] 2025 means
  /// FY 2025-2026.
  static StatementPeriod financialYear(int startYear) => StatementPeriod(
        labelKey: 'financial_year',
        from: DateTime(startYear, 4, 1),
        to: DateTime(startYear + 1, 3, 31),
      );

  /// The FY containing today, by the IST clock.
  static int currentFinancialYearStart() {
    final now = manaNowIst();
    return now.month >= 4 ? now.year : now.year - 1;
  }
}

class StatementResult {
  final Uint8List bytes;
  final String fileName;
  final int eventCount;

  /// True when the export stopped at [LedgerStatementService.maxRows].
  /// Reported, never applied silently — a statement missing rows must say so.
  final bool truncated;

  const StatementResult({
    required this.bytes,
    required this.fileName,
    required this.eventCount,
    required this.truncated,
  });
}

class LedgerStatementService {
  LedgerStatementService(this._history);
  final LedgerHistoryService _history;

  /// The whole workbook is built in memory on a low-end handset before it is
  /// written, so this caps it well below the point a 2GB phone would die.
  /// Same reasoning as BackupExportService.maxRowsPerSheet.
  static const int maxRows = 20000;

  /// The server caps a single call at 200; page until the period is covered.
  static const int _pageSize = 200;

  Future<StatementResult> generate({
    required String businessId,
    required String businessName,
    required StatementPeriod period,
    LedgerFilter filter = const LedgerFilter(),
  }) async {
    final scoped = filter.copyWith(from: period.from, to: period.to);
    final events = <LedgerEvent>[];
    DateTime? cursor;
    var truncated = false;

    while (true) {
      final page = await _history.page(
        businessId: businessId,
        before: cursor,
        limit: _pageSize,
        filter: scoped,
      );
      events.addAll(page);
      if (page.length < _pageSize) break;
      if (events.length >= maxRows) {
        truncated = true;
        break;
      }
      cursor = page.last.occurredAt;
    }

    final excel = Excel.createExcel();
    final sheet = excel['Statement'];

    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Time'),
      TextCellValue('Type'),
      TextCellValue('Direction'),
      TextCellValue('Counterparty'),
      TextCellValue('Reference'),
      TextCellValue('Details'),
      TextCellValue('Money In'),
      TextCellValue('Money Out'),
    ]);

    for (final e in events) {
      sheet.appendRow([
        TextCellValue(e.businessDate),
        // Written as text, not a real time value: every timestamp in this
        // schema is IST with no offset stored, and handing Excel a date it
        // will re-interpret in the reader's own locale is how a statement
        // ends up 5h30m out. Same rule as BackupExportService.
        TextCellValue(manaClock12(e.occurredAt)),
        TextCellValue(e.type.wire),
        TextCellValue(e.isMoneyIn ? 'In' : 'Out'),
        TextCellValue(e.counterparty ?? ''),
        TextCellValue(e.reference ?? ''),
        TextCellValue(e.method ?? ''),
        IntCellValue(e.isMoneyIn ? e.amount : 0),
        IntCellValue(e.isMoneyIn ? 0 : e.amount),
      ]);
    }

    // Totals of THESE ROWS, labelled as such. Not the period's net from
    // day_ledger — a filtered statement's totals are the totals of what it
    // contains, and calling them anything else would misstate them.
    final moneyIn = events.where((e) => e.isMoneyIn).fold(0, (s, e) => s + e.amount);
    final moneyOut = events.where((e) => !e.isMoneyIn).fold(0, (s, e) => s + e.amount);
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([
      TextCellValue('Total of rows in this statement'),
      TextCellValue(''), TextCellValue(''), TextCellValue(''),
      TextCellValue(''), TextCellValue(''), TextCellValue(''),
      IntCellValue(moneyIn),
      IntCellValue(moneyOut),
    ]);

    // createExcel() seeds a default sheet; left in place it ships an empty
    // "Sheet1" as the first tab, which reads as a failed export.
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('The statement file could not be generated.');
    }

    return StatementResult(
      bytes: Uint8List.fromList(bytes),
      fileName: _fileName(businessName, period),
      eventCount: events.length,
      truncated: truncated,
    );
  }

  static String _fileName(String businessName, StatementPeriod period) {
    final safe = businessName
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    return 'ManaLine-Statement-${safe.isEmpty ? 'Business' : safe}'
        '-${manaDateOf(period.from)}-to-${manaDateOf(period.to)}.xlsx';
  }

  /// Temp rather than Documents, matching BackupExportService: the file is a
  /// copy of data the server already holds, so it does not need to survive on
  /// a shared handset, and leaving customer names in app storage is a privacy
  /// cost with no upside.
  Future<void> share(StatementResult result) async {
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

final ledgerStatementServiceProvider = Provider<LedgerStatementService>(
  (ref) => LedgerStatementService(ref.read(ledgerHistoryServiceProvider)),
);
