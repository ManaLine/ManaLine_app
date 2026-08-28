import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../../shared/mana_time.dart';

/// OW-006 Collection Mode — real Supabase wiring over Module 7
/// (04_API_Specification_v1 Part 3 §8). Shared verbatim with AG-002 (Agent
/// Collection Mode) per spec's own API BINDING — this file is imported
/// directly by ag_002_collection_mode.dart; every method signature below is
/// UNCHANGED from the stub so that screen keeps compiling untouched.
///
/// INTEGRATION FLAG (read before relying on this): `Supabase.instance.client`
/// assumes `Supabase.initialize(...)` has already run in main.dart. As
/// delivered to this session, main.dart does not call it yet — that's the
/// Auth chat's file, not this one's, so it isn't touched here, but until it
/// lands every call below will throw at `Supabase.instance` access, not at
/// the query itself. Flagged for master chat per the briefing.
///
/// IDENTITY FLAG: `authFlowProvider.personId` is typed `String?` and
/// `persons.person_id` is `BIGINT`. This file parses it with `int.parse`
/// (BIGINT fits in Dart's 64-bit `int` on every platform this app targets
/// except web's JS-number `int`, which loses precision above 2^53 — flagged
/// as a real, if currently unlikely-to-bite, risk given person_id is an
/// auto-increment starting at 1).
class CollectionApiService {
  final Ref ref;
  CollectionApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  /// Not part of the original stub's public surface — internal helper only.
  /// Resolves the ACTIVE business_members.membership_id for the current
  /// logged-in person within [businessId], preferring an Agent-role row
  /// (the common caller of Collection Mode) and falling back to Owner
  /// (BR-199 unrestricted access — an Owner can also record collections
  /// per rls_role_matrix.md's "O: full" on `collections`).
  Future<String> _currentMembershipId(String businessId) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      throw StateError('No logged-in person_id available — cannot resolve business_members.membership_id.');
    }
    final rows = await _db
        .from('business_members')
        .select('membership_id, role')
        .eq('person_id', int.parse(personId))
        .eq('business_id', businessId)
        .eq('membership_status', 'Active')
        .inFilter('role', ['Agent', 'Owner']);
    if (rows.isEmpty) {
      throw StateError('Current person has no Active Agent/Owner membership in business $businessId.');
    }
    final agentRow = rows.firstWhere((r) => r['role'] == 'Agent', orElse: () => rows.first);
    return agentRow['membership_id'] as String;
  }

  /// GET-equivalent: today's collection due list for [businessId]. RLS
  /// (0016_rls_module7/0015_rls_module6) already scopes this correctly per
  /// caller — an Agent sees only their assigned customers' loans, an Owner
  /// sees the whole business; no extra role branching needed here, per the
  /// briefing's "RLS is a feature, not a bug to work around."
  ///
  /// #18: reads the server's due list from `app.v_collection_due` — real
  /// `total_due` (sum of Pending installments due up to today), real
  /// `next_installment_no` (lowest Pending installment), `is_overdue`, and
  /// `penalty_eligible` computed over `loan_schedule`, replacing the old
  /// client-side approximations (`installmentDue` was the flat
  /// installment_amount, `lineRepaymentIndex` was always 0). The view is
  /// `security_invoker`, so an Agent sees exactly their areas' loans (M4)
  /// and the Owner sees the whole business. BR-112 is preserved server-side:
  /// a partially-paid installment still counts at full amount.
  Future<List<CollectionDueRow>> fetchDueList({required String businessId}) async {
    final rows = await _db
        .schema('app')
        .from('v_collection_due')
        .select('loan_id, customer_id, customer_name, village, loan_number, '
            'total_due, remaining_balance, next_installment_no, is_overdue, '
            'penalty_eligible, loan_status, collection_agent_name, repayment_type, mlid, '
            'today_result, collected_today, installment_amount, in_grace, grace_period_days')
        .eq('business_id', businessId);

    return (rows as List).map((r) {
      return CollectionDueRow(
        loanId: r['loan_id'] as String,
        customerId: r['customer_id'] as String,
        customerName: r['customer_name'] as String? ?? '',
        village: r['village'] as String? ?? '',
        loanNumber: r['loan_number'] as String,
        mlid: r['mlid'] as String? ?? '',
        installmentDue: (r['total_due'] as num).toInt(),
        installmentAmount: (r['installment_amount'] as num?)?.toInt() ?? 0,
        outstandingBalance: (r['remaining_balance'] as num).toInt(),
        lineRepaymentIndex: (r['next_installment_no'] as num?)?.toInt() ?? 1,
        collectionStatus: manaCollectionStatus(r['today_result'] as String?),
        collectedToday: (r['collected_today'] as num?)?.toInt() ?? 0,
        collectionAgent: r['collection_agent_name'] as String? ?? '',
        penaltyEligible: r['penalty_eligible'] as bool? ?? false,
        // The view derives this. It used to read loan_status == 'Grace
        // Period', a status nothing in this codebase writes, so the round
        // never showed grace on any loan -- granted or not.
        gracePeriod: r['in_grace'] as bool? ?? false,
        gracePeriodDays: (r['grace_period_days'] as num?)?.toInt() ?? 0,
        isOverdue: r['is_overdue'] as bool? ?? false,
        repaymentType: r['repayment_type'] as String? ?? '',
      );
    }).toList();
  }

  /// POST-equivalent: records a Collection, its payment split rows, and
  /// deducts from the loan's remaining_balance — all three MUST happen
  /// atomically (a collection recorded without its splits, or without the
  /// balance actually moving, is a data-integrity bug a plain multi-step
  /// Postgrest call cannot safely guarantee under a dropped connection
  /// between steps). The `record_collection` RPC does all of it in one
  /// database transaction, and also decides Full / Partial / Excess
  /// server-side so the phone never recomputes that classification.
  ///
  /// ONE ENTRY PER LOAN PER DAY: if this loan already has an entry for this
  /// business date -- whoever recorded it -- the RPC writes nothing and
  /// returns `already_recorded` naming that entry. There is no override. A
  /// correction goes through [amendCollection]; a second row is how one
  /// payment ends up with two receipts.
  ///
  /// [confirmDuplicate] is inert. It used to turn the old warning into a
  /// second insert, and it is kept only because dropping it from the RPC's
  /// parameter list means DROP + CREATE, which this codebase has had answer
  /// HTTP 300 four times.
  Future<RecordCollectionOutcome> recordCollection({
    required String loanId,
    required String customerId,
    required int collectedAmount, // whole rupees (M8)
    required String payerType, // Customer | Guarantor | Others
    String? payerName, // free text, only when payerType is Others
    String? guarantorId,
    required List<PaymentSplit> paymentSplits,
    required String businessDate, // the business day this counts towards
    required String businessId, // used to resolve the caller's own membership
    String? excessDisposition, // Advance | Refund | Next Installment
    String? remarks,
    bool confirmDuplicate = false, // inert; see the note above
    // Same key on every retry of one save; see shared/idempotency.dart.
    String? idempotencyKey,
  }) async {
    final response = await _db.schema('app').rpc('record_collection', params: {
      'p_loan_id': loanId,
      'p_customer_id': customerId,
      'p_collected_amount': collectedAmount,
      'p_payer_type': payerType,
      'p_payer_name': payerName,
      'p_idempotency_key': idempotencyKey,
      'p_business_date': businessDate,
      'p_collected_by_membership_id': await _currentMembershipId(businessId),
      'p_guarantor_id': guarantorId,
      'p_excess_disposition': excessDisposition,
      'p_remarks': remarks,
      'p_splits': paymentSplits.map((s) => {'payment_mode': s.paymentMode, 'amount': s.amount}).toList(),
      'p_confirm_duplicate': confirmDuplicate,
    });

    final map = response as Map<String, dynamic>;
    if (map['status'] == 'already_recorded') {
      return RecordCollectionOutcome.already(ExistingCollection(
        collectionId: map['collection_id'] as String? ?? '',
        receiptNumber: map['receipt_number'] as String? ?? '',
        collectedAmount: (map['collected_amount'] as num?)?.toInt() ?? 0,
        resultType: map['result_type'] as String? ?? '',
        recordedBy: map['recorded_by'] as String? ?? '',
        mine: map['mine'] as bool? ?? false,
        window: map['window'] as String? ?? 'day',
        businessDate: map['business_date'] == null
            ? null
            : DateTime.tryParse(map['business_date'] as String),
      ));
    }
    return RecordCollectionOutcome.saved(CollectionResult(
      collectionId: map['collection_id'] as String? ?? '',
      receiptNumber: map['receipt_number'] as String? ?? '',
      resultType: (map['result_type'] as String?) ?? 'Full',
      collectedAmount: (map['collected_amount'] as num?)?.toInt() ?? collectedAmount,
      newOutstandingBalance: (map['remaining_balance'] as num?)?.toInt() ?? 0,
      businessDate: DateTime.parse(businessDate),
    ));
  }

  /// The entry standing against this loan today, if there is one, with
  /// enough of it to open the form on.
  ///
  /// Fetched on demand rather than carried on every due row: it is needed
  /// only when somebody actually presses to correct an entry, and the round
  /// loads fifty-odd rows on every open.
  Future<CollectionEdit?> fetchTodaysCollection({
    required String loanId,
    required String businessDate,
  }) async {
    final rows = await _db
        .from('collections')
        .select('collection_id, receipt_number, collected_amount, payer_type, '
            'payer_name, remarks, collection_payment_splits(payment_mode, amount)')
        .eq('loan_id', loanId)
        .eq('business_date', businessDate)
        .isFilter('deleted_at', null)
        .order('entry_timestamp', ascending: false)
        .limit(1);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    final r = list.first;
    final splitRows = ((r['collection_payment_splits'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return CollectionEdit(
      collectionId: r['collection_id'] as String,
      receiptNumber: r['receipt_number'] as String? ?? '',
      collectedAmount: (r['collected_amount'] as num).toInt(),
      payerType: r['payer_type'] as String? ?? 'Customer',
      payerName: r['payer_name'] as String?,
      remarks: r['remarks'] as String?,
      splits: {
        for (final s in splitRows)
          s['payment_mode'] as String: (s['amount'] as num).toInt(),
      },
    );
  }

  /// Corrects an entry in place, balance and splits with it.
  ///
  /// Deliberately NOT a delete-and-re-record: the receipt number the customer
  /// is holding stays valid. app.amend_collection refuses once a settlement
  /// covering the day is with the Owner, which is the window the Owner asked
  /// for -- editable until the account is submitted.
  Future<CollectionResult> amendCollection({
    required String collectionId,
    required int collectedAmount,
    required String payerType,
    String? payerName,
    required List<PaymentSplit> paymentSplits,
    String? excessDisposition,
    String? remarks,
  }) async {
    final response = await _db.schema('app').rpc('amend_collection', params: {
      'p_collection_id': collectionId,
      'p_collected_amount': collectedAmount,
      'p_payer_type': payerType,
      'p_payer_name': payerName,
      'p_splits': paymentSplits
          .map((s) => {'payment_mode': s.paymentMode, 'amount': s.amount})
          .toList(),
      'p_excess_disposition': excessDisposition,
      'p_remarks': remarks,
    });
    final map = response as Map<String, dynamic>;
    return CollectionResult(
      collectionId: map['collection_id'] as String? ?? collectionId,
      receiptNumber: map['receipt_number'] as String? ?? '',
      resultType: map['result_type'] as String? ?? 'Full',
      collectedAmount: (map['collected_amount'] as num?)?.toInt() ?? collectedAmount,
      newOutstandingBalance: (map['remaining_balance'] as num?)?.toInt() ?? 0,
      businessDate: DateTime.parse(manaBusinessDate()),
    );
  }

  /// POST /no_collection_visits — a single-table insert with no derived
  /// financial math, safe to do directly (unlike recordCollection above).
  Future<void> recordNoCollectionVisit({required String loanId, required String reason}) async {
    final loan = await _db.from('loans').select('business_id, customer_id').eq('loan_id', loanId).single();
    final membershipId = await _currentMembershipId(loan['business_id'] as String);
    await _db.from('no_collection_visits').insert({
      'loan_id': loanId,
      'customer_id': loan['customer_id'],
      'visited_by_membership_id': membershipId,
      'reason': reason,
      'business_date': manaBusinessDate(),
    });
  }

  /// POST /extension_requests — single-table insert. `requested_by` is
  /// derived from whichever role the current membership resolves to
  /// (Agent vs Customer), per BR schema note: "either party inserting a
  /// row falsely attributed to the other's requested_by value" must be
  /// prevented — RLS (0015) already pins this at the policy layer, but we
  /// also set it correctly here rather than relying on RLS to silently
  /// reject a wrong value with a confusing error.
  Future<String> requestExtension({required String loanId, String? remarks}) async {
    final loan = await _db.from('loans').select('business_id').eq('loan_id', loanId).single();
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) throw StateError('No logged-in person_id available.');
    final role = await _db
        .from('business_members')
        .select('role')
        .eq('person_id', int.parse(personId))
        .eq('business_id', loan['business_id'] as String)
        .eq('membership_status', 'Active')
        .inFilter('role', ['Agent', 'Customer']);
    final requestedBy = role.isNotEmpty ? (role.first['role'] as String) : 'Agent';
    final inserted = await _db
        .from('extension_requests')
        .insert({
          'loan_id': loanId,
          'requested_by': requestedBy,
          'status': 'Pending',
          'business_date': manaBusinessDate(),
        })
        .select('extension_id')
        .single();
    // NOTE: `remarks` is accepted by this method's signature (kept
    // unchanged for AG-002 compatibility) but extension_requests has no
    // remarks column in the locked schema (§6.6) — silently dropped rather
    // than guessed into some other column. Flagged as a schema/UI mismatch:
    // either the screen's remarks field should be removed, or the schema
    // needs an addendum column, master chat's call.
    return inserted['extension_id'] as String;
  }

  /// PATCH /extension_requests/{id} — Owner decision only (schema: "Owner
  /// decision"). `decided_by_person_id` set to the current person; RLS
  /// restricts the actual UPDATE to Owner-context callers regardless.
  Future<void> decideExtension({required String extensionRequestId, required bool approved}) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) throw StateError('No logged-in person_id available.');
    await _db.from('extension_requests').update({
      'status': approved ? 'Approved' : 'Rejected',
      'decided_by_person_id': int.parse(personId),
    }).eq('extension_id', extensionRequestId);
  }
}

