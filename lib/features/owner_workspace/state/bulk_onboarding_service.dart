import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_mode_state.dart';

/// P3 Bulk Migration Wizard — onboard a pre-existing business's whole book in
/// three spreadsheets instead of one screen per person/loan/instalment.
///
/// Every write goes through the same RPCs the rest of the app already uses
/// (`app.bulk_import_identities`, `app.bulk_import_investments`,
/// `app.import_migrated_loans`, `app.record_collection`) — see
/// supabase/migrations/20260807074903_bulk_import_identities_and_profit_metrics.sql
/// for the reasoning behind each one. This file is parsing and orchestration
/// only, same discipline as ImportService: the server is the one authority on
/// whether a row is valid.
///
/// LOCALISATION: column headers are shown in the Owner's own language
/// (English or Telugu — the only two the app offers), but parsing accepts
/// either — a template downloaded in Telugu and one downloaded in English
/// describe the same columns, so [normalise] is checked against both
/// languages' labels, not just the active one. `ui_translations` is not
/// used here: these are spreadsheet column headers, not screen copy, and
/// there is no live network dependency for opening a downloaded file.
class BulkOnboardingService {
  BulkOnboardingService(this._db, this._ref);

  final SupabaseClient _db;
  final Ref _ref;

  static String normalise(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  // ---------------------------------------------------------------------
  // Column labels — canonical key -> label per language. English first
  // column is also the fallback normalisation target.
  // ---------------------------------------------------------------------

  static const _identityLabels = <String, Map<String, String>>{
    'aadhaar_number': {
      'English': 'Aadhaar Number', 'Telugu': 'ఆధార్ నంబర్',
    },
    'gender_digit': {
      'English': 'Gender (M/F/O)*', 'Telugu': 'లింగం (M/F/O)*',
    },
    'full_name': {
      'English': 'Name*', 'Telugu': 'పేరు*',
    },
    'father_husband_name': {
      'English': 'C/O Name*', 'Telugu': 'తండ్రి/భర్త పేరు*',
    },
    'user_type': {
      'English': 'User Type (Agent/Customer/Investor)*', 'Telugu': 'యూజర్ రకం (Agent/Customer/Investor)*',
    },
    'mobile_number': {
      'English': 'Phone', 'Telugu': 'ఫోన్',
    },
    'door_no': {
      'English': 'Door No', 'Telugu': 'డోర్ నంబర్',
    },
    'pin_code': {
      'English': 'Pin Code*', 'Telugu': 'పిన్ కోడ్*',
    },
  };

  static const identityRequired = ['gender_digit', 'full_name', 'father_husband_name', 'user_type', 'pin_code'];
  static const identityOptional = ['aadhaar_number', 'mobile_number', 'door_no'];
  static const identityColumns = [
    'aadhaar_number', 'gender_digit', 'full_name', 'father_husband_name',
    'user_type', 'mobile_number', 'door_no', 'pin_code',
  ];

  /// Reverse lookup built once: every language's label, normalised, maps
  /// back to its canonical key. This is what lets a Telugu-filled sheet and
  /// an English-filled sheet both parse correctly.
  static Map<String, String> _aliasMap(Map<String, Map<String, String>> labels) {
    final out = <String, String>{};
    for (final entry in labels.entries) {
      out[normalise(entry.key)] = entry.key; // canonical key itself, hand-typed sheets
      for (final label in entry.value.values) {
        out[normalise(label)] = entry.key;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Step 1 — Identity template / parse / dedupe / submit
  // ---------------------------------------------------------------------

  Uint8List buildIdentityTemplate({required String language}) {
    final excel = Excel.createExcel();
    final sheet = excel['Identities'];
    sheet.appendRow([
      for (final key in identityColumns)
        TextCellValue(_identityLabels[key]?[language] ?? _identityLabels[key]!['English']!),
    ]);

    final notes = excel['Notes'];
    for (final line in const [
      'One row per person — Agent, Customer or Investor, all in this file.',
      'Gender, Name, C/O Name, User Type and Pin Code are required.',
      'User Type must be exactly Agent, Customer or Investor.',
      'Aadhaar is required for Agent and Investor, optional for Customer.',
      'Rows that look like an existing person will be shown to you to',
      'Merge (skip) or Ignore (import anyway) before anything is saved.',
    ]) {
      notes.appendRow([TextCellValue(line)]);
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The template could not be generated.');
    return Uint8List.fromList(bytes);
  }

  static ParsedSheet parseIdentityBytes(Uint8List bytes, String fileName) {
    final table = _decodeTable(bytes, fileName, preferredSheet: 'Identities');
    return _parseTable(table, identityRequired, identityOptional, _aliasMap(_identityLabels));
  }

  /// Owner-review step, BEFORE anything is written — calls the read-only
  /// `app.find_potential_duplicate_customers` RPC.
  Future<List<DuplicateMatch>> findDuplicates({
    required String businessId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final res = await _db.schema('app').rpc('find_potential_duplicate_customers', params: {
      'p_business_id': businessId,
      'p_rows': rows,
    });
    final map = Map<String, dynamic>.from(res as Map);
    final list = (map['duplicates'] as List? ?? const []).cast<Map<String, dynamic>>();
    return list
        .map((d) => DuplicateMatch(
              row: (d['row'] as num).toInt(),
              reason: d['reason'] as String,
              candidates: (d['candidates'] as List? ?? const [])
                  .cast<Map<String, dynamic>>()
                  .map((c) => '${c['full_name'] ?? ''} · ${c['mlid'] ?? ''}')
                  .toList(),
            ))
        .toList();
  }

  /// `dedupeDecisions` maps 1-based row number -> 'merge' (skip) or 'ignore'
  /// (import anyway). Only rows the Owner explicitly chose 'merge' on carry
  /// a `dedupe_decision: ignore` payload key — the RPC's own vocabulary is
  /// inverted from the wizard's (its `ignore` means "skip", ours means
  /// "import over the warning"), so the mapping happens right here, once.
  Future<ImportOutcome> submitIdentities({
    required String businessId,
    required List<Map<String, dynamic>> rows,
    Map<int, String> dedupeDecisions = const {},
  }) async {
    final payload = <Map<String, dynamic>>[];
    for (var i = 0; i < rows.length; i++) {
      final rowNumber = i + 1;
      final row = Map<String, dynamic>.from(rows[i]);
      if (dedupeDecisions[rowNumber] == 'skip') {
        row['dedupe_decision'] = 'ignore'; // RPC vocabulary: skip this row
      }
      payload.add(row);
    }
    try {
      final res = await _db.schema('app').rpc('bulk_import_identities', params: {
        'p_business_id': businessId,
        'p_rows': payload,
      });
      final map = Map<String, dynamic>.from(res as Map);
      final created = (map['created'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map((c) => CreatedIdentity(
                row: (c['row'] as num).toInt(),
                userType: c['user_type'] as String,
                mlid: c['mlid'] as String? ?? '',
              ))
          .toList();
      return ImportOutcome(imported: (map['imported'] as num?)?.toInt() ?? 0, errors: const [], created: created);
    } on PostgrestException catch (e) {
      final parsed = _rejectionFrom(e.message);
      if (parsed == null) rethrow;
      return parsed;
    }
  }

  /// Rejection from `submitIdentities` is all-or-nothing at the RPC, so
  /// every row in `rows` is still unimported even though only some failed
  /// validation. Rather than leave the Owner with just an inline error
  /// list, hand back the same rows with an Error column appended — nothing
  /// retyped, row order untouched (so "Row N" in the on-screen error still
  /// lines up), ready to fix and re-upload as-is.
  static Uint8List buildIdentityCorrectionFile({
    required List<Map<String, dynamic>> rows,
    required List<ImportRowError> errors,
    required String language,
  }) {
    return _buildCorrectionFile(
      sheetName: 'Identities',
      columns: identityColumns,
      labels: _identityLabels,
      rows: rows,
      errors: errors,
      language: language,
    );
  }

  static Uint8List _buildCorrectionFile({
    required String sheetName,
    required List<String> columns,
    required Map<String, Map<String, String>> labels,
    required List<Map<String, dynamic>> rows,
    required List<ImportRowError> errors,
    required String language,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];
    final errorByRow = {for (final e in errors) e.row: e.message};
    sheet.appendRow([
      for (final key in columns) TextCellValue(labels[key]?[language] ?? labels[key]!['English']!),
      TextCellValue('Error'),
    ]);
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      sheet.appendRow([
        for (final key in columns) TextCellValue((row[key] ?? '').toString()),
        TextCellValue(errorByRow[i + 1] ?? ''),
      ]);
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The corrected file could not be generated.');
    return Uint8List.fromList(bytes);
  }

  // ---------------------------------------------------------------------
  // Step 2 — 3-tab onboarding template / parse / submit
  // ---------------------------------------------------------------------

  static const _investorLabels = <String, Map<String, String>>{
    'invested_amount': {'English': 'Invested Amount*', 'Telugu': 'పెట్టుబడి మొత్తం*'},
    'roi': {'English': 'ROI (₹ per ₹100/month)*', 'Telugu': 'ROI*'},
    'interest_type': {'English': 'Interest Type (Simple/Yearly Compound)*', 'Telugu': 'వడ్డీ రకం*'},
    'invested_date': {'English': 'Invested Date* (yyyy-mm-dd)', 'Telugu': 'పెట్టుబడి తేదీ*'},
    'profit_percent': {'English': 'Profit %*', 'Telugu': 'లాభం %*'},
  };

  static const _customerLoanLabels = <String, Map<String, String>>{
    'amount_given': {'English': 'Amount Given*', 'Telugu': 'ఇచ్చిన మొత్తం*'},
    'repayment_amount': {'English': 'Repayment Amount*', 'Telugu': 'తిరిగి చెల్లించాల్సిన మొత్తం*'},
    'remaining_balance': {'English': 'Remaining Balance*', 'Telugu': 'మిగిలిన బ్యాలెన్స్*'},
    'effective_date': {'English': 'Issued Date* (yyyy-mm-dd)', 'Telugu': 'జారీ తేదీ*'},
    'repayment_type': {'English': 'Repayment Frequency (Daily/Weekly/Monthly)*', 'Telugu': 'తిరిగి చెల్లింపు వ్యవధి*'},
    'installment_amount': {'English': 'Instalment Amount*', 'Telugu': 'వాయిదా మొత్తం*'},
    'grace_period_end_date': {'English': 'Grace Period End Date (yyyy-mm-dd)', 'Telugu': 'గ్రేస్ పీరియడ్ ముగింపు తేదీ'},
    'loan_end_date': {'English': 'Loan End Date (informational only, yyyy-mm-dd)', 'Telugu': 'రుణం ముగింపు తేదీ (సమాచారం మాత్రమే)'},
    'processing_fee': {'English': 'Processing Fee', 'Telugu': 'ప్రాసెసింగ్ ఫీజు'},
  };

  static const _prefillLabels = <String, Map<String, String>>{
    'mlid': {'English': 'MLID', 'Telugu': 'MLID'},
    'full_name': {'English': 'Name', 'Telugu': 'పేరు'},
    'user_type': {'English': 'Type', 'Telugu': 'రకం'},
    'village': {'English': 'Village', 'Telugu': 'గ్రామం'},
  };

  static const investorRequired = ['invested_amount', 'roi', 'interest_type', 'invested_date', 'profit_percent'];
  static const customerLoanRequired = [
    'amount_given', 'repayment_amount', 'remaining_balance', 'effective_date',
    'repayment_type', 'installment_amount',
  ];
  static const customerLoanOptional = ['grace_period_end_date', 'loan_end_date', 'processing_fee'];

  /// Live-queries `business_members` per role rather than trusting Step 1's
  /// in-memory result, so Step 2 can be re-run any time the Owner has the
  /// business open — the file always reflects what is actually in the
  /// database, not what happened to be imported in this app session.
  Future<Uint8List> buildOnboardingTemplate({required String businessId, required String language}) async {
    final excel = Excel.createExcel();
    final prefillHeader = ['mlid', 'full_name', 'user_type', 'village']
        .map((k) => _prefillLabels[k]![language] ?? _prefillLabels[k]!['English']!)
        .toList();

    for (final role in const ['Agent', 'Investor', 'Customer']) {
      final rows = await _prefillRows(businessId, role);
      // Village A-Z, blanks last, name as tiebreak — so the sheet reads in
      // the same order as the Owner's paper ledger, which is organised by
      // village.
      rows.sort((a, b) {
        final va = (a.village ?? '').trim();
        final vb = (b.village ?? '').trim();
        if (va.isEmpty != vb.isEmpty) return va.isEmpty ? 1 : -1;
        final cmp = va.toLowerCase().compareTo(vb.toLowerCase());
        return cmp != 0 ? cmp : a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });
      final sheet = excel[role];
      final extraKeys = role == 'Investor'
          ? investorRequired
          : role == 'Customer'
              ? [...customerLoanRequired, ...customerLoanOptional]
              : const <String>[];
      final extraLabels = role == 'Investor' ? _investorLabels : _customerLoanLabels;
      sheet.appendRow([
        for (final h in prefillHeader) TextCellValue(h),
        for (final k in extraKeys) TextCellValue(extraLabels[k]![language] ?? extraLabels[k]!['English']!),
      ]);
      for (final r in rows) {
        sheet.appendRow([
          TextCellValue(r.mlid),
          TextCellValue(r.fullName),
          TextCellValue(role),
          TextCellValue(r.village ?? ''),
        ]);
      }
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The template could not be generated.');
    return Uint8List.fromList(bytes);
  }

  Future<List<_PrefillRow>> _prefillRows(String businessId, String role) async {
    final members = await _db
        .from('business_members')
        .select('membership_id, person_id, persons!business_members_person_id_fkey(person_id, full_name, mlid)')
        .eq('business_id', businessId)
        .eq('role', role)
        .neq('membership_status', 'Removed');
    final personIds = <int>{
      for (final m in members)
        if (m['person_id'] != null) (m['person_id'] as num).toInt(),
    }.toList();
    if (personIds.isEmpty) return const [];

    final addresses = personIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('person_addresses')
            .select('person_id, locations(village_town_name)')
            .inFilter('person_id', personIds)
            .eq('is_current', true);
    final villageByPerson = <int, String>{
      for (final a in addresses)
        if (a['locations'] != null)
          (a['person_id'] as num).toInt(): (a['locations'] as Map<String, dynamic>)['village_town_name'] as String,
    };

    return [
      for (final m in members)
        if (m['persons'] != null)
          _PrefillRow(
            mlid: (m['persons'] as Map<String, dynamic>)['mlid'] as String? ?? '',
            fullName: (m['persons'] as Map<String, dynamic>)['full_name'] as String? ?? '',
            village: villageByPerson[(m['person_id'] as num).toInt()],
          ),
    ];
  }

  /// Parses all three tabs from one workbook. A tab that is missing or has
  /// no data rows returns an empty list rather than an error — the Owner may
  /// only have new Investors this round, say, and an empty Agent tab is not
  /// a mistake.
  static Step2Parse parseOnboardingBytes(Uint8List bytes, String fileName) {
    final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (e) {
      throw ImportFormatException('This file could not be read as a spreadsheet. ($e)');
    }
    final investorAliases = {..._aliasMap(_prefillLabels), ..._aliasMap(_investorLabels)};
    final customerAliases = {..._aliasMap(_prefillLabels), ..._aliasMap(_customerLoanLabels)};

    ParsedSheet parseTab(String name, List<String> required, List<String> optional, Map<String, String> aliases) {
      final table = book.tables[name];
      if (table == null || table.rows.isEmpty) return const ParsedSheet(rows: [], sheetColumns: []);
      final grid = [
        for (final row in table.rows) [for (final cell in row) _cellText(cell?.value)],
      ];
      return _parseTable(grid, required, optional, aliases, prefillColumns: ['mlid', 'full_name', 'user_type', 'village']);
    }

    return Step2Parse(
      agent: parseTab('Agent', const [], const [], _aliasMap(_prefillLabels)),
      investor: parseTab('Investor', investorRequired, const [], investorAliases),
      customer: parseTab('Customer', customerLoanRequired, customerLoanOptional, customerAliases),
    );
  }

  Future<ImportOutcome> submitInvestments({
    required String businessId,
    required List<Map<String, dynamic>> rows,
  }) async {
    try {
      final res = await _db.schema('app').rpc('bulk_import_investments', params: {
        'p_business_id': businessId,
        'p_rows': rows,
      });
      final map = Map<String, dynamic>.from(res as Map);
      return ImportOutcome(imported: (map['imported'] as num?)?.toInt() ?? 0, errors: const []);
    } on PostgrestException catch (e) {
      final parsed = _rejectionFrom(e.message);
      if (parsed == null) rethrow;
      return parsed;
    }
  }

  /// `rows` carry `mlid` (from the prefill), never a raw `customer_id` — the
  /// Owner never sees a UUID. Resolved to `customer_id` here, then handed to
  /// `app.import_migrated_loans` exactly like OW-018's own bulk loan import,
  /// so the same money rules apply (amount_given vs repayment vs remaining
  /// balance, the generated column — see migrate_loan). `grace_period_days`
  /// is DERIVED from the Grace Period End Date column here, never typed —
  /// the sheet asks for a date because that is what an Owner's paper ledger
  /// records, not a day-count. `loan_end_date` is read and then discarded:
  /// there is no column for it, by design (task brief).
  Future<ImportOutcome> submitCustomerLoans({
    required String businessId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final mlids = [for (final r in rows) r['mlid'] as String? ?? ''].where((m) => m.isNotEmpty).toSet().toList();
    final customerIdByMlid = await _resolveCustomerIdsByMlid(businessId, mlids);

    final payload = <Map<String, dynamic>>[];
    for (final r in rows) {
      final row = Map<String, dynamic>.from(r);
      final mlid = row.remove('mlid') as String?;
      row.remove('full_name');
      row.remove('user_type');
      row.remove('village');
      final loanEndDate = row.remove('loan_end_date'); // informational only — never stored

      final graceEnd = row.remove('grace_period_end_date') as String?;
      if (graceEnd != null && graceEnd.isNotEmpty) {
        final issued = DateTime.tryParse(row['effective_date'] as String? ?? '');
        final end = DateTime.tryParse(graceEnd);
        if (issued != null && end != null) {
          row['grace_period_days'] = end.difference(issued).inDays;
        }
      }
      row['customer_id'] = customerIdByMlid[mlid];
      payload.add(row);
      // ignore: unused_local_variable
      loanEndDate;
    }

    try {
      final res = await _db.schema('app').rpc('import_migrated_loans', params: {
        'p_business_id': businessId,
        'p_rows': payload,
      });
      final map = Map<String, dynamic>.from(res as Map);
      return ImportOutcome(imported: (map['imported'] as num?)?.toInt() ?? 0, errors: const []);
    } on PostgrestException catch (e) {
      final parsed = _rejectionFrom(e.message);
      if (parsed == null) rethrow;
      return parsed;
    }
  }

  /// Same all-or-nothing-per-tab problem as Step 1, doubled — Investor and
  /// Customer submit independently, so either or both can come back
  /// rejected. One workbook, one tab per rejected side, each annotated the
  /// same way as [buildIdentityCorrectionFile].
  static Uint8List buildStep2CorrectionFile({
    required List<Map<String, dynamic>> investorRows,
    required List<ImportRowError> investorErrors,
    required List<Map<String, dynamic>> customerRows,
    required List<ImportRowError> customerErrors,
    required String language,
  }) {
    final excel = Excel.createExcel();
    const prefillCols = ['mlid', 'full_name', 'user_type', 'village'];

    void writeTab(
      String name,
      List<String> extraCols,
      Map<String, Map<String, String>> extraLabels,
      List<Map<String, dynamic>> rows,
      List<ImportRowError> errors,
    ) {
      final sheet = excel[name];
      final errorByRow = {for (final e in errors) e.row: e.message};
      sheet.appendRow([
        for (final k in prefillCols) TextCellValue(_prefillLabels[k]![language] ?? _prefillLabels[k]!['English']!),
        for (final k in extraCols) TextCellValue(extraLabels[k]![language] ?? extraLabels[k]!['English']!),
        TextCellValue('Error'),
      ]);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        sheet.appendRow([
          for (final k in prefillCols) TextCellValue((row[k] ?? '').toString()),
          for (final k in extraCols) TextCellValue((row[k] ?? '').toString()),
          TextCellValue(errorByRow[i + 1] ?? ''),
        ]);
      }
    }

    writeTab('Investor', investorRequired, _investorLabels, investorRows, investorErrors);
    writeTab('Customer', [...customerLoanRequired, ...customerLoanOptional], _customerLoanLabels, customerRows, customerErrors);

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The corrected file could not be generated.');
    return Uint8List.fromList(bytes);
  }

  Future<Map<String, String>> _resolveCustomerIdsByMlid(String businessId, List<String> mlids) async {
    if (mlids.isEmpty) return {};
    final rows = await _db
        .from('customers')
        .select('customer_id, business_members!inner(business_id, persons!inner(mlid))')
        .eq('business_members.business_id', businessId);
    final map = <String, String>{};
    for (final r in rows as List) {
      final person = (r['business_members'] as Map<String, dynamic>)['persons'] as Map<String, dynamic>;
      final mlid = person['mlid'] as String?;
      if (mlid != null && mlids.contains(mlid)) map[mlid] = r['customer_id'] as String;
    }
    return map;
  }

  // ---------------------------------------------------------------------
  // Step 3 (optional) — EMI history, 1..100 amount+date pairs
  // ---------------------------------------------------------------------

  static const emiCount = 100;

  Uint8List buildEmiTemplate({required List<CustomerRef> customers, required String language}) {
    final excel = Excel.createExcel();
    final sheet = excel['EMI History'];
    sheet.appendRow([
      TextCellValue(_prefillLabels['mlid']![language] ?? 'MLID'),
      TextCellValue(_prefillLabels['full_name']![language] ?? 'Name'),
      for (var i = 1; i <= emiCount; i++) ...[
        TextCellValue('EMI $i Amount'),
        TextCellValue('EMI $i Date'),
      ],
    ]);
    for (final c in customers) {
      sheet.appendRow([TextCellValue(c.mlid), TextCellValue(c.fullName)]);
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The template could not be generated.');
    return Uint8List.fromList(bytes);
  }

  /// Returns one schedule per MLID: an ordered list of (amount, date) pairs,
  /// skipping any of the 100 pairs left blank. A row with no filled pairs at
  /// all is dropped — an Owner who filled Step 2 for a customer with no
  /// history yet should not see that customer flagged as an error here.
  static List<EmiScheduleRow> parseEmiBytes(Uint8List bytes, String fileName) {
    final table = _decodeTable(bytes, fileName, preferredSheet: 'EMI History');
    if (table.isEmpty) return const [];
    final out = <EmiScheduleRow>[];
    for (final raw in table.skip(1)) {
      if (raw.length < 2 || raw.every((c) => c.trim().isEmpty)) continue;
      final mlid = raw[0].trim();
      if (mlid.isEmpty) continue;
      final entries = <EmiEntry>[];
      for (var i = 0; i < emiCount; i++) {
        final amountIdx = 2 + i * 2;
        final dateIdx = amountIdx + 1;
        if (amountIdx >= raw.length) break;
        final amountText = raw[amountIdx].trim();
        final dateText = dateIdx < raw.length ? raw[dateIdx].trim() : '';
        if (amountText.isEmpty || dateText.isEmpty) continue;
        final amount = int.tryParse(amountText);
        final date = DateTime.tryParse(dateText);
        if (amount == null || amount <= 0 || date == null) continue;
        entries.add(EmiEntry(amount: amount, date: date));
      }
      if (entries.isNotEmpty) out.add(EmiScheduleRow(mlid: mlid, entries: entries));
    }
    return out;
  }

  /// NOT all-or-nothing — unlike every other import in this wizard. Each
  /// instalment is its own `app.record_collection` call (there is no bulk
  /// RPC for historical collections), so a failure partway through leaves
  /// earlier instalments recorded. The caller renders per-row, per-instalment
  /// results so the Owner can see exactly which ones still need fixing and
  /// re-run just those, rather than assuming a clean sheet the way the other
  /// two steps can.
  Future<EmiSubmitResult> submitEmiSchedule({
    required String businessId,
    required List<EmiScheduleRow> schedule,
    required void Function(String mlid, int done, int total) onProgress,
  }) async {
    final mlids = schedule.map((s) => s.mlid).toList();
    final loanByMlid = await _resolveLoansByMlid(businessId, mlids);
    final collectionApi = _ref.read(collectionApiServiceProvider);

    var totalOk = 0;
    final errors = <EmiRowError>[];
    for (final row in schedule) {
      final loan = loanByMlid[row.mlid];
      if (loan == null) {
        errors.add(EmiRowError(mlid: row.mlid, instalment: 0, message: 'No migrated loan found for this MLID.'));
        continue;
      }
      for (var i = 0; i < row.entries.length; i++) {
        final e = row.entries[i];
        onProgress(row.mlid, i + 1, row.entries.length);
        try {
          final outcome = await collectionApi.recordCollection(
            loanId: loan.loanId,
            customerId: loan.customerId,
            collectedAmount: e.amount,
            payerType: 'Customer',
            paymentSplits: [PaymentSplit(paymentMode: 'Cash', amount: e.amount)],
            businessDate: e.date.toIso8601String().split('T').first,
            businessId: businessId,
            confirmDuplicate: true, // historical backfill: same-day repeats are expected, not a real duplicate
          );
          if (outcome.saved != null) {
            totalOk++;
          } else {
            errors.add(EmiRowError(mlid: row.mlid, instalment: i + 1, message: 'Could not be recorded.'));
          }
        } catch (e2) {
          errors.add(EmiRowError(mlid: row.mlid, instalment: i + 1, message: e2.toString()));
        }
      }
    }
    return EmiSubmitResult(recorded: totalOk, errors: errors);
  }

  /// Unlike Steps 1 and 2, `submitEmiSchedule` is NOT all-or-nothing —
  /// instalments that already recorded must not appear in the re-upload, or
  /// a second run would collect them twice. Only the failed pairs come
  /// back, repacked into sequential EMI slots starting at 1 (their original
  /// slot number carried no meaning — [EmiScheduleRow.entries] is already
  /// compacted past blanks during parse); a customer whose whole schedule
  /// succeeded is dropped from the file entirely.
  static Uint8List buildEmiCorrectionFile({
    required List<EmiScheduleRow> schedule,
    required List<EmiRowError> errors,
    required String language,
  }) {
    final wholeRowFailed = <String>{};
    final failedEntryIndexes = <String, Set<int>>{};
    for (final e in errors) {
      if (e.instalment == 0) {
        wholeRowFailed.add(e.mlid);
      } else {
        failedEntryIndexes.putIfAbsent(e.mlid, () => {}).add(e.instalment - 1);
      }
    }

    final excel = Excel.createExcel();
    final sheet = excel['EMI History'];
    sheet.appendRow([
      TextCellValue(_prefillLabels['mlid']![language] ?? 'MLID'),
      TextCellValue(_prefillLabels['full_name']![language] ?? 'Name'),
      for (var i = 1; i <= emiCount; i++) ...[
        TextCellValue('EMI $i Amount'),
        TextCellValue('EMI $i Date'),
      ],
    ]);
    for (final row in schedule) {
      final failedEntries = wholeRowFailed.contains(row.mlid)
          ? row.entries
          : [for (final idx in failedEntryIndexes[row.mlid] ?? const <int>{}) row.entries[idx]];
      if (failedEntries.isEmpty) continue;
      final cells = <CellValue>[TextCellValue(row.mlid), TextCellValue('')];
      for (final entry in failedEntries) {
        cells.add(TextCellValue(entry.amount.toString()));
        cells.add(TextCellValue(
            '${entry.date.year.toString().padLeft(4, '0')}-${entry.date.month.toString().padLeft(2, '0')}-${entry.date.day.toString().padLeft(2, '0')}'));
      }
      sheet.appendRow(cells);
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The corrected file could not be generated.');
    return Uint8List.fromList(bytes);
  }

  Future<Map<String, LoanRef>> _resolveLoansByMlid(String businessId, List<String> mlids) async {
    if (mlids.isEmpty) return {};
    final rows = await _db
        .from('loans')
        .select('loan_id, customer_id, issue_business_date, customers!inner(business_members!inner(business_id, persons!inner(mlid)))')
        .eq('customers.business_members.business_id', businessId)
        .order('issue_business_date', ascending: false);
    final map = <String, LoanRef>{};
    for (final r in rows as List) {
      final person = (((r['customers'] as Map<String, dynamic>)['business_members']) as Map<String, dynamic>)['persons']
          as Map<String, dynamic>;
      final mlid = person['mlid'] as String?;
      // First (most recent) loan wins — the migration wizard creates one
      // loan per customer, but this keeps a later re-run from crashing if a
      // customer somehow already had two.
      if (mlid != null && mlids.contains(mlid) && !map.containsKey(mlid)) {
        map[mlid] = LoanRef(loanId: r['loan_id'] as String, customerId: r['customer_id'] as String);
      }
    }
    return map;
  }

  Future<List<CustomerRef>> fetchCustomerRefs(String businessId) async {
    final rows = await _prefillRows(businessId, 'Customer');
    return [for (final r in rows) CustomerRef(mlid: r.mlid, fullName: r.fullName)];
  }

  // ---------------------------------------------------------------------
  // Shared plumbing
  // ---------------------------------------------------------------------

  Future<void> shareBytes(Uint8List bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, name: fileName)], subject: fileName),
    );
  }

  static List<List<String>> _decodeTable(Uint8List bytes, String fileName, {required String preferredSheet}) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.csv')) return _parseCsv(utf8.decode(bytes, allowMalformed: true));

    final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (e) {
      throw ImportFormatException('This file could not be read as a spreadsheet. '
          'If it came from another app, save it as .xlsx or .csv and try again. ($e)');
    }
    final sheet = book.tables[preferredSheet] ??
        book.tables.values.firstWhere(
          (t) => t.rows.isNotEmpty,
          orElse: () => throw const ImportFormatException('The workbook has no sheet with any rows in it.'),
        );
    return [
      for (final row in sheet.rows) [for (final cell in row) _cellText(cell?.value)],
    ];
  }

  static ParsedSheet _parseTable(
    List<List<String>> table,
    List<String> required,
    List<String> optional,
    Map<String, String> aliases, {
    List<String> prefillColumns = const [],
  }) {
    if (table.isEmpty) throw const ImportFormatException('The file has no rows.');
    final allKnown = {...prefillColumns, ...required, ...optional};
    final header = [for (final c in table.first) aliases[normalise(c)] ?? normalise(c)];
    final missing = [for (final c in required) if (!header.contains(c)) c];
    if (missing.isNotEmpty) {
      throw ImportFormatException(
        'These columns are missing: ${missing.join(", ")}. Use the template to be sure of the headings.',
      );
    }
    final rows = <Map<String, dynamic>>[];
    for (final raw in table.skip(1)) {
      if (raw.every((c) => c.trim().isEmpty)) continue;
      final row = <String, dynamic>{};
      for (var i = 0; i < header.length && i < raw.length; i++) {
        final key = header[i];
        if (!allKnown.contains(key)) continue;
        final v = raw[i].trim();
        if (v.isNotEmpty) row[key] = v;
      }
      rows.add(row);
    }
    return ParsedSheet(rows: rows, sheetColumns: header);
  }

  static String _cellText(CellValue? v) {
    if (v == null) return '';
    if (v is TextCellValue) return v.value.toString().trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    if (v is DateCellValue) {
      return '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    if (v is BoolCellValue) return v.value.toString();
    return v.toString().trim();
  }

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
            ImportRowError(row: ((e as Map)['row'] as num?)?.toInt() ?? 0, message: (e['error'] ?? '').toString()),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

// ============================================================================
// Types
// ============================================================================

class ParsedSheet {
  final List<Map<String, dynamic>> rows;
  final List<String> sheetColumns;
  const ParsedSheet({required this.rows, required this.sheetColumns});
}

class Step2Parse {
  final ParsedSheet agent;
  final ParsedSheet investor;
  final ParsedSheet customer;
  const Step2Parse({required this.agent, required this.investor, required this.customer});
}

class DuplicateMatch {
  final int row;
  final String reason; // 'existing_customer' | 'duplicate_in_file'
  final List<String> candidates;
  const DuplicateMatch({required this.row, required this.reason, this.candidates = const []});
}

class CreatedIdentity {
  final int row;
  final String userType;
  final String mlid;
  const CreatedIdentity({required this.row, required this.userType, required this.mlid});
}

class ImportRowError {
  final int row;
  final String message;
  const ImportRowError({required this.row, required this.message});
}

class ImportOutcome {
  final int imported;
  final List<ImportRowError> errors;
  final List<CreatedIdentity> created;
  const ImportOutcome({required this.imported, required this.errors, this.created = const []});
  bool get rejected => errors.isNotEmpty;
}

class ImportFormatException implements Exception {
  final String message;
  const ImportFormatException(this.message);
  @override
  String toString() => message;
}

class _PrefillRow {
  final String mlid;
  final String fullName;
  final String? village;
  const _PrefillRow({required this.mlid, required this.fullName, this.village});
}

class CustomerRef {
  final String mlid;
  final String fullName;
  const CustomerRef({required this.mlid, required this.fullName});
}

class LoanRef {
  final String loanId;
  final String customerId;
  const LoanRef({required this.loanId, required this.customerId});
}

class EmiEntry {
  final int amount;
  final DateTime date;
  const EmiEntry({required this.amount, required this.date});
}

class EmiScheduleRow {
  final String mlid;
  final List<EmiEntry> entries;
  const EmiScheduleRow({required this.mlid, required this.entries});
}

class EmiRowError {
  final String mlid;
  final int instalment; // 0 = the whole row (e.g. no loan found)
  final String message;
  const EmiRowError({required this.mlid, required this.instalment, required this.message});
}

class EmiSubmitResult {
  final int recorded;
  final List<EmiRowError> errors;
  const EmiSubmitResult({required this.recorded, required this.errors});
}

final bulkOnboardingServiceProvider = Provider<BulkOnboardingService>(
  (ref) => BulkOnboardingService(Supabase.instance.client, ref),
);
