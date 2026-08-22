import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/xlsx_fallback_reader.dart';
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
    // ONE name field, not two. The Owner's book writes the surname first and
    // the given name after it, in one string, and asking them to split it is
    // asking them to re-key 63 rows. persons carries surname/given_name
    // separately, but trg_sync_person_name derives both from full_name on
    // write, so a single column is the whole story here.
    'full_name': {
      'English': 'Name (Surname + Name)*', 'Telugu': 'పేరు (ఇంటిపేరు + పేరు)*',
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
    'village': {
      'English': 'Village*', 'Telugu': 'గ్రామం*',
    },
  };

  static const identityRequired = [
    'gender_digit', 'full_name', 'father_husband_name', 'user_type', 'pin_code', 'village',
  ];
  static const identityOptional = ['aadhaar_number', 'mobile_number', 'door_no'];
  static const identityColumns = [
    'aadhaar_number', 'gender_digit', 'full_name', 'father_husband_name',
    'user_type', 'mobile_number', 'door_no', 'pin_code', 'village',
  ];

  /// M/F/O as the Owner types it -> the MLID gender digit the database stores
  /// (1 Male, 0 Female, 2 Others). Without this the sheet's own heading —
  /// "Gender (M/F/O)" — produced a value the gender CHECK rejects, so every
  /// row failed on a column the template told them to fill that way.
  static const _genderDigits = <String, String>{
    'm': '1', 'male': '1', 'పురుషుడు': '1', '1': '1',
    'f': '0', 'female': '0', 'స్త్రీ': '0', '0': '0',
    'o': '2', 'other': '2', 'others': '2', 'ఇతరులు': '2', '2': '2',
  };

  static String? genderDigit(String raw) => _genderDigits[raw.trim().toLowerCase()];

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
      'Gender, Name, C/O Name, User Type, Pin Code and Village are required.',
      'Write the name the way your book does: surname first, then the name,',
      'in the one Name column.',
      'User Type must be exactly Agent, Customer or Investor.',
      'Gender is M, F or O.',
      'Phone and Aadhaar are both optional for a pre-existing book — a person',
      'may have neither. You can complete them later from Global Workflow.',
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
    final parsed = _parseTable(table, identityRequired, identityOptional, _aliasMap(_identityLabels));
    for (final row in parsed.rows) {
      final raw = row['gender_digit'];
      if (raw is String) {
        // An unrecognised value is passed through untouched so the server is
        // still the one that rejects it, with its own wording.
        row['gender_digit'] = genderDigit(raw) ?? raw;
      }
    }
    return parsed;
  }

  /// The distinct (PIN, Village) pairs an identity sheet names, in the order
  /// they first appear. This is what the Areas & Villages step works from —
  /// there is no villages sheet, because India has ~664,000 villages and a
  /// business operates in a dozen.
  static List<VillageRef> villagePairs(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    final out = <VillageRef>[];
    for (final r in rows) {
      final pin = (r['pin_code'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final village = (r['village'] ?? '').toString().trim();
      if (pin.isEmpty || village.isEmpty) continue;
      final key = '$pin|${village.toLowerCase()}';
      if (seen.add(key)) out.add(VillageRef(pinCode: pin, village: village));
    }
    return out;
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

  Future<List<ManaMemberRef>> _prefillRows(String businessId, String role) async {
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
    // Growable, not const: every caller sorts this, and sorting a const list
    // throws.
    if (personIds.isEmpty) return <ManaMemberRef>[];

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
          ManaMemberRef(
            mlid: (m['persons'] as Map<String, dynamic>)['mlid'] as String? ?? '',
            fullName: (m['persons'] as Map<String, dynamic>)['full_name'] as String? ?? '',
            village: villageByPerson[(m['person_id'] as num).toInt()],
          ),
    ];
  }

  /// Everyone on the books in a role, for a picker to search.
  ///
  /// The spreadsheet paths below still exist for a business with more
  /// investors than a person wants to tap in one at a time; the wizard no
  /// longer uses them.
  Future<List<ManaMemberRef>> membersInRole({
    required String businessId,
    required String role,
  }) =>
      _prefillRows(businessId, role);

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
      return ImportOutcome(
        imported: (map['imported'] as num?)?.toInt() ?? 0,
        skipped: (map['skipped'] as num?)?.toInt() ?? 0,
        errors: const [],
      );
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
  /// `emiTotals` is what the instalment history on the same sheet adds up to,
  /// per MLID. When a loan has history, the server opens it UNPAID and lets the
  /// replayed instalments derive the balance; a typed balance is then checked
  /// against that and disagreement rejects the row. Sending the typed balance
  /// alone, with history replayed on top, is what used to land the loan at
  /// typed - SUM(history).
  Future<ImportOutcome> submitCustomerLoans({
    required String businessId,
    required List<Map<String, dynamic>> rows,
    Map<String, int> emiTotals = const {},
    /// Mint once when the Owner taps Import and reuse it for every retry —
    /// see lib/shared/idempotency.dart. Without it, a retry after a timeout
    /// puts the whole book in a second time; that is exactly what happened on
    /// 22 Aug 2026 (108 loans, line balance nearly double).
    String? idempotencyKey,
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
      final emiTotal = emiTotals[mlid];
      if (emiTotal != null && emiTotal > 0) row['emi_total'] = emiTotal;
      payload.add(row);
      // ignore: unused_local_variable
      loanEndDate;
    }

    try {
      final res = await _db.schema('app').rpc('import_migrated_loans', params: {
        'p_business_id': businessId,
        'p_rows': payload,
        'p_idempotency_key': idempotencyKey,
      });
      final map = Map<String, dynamic>.from(res as Map);
      return ImportOutcome(
        imported: (map['imported'] as num?)?.toInt() ?? 0,
        skipped: (map['skipped'] as num?)?.toInt() ?? 0,
        errors: const [],
      );
    } on PostgrestException catch (e) {
      final parsed = _rejectionFrom(e.message);
      if (parsed == null) rethrow;
      return parsed;
    }
  }

  /// MLID -> customer_id, scoped to this business. The Owner never sees a
  /// UUID: every sheet is keyed by MLID, and the translation happens here.
  Future<Map<String, String>> _resolveCustomerIdsByMlid(String businessId, List<String> mlids) async {
    if (mlids.isEmpty) return {};
    final rows = await _db
        .from('customers')
        .select('customer_id, business_members!inner(business_id, persons!business_members_person_id_fkey!inner(mlid))')
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
  // EMI history — the instalment pairs the customer grids carry
  // ---------------------------------------------------------------------

  static const emiCount = 100;

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

    // What is ALREADY recorded, so a resumed run does not collect it twice.
    //
    // This replay is not one request — it is one record_collection per
    // instalment, hundreds of them, and any of the things that stop a phone
    // mid-round will stop it partway. On 22 Aug 2026 it stopped after 204 of
    // them, and the only way forward was a correction file built from an error
    // list that had died with the screen. Re-uploading the sheet would have
    // collected those 204 a second time.
    //
    // So the sheet is treated as the TARGET STATE rather than a list of
    // actions: for each (loan, date, amount) it asks for N instalments, the
    // loan already has M, and only max(0, N - M) are recorded. Multiplicity is
    // counted rather than a set membership test, because a customer really can
    // pay the same amount twice on one day and the second one is not a repeat.
    final already = await _recordedInstalments(
        [for (final l in loanByMlid.values) l.loanId]);

    var totalOk = 0;
    var skipped = 0;
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

        if (consumeRecorded(already, instalmentKey(loan.loanId, e))) {
          skipped++;
          continue;
        }

        // A payment dated before the loan existed. The server refuses it and
        // is right to — but it answers with neither date, which leaves the
        // Owner a row number and nothing to correct. Either the issue date on
        // the loan sheet is wrong or that instalment belongs to an earlier
        // loan, and only they can say which. Never re-dated to fit: that
        // would move money between two of their own books.
        final issued = loan.effectiveDate;
        if (issued != null && e.date.isBefore(issued)) {
          errors.add(EmiRowError(
            mlid: row.mlid,
            instalment: i + 1,
            message: 'Paid on ${_isoDate(e.date)} but the loan was issued on '
                '${_isoDate(issued)}. Correct whichever date is wrong.',
          ));
          continue;
        }

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
            // A payment bigger than the loan's own EMI is an Excess to
            // record_collection, and it refuses one that does not say where
            // the extra went. On a live screen that question is right — the
            // Agent is holding the money. Replaying an old book it is not:
            // the payment happened, the extra went against the instalments
            // that came after, and the closing balance the Owner is
            // reconciling to already reflects it. 46 rows of this business's
            // history are somebody paying two weeks at once.
            //
            // Only set when the row really is over the EMI: the RPC stores
            // the disposition whatever the result type, and stamping
            // "Next Installment" on ordinary payments would be a lie in the
            // record.
            excessDisposition: migrationExcessDisposition(
                e.amount, loan.installmentAmount),
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
    return EmiSubmitResult(recorded: totalOk, errors: errors, skipped: skipped);
  }

  /// loan + date + amount -> how many such collections the loan already has.
  ///
  /// Soft-deleted rows are excluded: a collection that was reversed has to be
  /// replayable, or a repaired import could never be completed.
  Future<Map<String, int>> _recordedInstalments(List<String> loanIds) async {
    if (loanIds.isEmpty) return {};
    final rows = await _db
        .from('collections')
        .select('loan_id, business_date, collected_amount')
        .inFilter('loan_id', loanIds)
        .isFilter('deleted_at', null);
    final counts = <String, int>{};
    for (final r in rows as List) {
      final key = '${r['loan_id']}|${r['business_date']}|'
          '${(r['collected_amount'] as num).toInt()}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// A whole-rupee amount out of a spreadsheet cell, or null if the cell is
  /// not one.
  ///
  /// The app writes these templates with text cells, so "600" comes back
  /// exactly as typed. The moment an Owner opens the file in Excel and saves,
  /// the same cell is a number and reads back "600.0" — and int.tryParse says
  /// null. That is how all 250 instalments in the sri satyanarayana sheet
  /// vanished on 22 Aug 2026 while the loans beside them imported fine: the
  /// loan columns are handed to Postgres as text and cast there, the EMI
  /// columns were parsed in Dart.
  ///
  /// Commas and a rupee sign are tolerated for the same reason. A genuinely
  /// fractional amount is NOT rounded away — money columns are numeric(_,0),
  /// paise cannot be stored, and quietly turning 600.50 into 600 or 601 would
  /// put a number in the book that nobody typed.
  static int? parseWholeRupees(String cell) {
    final cleaned = cell.replaceAll(RegExp(r'[₹,\s]'), '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0) return null;
    if (value != value.roundToDouble()) return null;
    return value.toInt();
  }

  /// Where the extra on a replayed instalment went, or null when the payment
  /// is not over the loan's EMI and there is no extra. See the call site.
  static String? migrationExcessDisposition(int amount, int installment) =>
      amount > installment ? 'Next Installment' : null;

  static String instalmentKey(String loanId, EmiEntry e) =>
      '$loanId|${_isoDate(e.date)}|${e.amount}';

  /// True if this instalment is already on the loan, consuming one of the
  /// recorded copies so a sheet asking for two only skips two.
  static bool consumeRecorded(Map<String, int> recorded, String key) {
    final left = recorded[key] ?? 0;
    if (left <= 0) return false;
    recorded[key] = left - 1;
    return true;
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
        .select('loan_id, customer_id, installment_amount, effective_date, issue_business_date, customers!inner(business_members!inner(business_id, persons!business_members_person_id_fkey!inner(mlid)))')
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
        map[mlid] = LoanRef(
          loanId: r['loan_id'] as String,
          customerId: r['customer_id'] as String,
          installmentAmount: (r['installment_amount'] as num?)?.toInt() ?? 0,
          effectiveDate: DateTime.tryParse(r['effective_date'] as String? ?? ''),
        );
      }
    }
    return map;
  }

  // ---------------------------------------------------------------------
  // Where the wizard had got to
  //
  // Server-side so it follows the Owner: migrating a book is eight pages and
  // several file uploads, which is neither one sitting nor reliably one
  // handset. A local key meant a reinstall or the other phone started page 1
  // again on a half-migrated book.
  // ---------------------------------------------------------------------

  Future<int?> wizardStep(String businessId) async {
    final res = await _db
        .schema('app')
        .rpc('migration_wizard_step', params: {'p_business_id': businessId});
    return (res as num?)?.toInt();
  }

  /// What is already in this business, counted from the live rows.
  ///
  /// Every page of the wizard shows this: without it, going back a page — or
  /// resuming tomorrow — shows a page that looks untouched whether it holds
  /// 55 customers or none, and the only way to find out is to import again.
  Future<MigrationProgress> migrationProgress(String businessId) async {
    final res = await _db
        .schema('app')
        .rpc('migration_progress', params: {'p_business_id': businessId});
    return MigrationProgress(Map<String, dynamic>.from(res as Map));
  }

  Future<void> saveWizardStep(String businessId, int step) async {
    await _db.schema('app').rpc('set_migration_wizard_step', params: {
      'p_business_id': businessId,
      'p_step': step,
    });
  }

  // ---------------------------------------------------------------------
  // Areas & Villages
  //
  // There is no villages sheet. The wizard takes the distinct (PIN, Village)
  // pairs out of the identity sheet, offers what the LGD reference knows about
  // that PIN, and asks the Owner to confirm. It suggests; it never validates —
  // 8.1% of PINs list two districts after the post-2022 splits, and both the
  // version columns and the heuristics were proven wrong, so the Owner answers
  // once per PIN.
  // ---------------------------------------------------------------------

  Future<List<VillageSuggestion>> suggestVillages(String pinCode) async {
    final res = await _db.schema('app').rpc('suggest_villages', params: {'p_pincode': pinCode});
    return [
      for (final r in (res as List? ?? const []).cast<Map<String, dynamic>>())
        VillageSuggestion(
          village: (r['village'] ?? '').toString(),
          mandal: (r['mandal'] ?? '').toString(),
          district: (r['district'] ?? '').toString(),
          state: (r['state'] ?? '').toString(),
        ),
    ];
  }

  Future<void> upsertVillages({
    required String businessId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _db.schema('app').rpc('migration_upsert_villages', params: {
      'p_business_id': businessId,
      'p_rows': rows,
    });
  }

  Future<Map<String, dynamic>> createAreas({
    required String businessId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final res = await _db.schema('app').rpc('migration_create_areas', params: {
      'p_business_id': businessId,
      'p_rows': rows,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// "517644|srikalahasti" -> the round that already walks it.
  ///
  /// A village belongs to exactly one area per business (unique index
  /// uq_oal_business_location), so an Owner who set their areas up before
  /// running the wizard must see those names here rather than a default that
  /// would silently propose moving every village into one round.
  Future<Map<String, String>> existingVillageAreas(String businessId) async {
    final rows = await _db
        .from('operating_area_locations')
        .select('locations!inner(village_town_name, pin_code), operating_areas!inner(name)')
        .eq('business_id', businessId)
        .isFilter('removed_at', null);

    final out = <String, String>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final loc = r['locations'] as Map<String, dynamic>?;
      final area = r['operating_areas'] as Map<String, dynamic>?;
      if (loc == null || area == null) continue;
      final pin = (loc['pin_code'] ?? '').toString();
      final village = (loc['village_town_name'] ?? '').toString().toLowerCase();
      out['$pin|$village'] = (area['name'] ?? '').toString();
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Investors
  // ---------------------------------------------------------------------

  Future<Uint8List> buildInvestorTemplate({required String businessId, required String language}) =>
      _buildRolePrefillTemplate(
        businessId: businessId,
        language: language,
        role: 'Investor',
        extraKeys: investorRequired,
        extraLabels: _investorLabels,
        notes: const [
          'One row per investor, including the Owner: owner capital is equity,',
          'and it is entered here as an investment first.',
          'ROI is Rupees per 100 per MONTH, not per year.',
          'Profit % is the share of profit this investor is owed. It accrues at',
          'the investment ROI until it is paid, and is 0 if it is paid the same',
          'day it is declared.',
        ],
      );

  /// The money that came back OUT, before the app existed.
  ///
  /// A separate sheet rather than more columns on the investor template,
  /// because an investor can withdraw more than once and a row-per-investor
  /// grid cannot hold that.
  Future<Uint8List> buildWithdrawalTemplate({
    required String businessId,
    required String language,
  }) async {
    final rows = await _prefillRows(businessId, 'Investor');
    final excel = Excel.createExcel();
    final sheet = excel['Withdrawals'];
    sheet.appendRow([
      TextCellValue(_prefillLabels['mlid']![language] ?? 'MLID'),
      TextCellValue(_prefillLabels['full_name']![language] ?? 'Name'),
      TextCellValue('Date* (yyyy-mm-dd)'),
      TextCellValue('Amount Taken Out*'),
      TextCellValue('Of Which Interest'),
      TextCellValue('Invested Date (only if they hold more than one)'),
    ]);
    for (final r in rows) {
      sheet.appendRow([TextCellValue(r.mlid), TextCellValue(r.fullName)]);
    }

    final notes = excel['Notes'];
    for (final line in const [
      'One row per withdrawal, not per investor — copy an investor down as many',
      'times as they took money out.',
      '',
      'Amount Taken Out is the CASH that left the box. If some of that cash was',
      'interest rather than capital, say how much in the next column; otherwise',
      'leave it blank.',
      '',
      'Interest that was settled against what the investor had accrued, without',
      'cash leaving, does NOT belong here — it goes in the weekly account',
      'sheet, on the Investor Out - Interest column.',
      '',
      'Invested Date is only needed when one investor holds more than one',
      'investment, so the row can say which one the money came off.',
    ]) {
      notes.appendRow([TextCellValue(line)]);
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The template could not be generated.');
    return Uint8List.fromList(bytes);
  }

  static List<Map<String, dynamic>> parseWithdrawalBytes(
      Uint8List bytes, String fileName) {
    final table = _decodeTable(bytes, fileName, preferredSheet: 'Withdrawals');
    if (table.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    for (final raw in table.skip(1)) {
      if (raw.every((c) => c.trim().isEmpty)) continue;
      if (raw.length < 4) continue;
      final mlid = raw[0].trim();
      final date = raw[2].trim();
      // Whole rupees however the spreadsheet chose to write them — a file that
      // has been through Excel says "400000.0". See parseWholeRupees.
      final amount = parseWholeRupees(raw[3]);
      if (mlid.isEmpty || date.isEmpty || amount == null) continue;
      final interest = raw.length > 4 ? parseWholeRupees(raw[4]) : null;
      final invested = raw.length > 5 ? raw[5].trim() : '';
      out.add({
        'mlid': mlid,
        'business_date': date,
        'amount': amount,
        if (interest != null) 'interest_portion': interest,
        if (invested.isNotEmpty) 'invested_date': invested,
      });
    }
    return out;
  }

  Future<ImportOutcome> submitWithdrawals({
    required String businessId,
    required List<Map<String, dynamic>> rows,
    String? idempotencyKey,
  }) async {
    try {
      final res = await _db.schema('app').rpc('import_migrated_withdrawals', params: {
        'p_business_id': businessId,
        'p_rows': rows,
        'p_idempotency_key': idempotencyKey,
      });
      final map = Map<String, dynamic>.from(res as Map);
      return ImportOutcome(
        imported: (map['imported'] as num?)?.toInt() ?? 0,
        skipped: (map['skipped'] as num?)?.toInt() ?? 0,
        errors: const [],
      );
    } on PostgrestException catch (e) {
      final parsed = _rejectionFrom(e.message);
      if (parsed == null) rethrow;
      return parsed;
    }
  }

  static ParsedSheet parseInvestorBytes(Uint8List bytes, String fileName) {
    final table = _decodeTable(bytes, fileName, preferredSheet: 'Investor');
    return _parseTable(
      table,
      investorRequired,
      const [],
      {..._aliasMap(_prefillLabels), ..._aliasMap(_investorLabels)},
      prefillColumns: const ['mlid', 'full_name', 'user_type', 'village'],
    );
  }

  // ---------------------------------------------------------------------
  // Customers — one grid per repayment frequency
  //
  // Three sheets, because a Daily book and a Monthly book are different
  // shapes on paper and mixing them in one grid is where an Owner
  // mis-keys a frequency. The frequency is the SHEET, never a column, so it
  // cannot be typed wrong. Each row carries its own EMI history as
  // amount+date pairs, which is what a paper ledger's date columns are.
  // ---------------------------------------------------------------------

  static const customerFrequencies = ['Daily', 'Weekly', 'Monthly'];

  Future<Uint8List> buildCustomerGridTemplate({
    required String businessId,
    required String language,
  }) async {
    final rows = await _prefillRows(businessId, 'Customer');
    rows.sort((a, b) {
      final va = (a.village ?? '').trim();
      final vb = (b.village ?? '').trim();
      if (va.isEmpty != vb.isEmpty) return va.isEmpty ? 1 : -1;
      final cmp = va.toLowerCase().compareTo(vb.toLowerCase());
      return cmp != 0 ? cmp : a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });

    final excel = Excel.createExcel();
    final loanKeys = [
      for (final k in [...customerLoanRequired, ...customerLoanOptional])
        if (k != 'repayment_type') k,
    ];

    for (final frequency in customerFrequencies) {
      final sheet = excel[frequency];
      sheet.appendRow([
        for (final k in const ['mlid', 'full_name', 'village'])
          TextCellValue(_prefillLabels[k]![language] ?? _prefillLabels[k]!['English']!),
        for (final k in loanKeys)
          TextCellValue(_customerLoanLabels[k]![language] ?? _customerLoanLabels[k]!['English']!),
        for (var i = 1; i <= emiCount; i++) ...[
          TextCellValue('EMI $i Amount'),
          TextCellValue('EMI $i Date'),
        ],
      ]);
      for (final r in rows) {
        sheet.appendRow([
          TextCellValue(r.mlid),
          TextCellValue(r.fullName),
          TextCellValue(r.village ?? ''),
        ]);
      }
    }

    final notes = excel['Notes'];
    for (final line in const [
      'One sheet per repayment frequency — put each loan on the sheet that',
      'matches how it is collected. The sheet IS the frequency; there is no',
      'frequency column to get wrong.',
      'Delete the rows of any customer who has no loan on that sheet.',
      'Issued Date is required. Remaining Balance is what is still owed on the',
      'cut-off date; if you fill in the EMI columns it is checked against them.',
      'The EMI columns are the instalment history: every instalment ever paid,',
      'one amount and one date per pair. Leave them blank if you are only',
      'entering the balance.',
      'Rupees only — paise cannot be stored.',
    ]) {
      notes.appendRow([TextCellValue(line)]);
    }

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The template could not be generated.');
    return Uint8List.fromList(bytes);
  }

  /// Loan rows (with `repayment_type` filled in from the sheet name) plus the
  /// EMI schedule those same rows carry. A sheet with no data rows is not an
  /// error: a business may run Daily loans only.
  static CustomerGridParse parseCustomerGridBytes(Uint8List bytes, String fileName) {
    final book = _decodeSheets(bytes, fileName);

    final aliases = {..._aliasMap(_prefillLabels), ..._aliasMap(_customerLoanLabels)};
    final required = [for (final k in customerLoanRequired) if (k != 'repayment_type') k];
    final loans = <Map<String, dynamic>>[];
    final schedule = <EmiScheduleRow>[];
    var unreadable = 0;

    for (final frequency in customerFrequencies) {
      final grid = book[frequency];
      if (grid == null || grid.isEmpty) continue;
      final parsed = _parseTable(
        grid,
        required,
        customerLoanOptional,
        aliases,
        prefillColumns: const ['mlid', 'full_name', 'user_type', 'village'],
      );
      for (final row in parsed.rows) {
        row['repayment_type'] = frequency;
        loans.add(row);
      }

      // The EMI pairs sit past the named columns, so they are read positionally
      // from the raw grid rather than through the header map.
      final header = grid.first;
      final firstEmiColumn = header.indexWhere((c) => normalise(c).startsWith('emi_1'));
      if (firstEmiColumn < 0) continue;

      var dataRow = 0;
      for (final raw in grid.skip(1)) {
        if (raw.every((c) => c.trim().isEmpty)) continue;
        final row = parsed.rows.length > dataRow ? parsed.rows[dataRow] : null;
        dataRow++;
        final mlid = (row?['mlid'] ?? '').toString().trim();
        if (mlid.isEmpty) continue;

        final entries = <EmiEntry>[];
        for (var i = 0; i < emiCount; i++) {
          final amountIdx = firstEmiColumn + i * 2;
          final dateIdx = amountIdx + 1;
          if (amountIdx >= raw.length) break;
          final amountText = raw[amountIdx].trim();
          final dateText = dateIdx < raw.length ? raw[dateIdx].trim() : '';
          if (amountText.isEmpty && dateText.isEmpty) continue;
          final amount = parseWholeRupees(amountText);
          final date = DateTime.tryParse(dateText);
          if (amount == null || date == null) {
            // Half a pair, or something neither a rupee amount nor a date.
            // Counted, never dropped in silence: 250 instalments went missing
            // this way on 22 Aug 2026 and the only trace was the readiness
            // line saying 0.
            unreadable++;
            continue;
          }
          entries.add(EmiEntry(amount: amount, date: date));
        }
        if (entries.isNotEmpty) schedule.add(EmiScheduleRow(mlid: mlid, entries: entries));
      }
    }

    return CustomerGridParse(
        loans: loans, schedule: schedule, unreadableInstalments: unreadable);
  }

  // ---------------------------------------------------------------------
  // Agents — attendance only
  // ---------------------------------------------------------------------

  Future<Uint8List> buildAttendanceTemplate({
    required String businessId,
    required String language,
  }) async {
    final rows = await _prefillRows(businessId, 'Agent');
    final excel = Excel.createExcel();
    final sheet = excel['Attendance'];
    sheet.appendRow([
      TextCellValue(_prefillLabels['mlid']![language] ?? 'MLID'),
      TextCellValue(_prefillLabels['full_name']![language] ?? 'Name'),
      TextCellValue('Date (yyyy-mm-dd)'),
      TextCellValue('Allowance'),
    ]);
    for (final r in rows) {
      sheet.appendRow([TextCellValue(r.mlid), TextCellValue(r.fullName)]);
    }

    final notes = excel['Notes'];
    for (final line in const [
      'One row per agent per working day. Copy an agent down as many rows as',
      'they worked days.',
      'Salary and expenses are NOT entered here — they are declared in the',
      'weekly account sheet, which is where your book records them.',
    ]) {
      notes.appendRow([TextCellValue(line)]);
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The template could not be generated.');
    return Uint8List.fromList(bytes);
  }

  static List<Map<String, dynamic>> parseAttendanceBytes(Uint8List bytes, String fileName) {
    final table = _decodeTable(bytes, fileName, preferredSheet: 'Attendance');
    if (table.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    for (final raw in table.skip(1)) {
      if (raw.every((c) => c.trim().isEmpty)) continue;
      if (raw.length < 3) continue;
      final mlid = raw[0].trim();
      final date = raw[2].trim();
      if (mlid.isEmpty || date.isEmpty) continue;
      out.add({
        'mlid': mlid,
        'business_date': date,
        if (raw.length > 3 && raw[3].trim().isNotEmpty) 'allowance_amount': raw[3].trim(),
      });
    }
    return out;
  }

  Future<AttendanceResult> recordAttendance({
    required String businessId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final res = await _db.schema('app').rpc('migration_record_attendance', params: {
      'p_business_id': businessId,
      'p_rows': rows,
    });
    final map = res as Map;
    final recorded = (map['recorded'] as num?)?.toInt() ?? 0;
    final total = (map['total'] as num?)?.toInt() ?? recorded;
    // The RPC skips a day the agent already has, so a re-upload is safe. It
    // has always returned `total` beside `recorded`; only `recorded` was read,
    // which is how a second upload came to report a bare "0 days recorded".
    return AttendanceResult(recorded: recorded, alreadyIn: total - recorded);
  }

  // ---------------------------------------------------------------------
  // Opening snapshot & reconciliation
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> profitSummary({
    required String businessId,
    DateTime? asOf,
  }) async {
    final res = await _db.schema('app').rpc('migration_profit_summary', params: {
      'p_business_id': businessId,
      if (asOf != null) 'p_as_of': _isoDate(asOf),
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> recordOpeningSnapshot({
    required String businessId,
    required DateTime cutoffDate,
    required int openingBf,
    required int declaredLineBalance,
    required int declaredProfit,
  }) async {
    final res = await _db.schema('app').rpc('record_opening_snapshot', params: {
      'p_business_id': businessId,
      'p_cutoff_date': _isoDate(cutoffDate),
      'p_opening_bf': openingBf,
      'p_declared_line_balance': declaredLineBalance,
      'p_declared_profit': declaredProfit,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  // ---------------------------------------------------------------------
  // Weekly account sheet — the source of truth for a migrated period
  //
  // Two sheets, because a week has one line of totals and any number of expense
  // lines under it. The server checks the week identity and the opening/closing
  // chain and refuses the whole file if either breaks, so nothing is validated
  // twice here.
  // ---------------------------------------------------------------------

  static const weekColumns = <String>[
    'account_date', 'opening_bf', 'collection', 'interest', 'fee',
    'investor_in', 'investor_in_interest', 'loans_gross_out',
    'investor_out', 'investor_out_interest', 'cheeti', 'expenses_total', 'closing_bf',
  ];

  static const _weekHeadings = <String>[
    'Date* (yyyy-mm-dd)', 'Opening BF*', 'Collection (vasool)', 'Interest (vaddi)',
    'Processing Fee (agreement)', 'Investor In', 'Investor In - Interest',
    'Loans Out (gross repayment)', 'Investor Out', 'Investor Out - Interest',
    'Cheeti', 'Expenses Total', 'Closing BF*',
  ];

  Uint8List buildWeeklyTemplate({required String language}) {
    final excel = Excel.createExcel();
    final weeks = excel['Weeks'];
    weeks.appendRow([for (final h in _weekHeadings) TextCellValue(h)]);

    final expenses = excel['Expenses'];
    expenses.appendRow([
      TextCellValue('Date* (yyyy-mm-dd)'),
      TextCellValue('What it was*'),
      TextCellValue('Amount*'),
    ]);

    final notes = excel['Notes'];
    for (final line in const [
      'One row per account in the Weeks sheet — the date is the day you closed',
      'the account, which is the last working day of that schedule.',
      '',
      'Every expense line goes on the Expenses sheet against the same date.',
      'Expenses Total is optional; fill it and it will be checked against the',
      'lines you entered.',
      '',
      'Loans Out is the GROSS repayment written out, not the cash handed over —',
      'the withheld interest and fee come back in on the Interest and Fee',
      'columns, the way your book already does it.',
      '',
      'Each week must balance:',
      '  opening + collection + interest + fee + investor in',
      '    - loans - expenses - investor out - cheeti = closing',
      'and one week closing must equal the next week opening. If either does',
      'not hold, nothing is imported and you are told which week.',
    ]) {
      notes.appendRow([TextCellValue(line)]);
    }

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The template could not be generated.');
    return Uint8List.fromList(bytes);
  }

  /// One map per week, with its expense lines nested. A blank numeric cell is
  /// left out rather than sent as 0 — the server treats absent and zero the
  /// same, and this way a skipped column never looks like a declared nothing.
  static List<Map<String, dynamic>> parseWeeklyBytes(Uint8List bytes, String fileName) {
    final book = _decodeSheets(bytes, fileName);

    final weekTable = book['Weeks'];
    if (weekTable == null || weekTable.length < 2) {
      throw const ImportFormatException(
          'The workbook has no Weeks sheet with any rows in it.');
    }

    final expensesByDate = <String, List<Map<String, dynamic>>>{};
    final expenseTable = book['Expenses'];
    if (expenseTable != null) {
      for (final cells in expenseTable.skip(1)) {
        if (cells.every((c) => c.trim().isEmpty)) continue;
        String at(int i) => i < cells.length ? cells[i].trim() : '';
        final date = at(0);
        final amount = at(2);
        if (date.isEmpty || amount.isEmpty) continue;
        expensesByDate.putIfAbsent(date, () => []).add({
          'label': at(1),
          'amount': amount,
        });
      }
    }

    final out = <Map<String, dynamic>>[];
    for (final cells in weekTable.skip(1)) {
      if (cells.every((c) => c.trim().isEmpty)) continue;
      String at(int i) => i < cells.length ? cells[i].trim() : '';
      final date = at(0);
      if (date.isEmpty) continue;

      final week = <String, dynamic>{'account_date': date};
      for (var i = 1; i < weekColumns.length; i++) {
        final v = at(i);
        if (v.isNotEmpty) week[weekColumns[i]] = v;
      }
      week['expenses'] = expensesByDate[date] ?? const <Map<String, dynamic>>[];
      out.add(week);
    }
    return out;
  }

  /// Returns the server's summary — how many weeks landed, and the opening and
  /// closing BF of the imported span.
  Future<Map<String, dynamic>> importWeeklyAccount({
    required String businessId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final res = await _db.schema('app').rpc('import_weekly_account', params: {
      'p_business_id': businessId,
      'p_rows': rows,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  // ---------------------------------------------------------------------
  // Shareholders
  //
  // Deliberately not the investor list: in the real book 2 of the 5 profit
  // shareholders hold no investment at all.
  // ---------------------------------------------------------------------

  static const shareholderColumns = <String>[
    'full_name', 'share_percent', 'share_amount', 'roi_rate', 'paid_on', 'amount_received',
  ];

  Uint8List buildShareholderTemplate({required String language}) {
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
    final notes = excel['Notes'];
    for (final line in const [
      'Who shares in the profit. This is not the investor list — a shareholder',
      'may hold no investment at all, and an investor may take no share.',
      '',
      'Share Amount is worked out from Share % and the profit you declare on',
      'the page; fill it only to override.',
      'A share accrues at its ROI from the day you declare it until the day it',
      'is paid, and is nothing at all if both fall on the same day.',
    ]) {
      notes.appendRow([TextCellValue(line)]);
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The template could not be generated.');
    return Uint8List.fromList(bytes);
  }

  static List<Map<String, dynamic>> parseShareholderBytes(Uint8List bytes, String fileName) {
    final table = _decodeTable(bytes, fileName, preferredSheet: 'Shareholders');
    if (table.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    for (final raw in table.skip(1)) {
      if (raw.every((c) => c.trim().isEmpty)) continue;
      String at(int i) => i < raw.length ? raw[i].trim() : '';
      if (at(0).isEmpty) continue;
      final row = <String, dynamic>{'full_name': at(0)};
      for (var i = 1; i < shareholderColumns.length; i++) {
        final v = at(i);
        if (v.isNotEmpty) row[shareholderColumns[i]] = v;
      }
      out.add(row);
    }
    return out;
  }

  Future<Map<String, dynamic>> importShareholders({
    required String businessId,
    required DateTime declaredOn,
    required int declaredProfit,
    required List<Map<String, dynamic>> rows,
  }) async {
    final res = await _db.schema('app').rpc('import_shareholders', params: {
      'p_business_id': businessId,
      'p_declared_on': _isoDate(declaredOn),
      'p_declared_profit': declaredProfit,
      'p_rows': rows,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  // ---------------------------------------------------------------------
  // Shared plumbing
  // ---------------------------------------------------------------------

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// One sheet of the people already in a role, prefilled, plus that role's own
  /// columns. Live-queried rather than trusted from an earlier step, so the
  /// file always reflects what is actually in the database.
  Future<Uint8List> _buildRolePrefillTemplate({
    required String businessId,
    required String language,
    required String role,
    required List<String> extraKeys,
    required Map<String, Map<String, String>> extraLabels,
    List<String> notes = const [],
  }) async {
    final rows = await _prefillRows(businessId, role);
    final excel = Excel.createExcel();
    final sheet = excel[role];
    sheet.appendRow([
      for (final k in const ['mlid', 'full_name', 'user_type', 'village'])
        TextCellValue(_prefillLabels[k]![language] ?? _prefillLabels[k]!['English']!),
      for (final k in extraKeys)
        TextCellValue(extraLabels[k]![language] ?? extraLabels[k]!['English']!),
    ]);
    for (final r in rows) {
      sheet.appendRow([
        TextCellValue(r.mlid),
        TextCellValue(r.fullName),
        TextCellValue(role),
        TextCellValue(r.village ?? ''),
      ]);
    }
    if (notes.isNotEmpty) {
      final notesSheet = excel['Notes'];
      for (final line in notes) {
        notesSheet.appendRow([TextCellValue(line)]);
      }
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('The template could not be generated.');
    return Uint8List.fromList(bytes);
  }

  Future<void> shareBytes(Uint8List bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, name: fileName)], subject: fileName),
    );
  }

  /// Every sheet in a workbook, as plain rows of strings, with the same
  /// fallback [_decodeTable] uses for a single sheet.
  ///
  /// WHY: the multi-sheet importers — the customer grid and the weekly account
  /// — called `Excel.decodeBytes` directly and so never got the fallback. That
  /// package throws "Null check operator used on a null value" on any workbook
  /// storing text as INLINE strings, which openpyxl and most non-Excel
  /// exporters do, and the Owner was told "this file could not be read as a
  /// spreadsheet" — the app blaming their file for its own crash. Fixed once
  /// for the identity sheet; these two were still exposed.
  static Map<String, List<List<String>>> _decodeSheets(
      Uint8List bytes, String fileName) {
    try {
      final book = Excel.decodeBytes(bytes);
      return {
        for (final name in book.tables.keys)
          name: [
            for (final row in book.tables[name]!.rows)
              [for (final cell in row) _cellText(cell?.value)],
          ],
      };
    } catch (e) {
      try {
        return XlsxFallbackReader.decode(bytes).sheets;
      } catch (_) {
        throw ImportFormatException(
            'This file could not be read as a spreadsheet. If it came from '
            'another app, save it as .xlsx or .csv and try again. ($e)');
      }
    }
  }

  static List<List<String>> _decodeTable(Uint8List bytes, String fileName, {required String preferredSheet}) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.csv')) return _parseCsv(utf8.decode(bytes, allowMalformed: true));

    final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (e) {
      // The `excel` package throws "Null check operator used on a null value"
      // on any workbook whose text is stored as INLINE strings rather than in a
      // shared-strings table. openpyxl writes that shape, and so do several
      // exporters — so a sheet prepared in anything but Excel itself was
      // rejected with a message blaming the Owner's file for the app's crash.
      // Hit for real on the live test with a 55-row identity sheet.
      return _decodeTableFallback(bytes, preferredSheet, e);
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

  /// Second attempt with this app's own reader, which understands inline
  /// strings. If it also fails, the original error is reported — by then the
  /// file really is unreadable, and the first message is the informative one.
  static List<List<String>> _decodeTableFallback(
      Uint8List bytes, String preferredSheet, Object originalError) {
    final Map<String, List<List<String>>> sheets;
    try {
      sheets = XlsxFallbackReader.decode(bytes).sheets;
    } catch (_) {
      throw ImportFormatException('This file could not be read as a spreadsheet. '
          'If it came from another app, save it as .xlsx or .csv and try again. '
          '($originalError)');
    }

    final rows = sheets[preferredSheet] ??
        sheets.values.cast<List<List<String>>?>().firstWhere(
              (r) => r != null && r.isNotEmpty,
              orElse: () => null,
            );
    if (rows == null || rows.isEmpty) {
      throw const ImportFormatException('The workbook has no sheet with any rows in it.');
    }
    return rows;
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

  /// Rows the book already had, so this run left them alone. Re-uploading a
  /// sheet to finish a partly-failed import is the normal way to recover, and
  /// without this the screen would report "0 imported" and read as a failure.
  final int skipped;

  const ImportOutcome({
    required this.imported,
    required this.errors,
    this.created = const [],
    this.skipped = 0,
  });
  bool get rejected => errors.isNotEmpty;
}

class ImportFormatException implements Exception {
  final String message;
  const ImportFormatException(this.message);
  @override
  String toString() => message;
}

/// One person already on the business's books, as a picker shows them.
///
/// Public because investors and shareholders are now chosen from a search
/// rather than typed into a spreadsheet: there are a handful of them, they are
/// already on the books from page 1, and asking an Owner to retype a name and
/// an MLID into Excel to say what they invested was work invented by the
/// tooling rather than the task.
class ManaMemberRef {
  final String mlid;
  final String fullName;
  final String? village;
  const ManaMemberRef({required this.mlid, required this.fullName, this.village});

  /// Name, MLID and village all searched together, so an Owner can type
  /// whichever they happen to remember.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q) ||
        mlid.toLowerCase().contains(q) ||
        (village ?? '').toLowerCase().contains(q);
  }
}

/// A (PIN, Village) pair named by the identity sheet.
class VillageRef {
  final String pinCode;
  final String village;
  const VillageRef({required this.pinCode, required this.village});
}

/// What the LGD reference knows about a PIN. A suggestion, never a validation.
class VillageSuggestion {
  final String village;
  final String mandal;
  final String district;
  final String state;
  const VillageSuggestion({
    required this.village,
    required this.mandal,
    required this.district,
    required this.state,
  });
}

class AttendanceResult {
  final int recorded;

  /// Days the agent already had, so this run left them alone.
  final int alreadyIn;

  const AttendanceResult({required this.recorded, this.alreadyIn = 0});
}

class CustomerGridParse {
  final List<Map<String, dynamic>> loans;
  final List<EmiScheduleRow> schedule;

  /// EMI pairs that carried something but could not be read — half a pair, or
  /// an amount that is not whole rupees. Surfaced beside the ready count so a
  /// sheet cannot quietly arrive with no history at all.
  final int unreadableInstalments;

  const CustomerGridParse({
    required this.loans,
    required this.schedule,
    this.unreadableInstalments = 0,
  });
}

class LoanRef {
  final String loanId;
  final String customerId;

  /// The loan's regular instalment. Needed by the replay: a historical
  /// payment larger than this is an Excess as far as record_collection is
  /// concerned, and an Excess must say where the extra went.
  final int installmentAmount;

  /// The day the loan was issued. record_collection refuses a payment dated
  /// before it, and rightly so — the replay checks first only to be able to
  /// say WHICH dates disagree.
  final DateTime? effectiveDate;

  const LoanRef({
    required this.loanId,
    required this.customerId,
    required this.installmentAmount,
    this.effectiveDate,
  });
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

  /// Instalments the loan already had, so this run left them alone. Shown to
  /// the Owner: on a resumed replay it is the bulk of the sheet, and a screen
  /// reporting "12 recorded" out of 216 rows with no explanation reads as a
  /// failure rather than as the rest already being in.
  final int skipped;

  const EmiSubmitResult({
    required this.recorded,
    required this.errors,
    this.skipped = 0,
  });
}

final bulkOnboardingServiceProvider = Provider<BulkOnboardingService>(
  (ref) => BulkOnboardingService(Supabase.instance.client, ref),
);


/// The counts behind the "already added" line on each wizard page.
///
/// A thin wrapper rather than a field per count: the RPC is the shape's owner,
/// and a page that wants a number it does not yet expose should add it there,
/// not invent it here.
class MigrationProgress {
  MigrationProgress(this._raw);
  final Map<String, dynamic> _raw;

  int count(String key) => (_raw[key] as num?)?.toInt() ?? 0;
  String? date(String key) {
    final v = _raw[key] as String?;
    return (v == null || v.isEmpty) ? null : v;
  }
}