class PaymentSplit {
  final String paymentMode; // Cash | UPI | Bank Transfer | Cheque
  final int amount; // whole rupees (M8)
  PaymentSplit({required this.paymentMode, required this.amount});
}

/// Narrows an already-sorted due list to the rows matching [query].
///
/// Deliberately applied AFTER `sorted` and never inside it: the collection
/// order is a business rule, not a display preference, and a filter that
/// reordered what is left would quietly change which customer an Agent visits
/// first. Filtering preserves the order it was handed.
///
/// Matches name, village, loan number, the line repayment index and the
/// assigned agent — every field a row actually shows, so anything readable on
/// screen is also findable. The LRI is included because it is the number
/// called out on a route sheet, and it is what someone types when they have a
/// paper list in front of them.
/// The server's own classification of today's visit, in the round's words.
///
/// record_collection writes result_type as Full / Partial / Excess / No
/// Collection. This renames rather than recomputes: deriving "was this
/// collected" from amounts would be a second opinion on a question already
/// answered, and the two would disagree the first time a rule changed.
///
/// Excess counts as Collected. Somebody who paid more than was due has
/// certainly been collected from, and showing that door as still owing would
/// send the Agent back to it.
String manaCollectionStatus(String? todayResult) => switch (todayResult) {
      'Full' || 'Excess' => 'Collected',
      'Partial' => 'Partial',
      'No Collection' => 'Skipped',
      // Null is a door not yet knocked on. Not the same as one that was
      // visited and paid nothing -- that is Skipped, above.
      _ => 'Pending',
    };

List<CollectionDueRow> manaFilterDueRows(
  List<CollectionDueRow> rows,
  String query, {
  /// Daily / Weekly / Monthly, or null for all of them. A separate argument
  /// rather than another term in the text search: an Agent narrowing to the
  /// Daily line is stating which round they are on, not searching for a word,
  /// and typing "daily" must not also match a customer called Daily.
  String? frequency,
}) {
  final q = query.trim().toLowerCase();
  var out = rows;
  if (frequency != null && frequency.isNotEmpty) {
    out = [for (final r in out) if (r.repaymentType == frequency) r];
  }
  if (q.isEmpty) return out;
  return [
    for (final r in out)
      if (r.customerName.toLowerCase().contains(q) ||
          r.village.toLowerCase().contains(q) ||
          r.loanNumber.toLowerCase().contains(q) ||
          r.collectionAgent.toLowerCase().contains(q) ||
          '${r.lineRepaymentIndex}'.contains(q))
        r,
  ];
}

class CollectionDueRow {
  final String loanId;
  final String customerId;
  final String customerName;
  final String village;
  final String loanNumber;

  /// The customer's MANA LINE ID. Shown under their name in the round: it is
  /// on the card they carry, and it is what tells two customers of the same
  /// name in the same village apart.
  final String mlid;
  /// EVERYTHING that has fallen due and is still owed -- every missed
  /// instalment added up, capped at the balance. On the live book that is
  /// Rs 5,30,000 for a customer whose instalment is Rs 30,000.
  ///
  /// This is the RANKING figure: it decides who leads the round and what the
  /// day's target is. It is NOT what is asked for at a door.
  final int installmentDue;

  /// ONE instalment -- what this customer actually hands over on a visit.
  ///
  /// The row leads with this, and the collect form opens on it. Showing the
  /// whole arrears where the amount goes invites the Agent to key
  /// Rs 5,30,000 into a field that is about to become a receipt, and a
  /// customer who is nineteen weeks behind still pays one instalment today.
  final int installmentAmount;
  final int outstandingBalance;
  final int lineRepaymentIndex;
  final String collectionStatus; // Pending | Collected | Partial | Skipped

  /// What has actually been taken at this door today. Zero on a door not yet
  /// visited AND on a visit that collected nothing -- collectionStatus is what
  /// tells those two apart.
  final int collectedToday;

  /// Days of grace granted on this loan. Zero for most of them.
  final int gracePeriodDays;
  final String collectionAgent;
  final bool penaltyEligible;
  final bool gracePeriod;
  final bool isOverdue;

  /// Daily | Weekly | Monthly. Empty only if the view returned nothing for it,
  /// which the frequency filter treats as "not this round" rather than
  /// silently including the row in every round.
  final String repaymentType;

  CollectionDueRow({
    required this.loanId,
    required this.customerId,
    required this.customerName,
    required this.village,
    required this.loanNumber,
    this.mlid = '',
    required this.installmentDue,
    this.installmentAmount = 0,
    required this.outstandingBalance,
    required this.lineRepaymentIndex,
    required this.collectionStatus,
    this.collectedToday = 0,
    this.gracePeriodDays = 0,
    required this.collectionAgent,
    this.penaltyEligible = false,
    this.gracePeriod = false,
    this.isOverdue = false,
    this.repaymentType = '',
  });
}

class CollectionResult {
  /// The row's own id. The server has always returned it; nothing read it
  /// until the collection needed stamping with where it was taken.
  final String collectionId;
  final String receiptNumber;
  final String resultType; // Full | Partial | Excess
  final int collectedAmount;
  final int newOutstandingBalance;
  final DateTime businessDate;

  CollectionResult({
    this.collectionId = '',
    required this.receiptNumber,
    required this.resultType,
    required this.collectedAmount,
    required this.newOutstandingBalance,
    required this.businessDate,
  });
}

/// Result of trying to save a collection. Either it was saved, or the
/// server refused with a duplicate warning because another member already
/// recorded a payment on this loan today (details in [existing]).
class RecordCollectionOutcome {
  final CollectionResult? saved;

  /// This loan already has an entry for this day, so nothing was written.
  ///
  /// Was `duplicateWarning`, and it only ever fired when SOMEBODY ELSE had
  /// collected -- the same person could record a second and third payment on
  /// one loan without a word. One entry per loan per day is the rule now, and
  /// a correction is an amendment of the entry named here rather than another
  /// row beside it.
  final ExistingCollection? alreadyRecorded;

  RecordCollectionOutcome.saved(CollectionResult result)
      : saved = result,
        alreadyRecorded = null;

  RecordCollectionOutcome.already(ExistingCollection existing)
      : saved = null,
        alreadyRecorded = existing;
}

/// The entry that is already standing against a loan today.
class ExistingCollection {
  final String collectionId;
  final String receiptNumber;
  final int collectedAmount;
  final String resultType;
  final String recordedBy;

  /// 'day' or 'cycle' — which window the server measured.
  ///
  /// A Daily loan may be collected on every day of an account period; a
  /// Weekly or Monthly one may be collected once in the period. So the same
  /// refusal means two different things, and a message that says "today" over
  /// a weekly loan sends the Agent back tomorrow to be refused again.
  final String window;

  /// The day the existing entry was recorded on. Inside a cycle window it is
  /// not necessarily today.
  final DateTime? businessDate;

  /// Whether the caller is the person who recorded it. An Agent may correct
  /// their own entry; somebody else's is the Owner's to change.
  final bool mine;

  const ExistingCollection({
    required this.collectionId,
    required this.receiptNumber,
    required this.collectedAmount,
    required this.resultType,
    required this.recordedBy,
    required this.mine,
    this.window = 'day',
    this.businessDate,
  });
}

/// An entry being opened for correction: what it holds now, so the form can
/// come up showing it rather than an empty box the Agent has to retype.
class CollectionEdit {
  final String collectionId;
  final String receiptNumber;
  final int collectedAmount;
  final String payerType;
  final String? payerName;
  final String? remarks;
  final Map<String, int> splits;

  const CollectionEdit({
    required this.collectionId,
    required this.receiptNumber,
    required this.collectedAmount,
    required this.payerType,
    this.payerName,
    this.remarks,
    this.splits = const {},
  });
}

final collectionApiServiceProvider = Provider<CollectionApiService>((ref) {
  return CollectionApiService(ref: ref);
});

/// VILLAGE FIRST, then the urgency order within it: Penalty → Grace Period →
/// Today's Due → Customer Name.
///
/// The spec's original order put village fourth, which is right for a list you
/// read and wrong for a list you WALK: a route is worked one village at a
/// time, and penalty-first across the whole business sends an agent between
/// villages and back again. Urgency still leads inside each village, so the
/// row that matters most in the place you are standing is still at the top of
/// that group. Villages sort alphabetically; a customer with no address on
/// file sorts last rather than into a nameless group at the front.
/// How the round is ordered, once the Agent has chosen which villages they
/// are standing in.
///
/// Village used to lead the sort, because a route is walked one village at a
/// time. It is now a FILTER instead: an Agent picks the villages they are
/// working and the order applies within them, which is the same idea said
/// better — sorting by a thing you have already narrowed to does nothing.
enum CollectionSort {
  /// The default. Most owed today at the top, which is what a round is for.
  dueToday('Due Today'),
  penaltyFirst('Penalty First'),
  outstanding('Biggest Balance'),
  name('Name');

  const CollectionSort(this.label);
  final String label;
}

/// The villages this round touches, with how many rows each has.
///
/// A village whose every loan is settled is left out entirely: it is not a
/// place the Agent has to go today, and offering it is offering a trip for
/// nothing.
List<({String village, int rows, int due})> manaVillagesInRound(
    List<CollectionDueRow> list) {
  final byVillage = <String, ({int rows, int due})>{};
  for (final r in list) {
    final v = r.village.trim().isEmpty ? '' : r.village.trim();
    final now = byVillage[v] ?? (rows: 0, due: 0);
    byVillage[v] = (rows: now.rows + 1, due: now.due + r.installmentDue);
  }
  final out = [
    for (final e in byVillage.entries)
      if (e.value.due > 0) (village: e.key, rows: e.value.rows, due: e.value.due),
  ]..sort((a, b) {
      // A row with no village on file sorts last rather than into a nameless
      // group at the front.
      if (a.village.isEmpty != b.village.isEmpty) return a.village.isEmpty ? 1 : -1;
      return a.village.toLowerCase().compareTo(b.village.toLowerCase());
    });
  return out;
}

/// Narrows to the chosen villages. An empty choice means the whole round,
/// not an empty one -- an Agent who has picked nothing has not said "show me
/// nothing".
List<CollectionDueRow> manaFilterByVillages(
    List<CollectionDueRow> list, Set<String> villages) {
  if (villages.isEmpty) return list;
  return [
    for (final r in list)
      if (villages.contains(r.village.trim())) r,
  ];
}

/// Orders a round. Village is not an option here on purpose -- see
/// [CollectionSort].
/// This door is finished for today -- collected from, part-paid, or visited
/// and recorded as nothing collected.
///
/// The row widget greys these out and the sort sends them to the end. Both
/// need the same answer, so there is one place that gives it: two copies of
/// this rule drifting apart would grey a row that still sorted as work to do.
bool manaRowSettled(CollectionDueRow r) =>
    r.collectionStatus == 'Collected' ||
    r.collectionStatus == 'Partial' ||
    r.collectionStatus == 'Skipped';

List<CollectionDueRow> manaSortDueRows(
    List<CollectionDueRow> list, CollectionSort mode) {
  final sorted = [...list];
  int byName(CollectionDueRow a, CollectionDueRow b) =>
      a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase());
  sorted.sort((a, b) {
    // Finished doors sink, whatever the chosen sort says.
    //
    // A round is worked from the top, and a door already answered is not work
    // -- leaving it interleaved means scrolling past this morning to find
    // this afternoon. They stay in the list rather than disappearing: an
    // Agent checking whether they visited somebody has to be able to find
    // them.
    if (manaRowSettled(a) != manaRowSettled(b)) {
      return manaRowSettled(a) ? 1 : -1;
    }
    return switch (mode) {
        CollectionSort.dueToday => b.installmentDue.compareTo(a.installmentDue) != 0
            ? b.installmentDue.compareTo(a.installmentDue)
            : byName(a, b),
        CollectionSort.penaltyFirst => a.penaltyEligible != b.penaltyEligible
            ? (a.penaltyEligible ? -1 : 1)
            : (a.gracePeriod != b.gracePeriod
                ? (a.gracePeriod ? -1 : 1)
                : byName(a, b)),
        CollectionSort.outstanding =>
          b.outstandingBalance.compareTo(a.outstandingBalance) != 0
              ? b.outstandingBalance.compareTo(a.outstandingBalance)
              : byName(a, b),
        CollectionSort.name => byName(a, b),
    };
  });
  return sorted;
}

List<CollectionDueRow> _applyLockedSort(List<CollectionDueRow> list) {
  final sorted = [...list];
  sorted.sort((a, b) {
    final av = a.village.trim();
    final bv = b.village.trim();
    if (av.isEmpty != bv.isEmpty) return av.isEmpty ? 1 : -1;
    final byVillage = av.toLowerCase().compareTo(bv.toLowerCase());
    if (byVillage != 0) return byVillage;
    if (a.penaltyEligible != b.penaltyEligible) return a.penaltyEligible ? -1 : 1;
    if (a.gracePeriod != b.gracePeriod) return a.gracePeriod ? -1 : 1;
    final byDue = b.installmentDue.compareTo(a.installmentDue);
    if (byDue != 0) return byDue;
    return a.customerName.compareTo(b.customerName);
  });
  return sorted;
}

class CollectionModeState {
  final List<CollectionDueRow> dueList;
  final bool loading;
  final String? error;
  final int liveCollectionAmount; // whole rupees (M8)

  const CollectionModeState({
    this.dueList = const [],
    this.loading = false,
    this.error,
    this.liveCollectionAmount = 0,
  });

  List<CollectionDueRow> get sorted => _applyLockedSort(dueList);
  int get totalDue => dueList.length;
  /// Doors where money changed hands, part payments included.
  ///
  /// A Partial used to count as neither collected nor pending, so the three
  /// figures did not add up to the round and the strip read as broken the
  /// first time somebody paid half. Money was taken at that door; the Agent
  /// does not have to go back today.
  int get collected => dueList
      .where((r) => r.collectionStatus == 'Collected' || r.collectionStatus == 'Partial')
      .length;
  int get pending => dueList.where((r) => r.collectionStatus == 'Pending').length;
  int get skipped => dueList.where((r) => r.collectionStatus == 'Skipped').length;
  int get penaltyCount => dueList.where((r) => r.penaltyEligible).length;
  int get graceCount => dueList.where((r) => r.gracePeriod).length;

  CollectionModeState copyWith({
    List<CollectionDueRow>? dueList,
    bool? loading,
    String? error,
    bool clearError = false,
    int? liveCollectionAmount,
  }) {
    return CollectionModeState(
      dueList: dueList ?? this.dueList,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      liveCollectionAmount: liveCollectionAmount ?? this.liveCollectionAmount,
    );
  }
}

class CollectionModeNotifier extends Notifier<CollectionModeState> {
  @override
  CollectionModeState build() => const CollectionModeState();

  Future<void> load(String businessId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(collectionApiServiceProvider);
      final list = await api.fetchDueList(businessId: businessId);
      state = state.copyWith(dueList: list, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// The entry standing against this loan today, for correcting it.
  Future<CollectionEdit?> loadTodaysCollection({
    required String loanId,
    required String businessDate,
  }) {
    return ref.read(collectionApiServiceProvider).fetchTodaysCollection(
          loanId: loanId,
          businessDate: businessDate,
        );
  }

  /// Corrects an entry. Rethrows -- the reason an amendment was refused (the
  /// account is already with the Owner, the caller did not take the money) is
  /// the whole content of the failure.
  Future<CollectionResult> amendCollection({
    required String collectionId,
    required int collectedAmount,
    required String payerType,
    String? payerName,
    required List<PaymentSplit> paymentSplits,
    String? excessDisposition,
    String? remarks,
    required int previousAmount,
  }) async {
    final result = await ref.read(collectionApiServiceProvider).amendCollection(
          collectionId: collectionId,
          collectedAmount: collectedAmount,
          payerType: payerType,
          payerName: payerName,
          paymentSplits: paymentSplits,
          excessDisposition: excessDisposition,
          remarks: remarks,
        );
    // The running total follows the correction rather than counting the
    // money twice: what changed is the difference, not the whole entry.
    state = state.copyWith(
      liveCollectionAmount:
          state.liveCollectionAmount + (collectedAmount - previousAmount),
    );
    return result;
  }

  Future<RecordCollectionOutcome?> recordCollection({
    required String loanId,
    required String customerId,
    required int collectedAmount, // whole rupees (M8)
    required String payerType,
    String? payerName,
    String? guarantorId,
    required List<PaymentSplit> paymentSplits,
    required String businessDate,
    required String businessId,
    String? excessDisposition,
    String? remarks,
    bool confirmDuplicate = false,
    String? idempotencyKey,
  }) async {
    try {
      final api = ref.read(collectionApiServiceProvider);
      final outcome = await api.recordCollection(
        loanId: loanId,
        customerId: customerId,
        collectedAmount: collectedAmount,
        payerType: payerType,
        payerName: payerName,
        idempotencyKey: idempotencyKey,
        guarantorId: guarantorId,
        paymentSplits: paymentSplits,
        businessDate: businessDate,
        businessId: businessId,
        excessDisposition: excessDisposition,
        remarks: remarks,
        confirmDuplicate: confirmDuplicate,
      );
      // Count the money only when it was actually saved (an entry that
      // already exists means nothing was recorded).
      if (outcome.saved != null) {
        state = state.copyWith(liveCollectionAmount: state.liveCollectionAmount + collectedAmount);
      }
      return outcome;
    } catch (e) {
      // Kept for anything reading state.error, and RETHROWN.
      //
      // Returning null here swallowed the real failure. The form saw null,
      // threw its own "Collection could not be saved", and that generic
      // sentence was all anyone -- the Agent at the door, and me reading
      // logcat -- ever got. The cause sat in state.error, which no screen
      // displays. A money write that fails must say why it failed.
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<bool> recordNoCollectionVisit({required String loanId, required String reason}) async {
    try {
      await ref.read(collectionApiServiceProvider).recordNoCollectionVisit(loanId: loanId, reason: reason);
      return true;
    } catch (e) {
      // Rethrown for the same reason as recordCollection above: false and
      // "the server refused it" must not look identical.
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<bool> requestAndDecideExtension({required String loanId, required bool approve}) async {
    try {
      final api = ref.read(collectionApiServiceProvider);
      final requestId = await api.requestExtension(loanId: loanId);
      await api.decideExtension(extensionRequestId: requestId, approved: approve);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final collectionModeProvider = NotifierProvider<CollectionModeNotifier, CollectionModeState>(
  CollectionModeNotifier.new,
);
