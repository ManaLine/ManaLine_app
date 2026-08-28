import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/mana_location.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../../shared/text_utils.dart';
import '../../../shared/document_viewer.dart' show DocumentSummary;
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart' show kManaQueryTimeout;

/// OW-004 Customer Domain — real Supabase wiring over Module 3
/// (persons/person_addresses/business_members/customers/customer_remarks).
class CustomerApiService {
  /// Needed for authFlowProvider.personId on writes that record who did them
  /// — see addRemark. Matches CollectionApiService's shape.
  final Ref ref;
  CustomerApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  /// Village/outstanding/todaysDue/lineRepaymentIndex are derived values —
  /// same KNOWN SIMPLIFICATION already flagged in collection_mode_state.dart
  /// (this session): a precise per-installment "today's due" needs a
  /// loan_schedule join against the business's current business_date, which
  /// this single-query list view doesn't attempt. installmentDue below is
  /// approximated as SUM of each Active/Grace/Penalty loan's flat
  /// installment_amount; lineRepaymentIndex is left at 0 pending the same
  /// recommended v_collection_due_today-style view. Village IS resolved
  /// here (unlike collection_mode_state.dart) via person_addresses, since
  /// OW-004's own filter/sort explicitly needs it and customers.customer_id
  /// count here is small enough per business that the extra join is cheap.
  Future<List<CustomerSummary>> fetchCustomers({
    required String businessId,
    String? status,
    String? search,
  }) async {
    var q = _db
        .from('customers')
        .select('''
          customer_id, customer_status, membership_id, person_id,
          business_members!customers_membership_id_fkey!inner(business_id, membership_status),
          persons!inner(full_name, father_husband_name, mobile_number, mlid,
            person_addresses(village_id, is_current, locations(village_town_name))),
          loans(loan_id, loan_status, installment_amount, remaining_balance, repayment_amount)
        ''')
        .eq('business_members.business_id', businessId);
    if (status != null) q = q.eq('customer_status', status);
    final rows = await q;

    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final person = m['persons'] as Map<String, dynamic>;
      final addresses = (person['person_addresses'] as List?) ?? const [];
      final currentAddress = addresses.cast<Map<String, dynamic>?>().firstWhere(
            (a) => a?['is_current'] == true,
            orElse: () => addresses.isNotEmpty ? addresses.first as Map<String, dynamic> : null,
          );
      final village = (currentAddress?['locations'] as Map<String, dynamic>?)?['village_town_name'] as String? ?? '';
      final loans = ((m['loans'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final activeLoans = loans.where((l) => ['Active', 'Grace Period', 'Penalty'].contains(l['loan_status']));
      final todaysDue = activeLoans.fold<int>(0, (sum, l) => sum + (l['installment_amount'] as num).toInt());
      final outstanding = activeLoans.fold<int>(0, (sum, l) => sum + (l['remaining_balance'] as num).toInt());
      // What was lent in total, across this customer's live loans -- the
      // figure the row leads with. Distinct from what is still owed.
      final lent = activeLoans.fold<int>(
          0, (sum, l) => sum + ((l['repayment_amount'] as num?)?.toInt() ?? 0));

      return CustomerSummary(
        customerId: m['customer_id'] as String,
        fullName: titleCaseName(person['full_name'] as String? ?? ''),
        fatherHusbandName: titleCaseName(person['father_husband_name'] as String? ?? ''),
        village: village,
        phoneNumber: person['mobile_number'] as String? ?? '',
        mlid: person['mlid'] as String? ?? '',
        activeLoanCount: activeLoans.length,
        todaysDue: todaysDue,
        totalLoanAmount: lent,
        outstandingBalance: outstanding,
        lineRepaymentIndex: 0, // requires loan_schedule join — see method doc above
        customerStatus: m['customer_status'] as String,
        membershipStatus: (m['business_members'] as Map<String, dynamic>)['membership_status'] as String,
      );
    }).where((c) {
      if (search == null || search.trim().isEmpty) return true;
      final q2 = search.trim().toLowerCase();
      return c.fullName.toLowerCase().contains(q2) || c.mlid.toLowerCase().contains(q2) || c.phoneNumber.contains(q2);
    }).toList();
  }

  /// Identity Search — shared with OW-005 Step 1 per API BINDING. Searches
  /// `persons` directly (not scoped to any one business — the whole point
  /// of Link Existing is finding a person who may not yet have any
  /// membership in the current business). RLS on `persons` is
  /// business-partner-scoped (`app.shares_active_business`), so this will
  /// correctly return zero rows for a person the caller shares no business
  /// with at all — that's RLS working as intended, not a bug to route
  /// around; Create New Identity is the correct path when this legitimately
  /// finds nothing.
  /// EVERY match, not just the first.
  ///
  /// Was `Future<CustomerSummary?>` returning `list.first`, on top of an RPC
  /// that also had LIMIT 1 on every branch — so a business with two people
  /// called Sai could only ever surface one of them, in both the Add
  /// Customer sheet and the header's universal search. The unique-identifier
  /// branches still match at most one row by constraint; a name never did.
  Future<List<CustomerSummary>> searchIdentity({
    String? phone,
    String? aadhaar,
    String? mlid,
    String? fullName,
  }) async {
    if ((mlid == null || mlid.isEmpty) &&
        (aadhaar == null || aadhaar.isEmpty) &&
        (phone == null || phone.isEmpty) &&
        (fullName == null || fullName.isEmpty)) {
      return const [];
    }
    // .timeout, because PostgREST has no client-side deadline of its own.
    // A request that stalls (dead cell, captive portal) otherwise leaves the
    // caller's spinner turning forever with nothing to cancel it — which is
    // exactly what the Add Customer sheet did.
    final rows = await _db
        .schema('app')
        .rpc('owner_search_person', params: {
          'p_mlid': mlid,
          'p_mobile_number': phone,
          'p_aadhaar_number': aadhaar,
          'p_full_name': fullName,
        })
        .timeout(kManaQueryTimeout);
    final list = (rows as List).cast<Map<String, dynamic>>();
    return [
      for (final row in list)
        CustomerSummary(
          customerId: '', // no customers row yet — a persons-level result, not a customer
          personId: row['person_id']?.toString(),
          fullName: titleCaseName(row['full_name'] as String? ?? ''),
          fatherHusbandName: titleCaseName(row['father_husband_name'] as String? ?? ''),
          village: '',
          phoneNumber: row['mobile_number'] as String? ?? '',
          mlid: row['mlid'] as String? ?? '',
          activeLoanCount: 0,
          todaysDue: 0,
          outstandingBalance: 0,
          lineRepaymentIndex: 0,
          customerStatus: 'Active',
          membershipStatus: 'Pending Invitation',
        ),
    ];
  }

  /// Who this book may lend to.
  ///
  /// Two kinds of row come back, and the difference is the whole point:
  ///
  ///  * `customerId` set — already a customer here. Selectable straight away.
  ///  * `customerId` empty, `personId` set — found by global identity search,
  ///    not on this book yet. The wizard adds them before the loan is written.
  ///
  /// Which kinds appear is the OWNER'S rule, read server-side from
  /// businesses.loans_require_existing_customer. The default is permissive: a
  /// new borrower walks up, and the loan and the customer record happen in one
  /// conversation rather than sending the Owner to another screen mid-loan.
  ///
  /// This is NOT plain searchIdentity, which is what Step 1 used to call. That
  /// one is business-blind: it matched an Agent of the Owner's OTHER business,
  /// a person this book could not lend to at all, and the empty customerId
  /// travelled six wizard steps before failing at the insert as `invalid input
  /// syntax for type uuid: ""`. Here an empty customerId means something
  /// specific and the screen knows what to do about it.
  Future<List<CustomerSummary>> searchLoanCandidates({
    required String businessId,
    required String query,
  }) async {
    if (query.trim().isEmpty) return const [];
    final rows = await _db
        .schema('app')
        .rpc('owner_search_loan_candidate', params: {
          'p_business_id': businessId,
          'p_query': query.trim(),
        })
        .timeout(kManaQueryTimeout);
    return manaLoanCandidates((rows as List).cast<Map<String, dynamic>>());
  }

  /// Handles both Link Existing (existingPersonId set) and Create New
  /// Identity (fullName/etc. set) — mirrors the stub's single-endpoint
  /// contract, but as two real Postgrest write sequences rather than one
  /// POST, since there's no Edge Function/RPC for this yet. Both paths
  /// insert business_members (role='Customer') then customers, in that
  /// order (customers.membership_id is NOT NULL UNIQUE REFERENCES
  /// business_members).
  Future<String> createCustomer({
    required String businessId,
    String? existingPersonId,
    String? fullName,
    String? fatherHusbandName,
    String? genderDigit,
    String? mobileNumber,
    String? aadhaarNumber,
    String? doorNo,
    String? pinCode,
    String? villageId,
    /// Optional GPS pin for the address, captured at registration.
    ///
    /// All three stay null when the person declined location, has it switched
    /// off, or no fix arrived — registration must never depend on GPS, so the
    /// address is written exactly as before and the pin columns stay empty.
    double? gpsLatitude,
    double? gpsLongitude,
    double? gpsAccuracyM,
  }) async {
    if (existingPersonId != null) {
      // Linking an already-existing person -- business_members/customers
      // inserts are permitted directly (customers_owner_all,
      // business_members_owner_all both FOR ALL for the Owner); only
      // persons itself needed the RPC bypass, and that is not needed here
      // since the person already exists.
      final personId = int.parse(existingPersonId);
      final membershipRow = await _db
          .from('business_members')
          .insert({
            'person_id': personId,
            'business_id': businessId,
            'role': 'Customer',
            'membership_status': 'Active',
            'verification_status': 'Not Required', // BR-189
            'onboarding_method': 'Direct Registration',
          })
          .select('membership_id')
          .single();
      final membershipId = membershipRow['membership_id'] as String;

      final customerRow = await _db
          .from('customers')
          .insert({
            'membership_id': membershipId,
            'person_id': personId,
            'occupation': 'Other-Custom',
            'occupation_other_text': 'Not specified at creation',
            'customer_status': 'Active',
            'customer_since': manaBusinessDate(),
          })
          .select('customer_id')
          .single();
      return customerRow['customer_id'] as String;
    }

    // Brand-new identity -- RESOLVED (was a raw client insert that always
    // failed: persons has no client INSERT policy, and left mlid as a
    // literal empty string that would violate the UNIQUE/NOT NULL
    // constraint on every second call). Now a single atomic RPC --
    // app.register_new_customer (0045) -- handling persons +
    // person_addresses + business_members + customers together, with
    // Aadhaar optional (MLPI if given, MLTI if not).
    if (fullName == null || fatherHusbandName == null || genderDigit == null || mobileNumber == null) {
      throw ArgumentError('fullName/fatherHusbandName/genderDigit/mobileNumber are required to create a new identity.');
    }
    final result = await _db.schema('app').rpc('register_new_customer', params: {
      'p_business_id': businessId,
      'p_full_name': fullName,
      'p_father_husband_name': fatherHusbandName,
      'p_gender_digit': genderDigit,
      'p_mobile_number': mobileNumber,
      'p_aadhaar_number': aadhaarNumber,
      'p_door_no': doorNo,
      'p_pin_code': pinCode,
      'p_village_id': villageId,
      // Sent in the SAME call that creates the address rather than as a second
      // "now attach the GPS" write — a separate call can fail on its own and
      // leave a customer whose address exists but whose pin silently does not.
      'p_gps_latitude': gpsLatitude,
      'p_gps_longitude': gpsLongitude,
      'p_gps_accuracy_m': gpsAccuracyM,
    });
    return result as String; // RETURNS UUID (customer_id) -- a scalar return
  }


  // BUG FIXED this pass: OW-004's Customer Documents tab was a static
  // label list with onTap: () {} — customer_documents has a real insert
  // path (agent_customer_state.dart's customer creation flow) but
  // nothing ever read it back for display. This closes that.
  Future<List<DocumentSummary>> fetchCustomerDocuments({required String customerId}) async {
    final rows = await _db
        .from('customer_documents')
        .select('document_id, document_type, file_url, uploaded_at')
        .eq('customer_id', customerId)
        .eq('is_archived', false)
        .order('uploaded_at', ascending: false);
    return (rows as List)
        .map((r) => DocumentSummary(
              documentId: r['document_id'] as String,
              documentType: r['document_type'] as String,
              fileUrl: r['file_url'] as String,
              uploadedAt: DateTime.parse(r['uploaded_at'] as String),
            ))
        .toList();
  }

  Future<CustomerProfile> fetchCustomerProfile({required String customerId}) async {
    final row = await _db
        .from('customers')
        .select('''
          customer_id, customer_status, occupation, customer_since, membership_id,
          business_members!customers_membership_id_fkey!inner(membership_status),
          persons!inner(full_name, father_husband_name, mobile_number, mlid,
            person_addresses(village_id, is_current, locations(village_town_name))),
          loans(loan_id, loan_number, effective_date, repayment_amount, remaining_balance,
            installment_amount, loan_status),
          customer_remarks(remark_id, remark_text, priority, business_date, entered_by_person_id)
        ''')
        .eq('customer_id', customerId)
        .single();

    final person = row['persons'] as Map<String, dynamic>;
    final addresses = (person['person_addresses'] as List?) ?? const [];
    final currentAddress = addresses.cast<Map<String, dynamic>?>().firstWhere(
          (a) => a?['is_current'] == true,
          orElse: () => addresses.isNotEmpty ? addresses.first as Map<String, dynamic> : null,
        );
    final village = (currentAddress?['locations'] as Map<String, dynamic>?)?['village_town_name'] as String? ?? '';

    // M4: who covers a customer is decided by area now (no
    // assigned_agent_membership_id column). Ask the server for the covering
    // agent's membership, then resolve the name.
    String? agentName;
    final agentMembershipId =
        await _db.schema('app').rpc('covering_agent_membership_id', params: {'p_customer_id': customerId});
    if (agentMembershipId != null) {
      final agentRow = await _db
          .from('business_members')
          .select('persons!business_members_person_id_fkey(full_name)')
          .eq('membership_id', agentMembershipId)
          .maybeSingle();
      final rawAgentName = (agentRow?['persons'] as Map<String, dynamic>?)?['full_name'] as String?;
      agentName = rawAgentName == null ? null : titleCaseName(rawAgentName);
    }

    final collections = await manaFetchCustomerCollections(_db, customerId);

    final loans = ((row['loans'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final activeLoans = loans.where((l) => ['Active', 'Grace Period', 'Penalty'].contains(l['loan_status']));
    final todaysDue = activeLoans.fold<int>(0, (sum, l) => sum + (l['installment_amount'] as num).toInt());
    final outstanding = activeLoans.fold<int>(0, (sum, l) => sum + (l['remaining_balance'] as num).toInt());

    final summary = CustomerSummary(
      customerId: row['customer_id'] as String,
      fullName: titleCaseName(person['full_name'] as String? ?? ''),
      fatherHusbandName: titleCaseName(person['father_husband_name'] as String? ?? ''),
      village: village,
      phoneNumber: person['mobile_number'] as String? ?? '',
      mlid: person['mlid'] as String? ?? '',
      activeLoanCount: activeLoans.length,
      todaysDue: todaysDue,
      outstandingBalance: outstanding,
      lineRepaymentIndex: 0,
      customerStatus: row['customer_status'] as String,
      membershipStatus: (row['business_members'] as Map<String, dynamic>)['membership_status'] as String,
    );

    return CustomerProfile(
      summary: summary,
      occupation: row['occupation'] as String?,
      address: village,
      customerSince: DateTime.parse(row['customer_since'] as String),
      currentAgent: agentName,
      loans: loans
          .map((l) => CustomerLoanSummary(
                loanId: l['loan_id'] as String,
                loanNumber: l['loan_number'] as String,
                issueDate: DateTime.parse(l['effective_date'] as String),
                loanAmount: (l['repayment_amount'] as num).toInt(),
                outstanding: (l['remaining_balance'] as num).toInt(),
                todaysDue: (l['installment_amount'] as num).toInt(),
                // Money stays int; only the percentage needs a double — `/`
                // on two ints already yields a double in Dart.
                progressPercent: (l['repayment_amount'] as num).toInt() == 0
                    ? 0
                    : 100 -
                        (((l['remaining_balance'] as num).toInt() / (l['repayment_amount'] as num).toInt()) *
                            100),
                status: l['loan_status'] as String,
              ))
          .toList(),
      collections: collections,
      remarks: ((row['customer_remarks'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((r) => CustomerRemark(
                remarkId: r['remark_id'] as String,
                date: DateTime.parse(r['business_date'] as String),
                enteredBy: '', // requires a persons join on entered_by_person_id — omitted, see KNOWN SIMPLIFICATION pattern
                remark: r['remark_text'] as String,
                priority: r['priority'] as String,
              ))
          .toList(),
    );
  }

  Future<void> updateCustomerStatus({required String customerId, required String status}) async {
    await _db.from('customers').update({'customer_status': status}).eq('customer_id', customerId);
  }

  /// This app's identity layer does not use Supabase Auth's own session, so
  /// entered_by_person_id has to come from authFlowProvider.personId — which
  /// is why this service takes a Ref, the same shape CollectionApiService and
  /// AgentCustomerApiService already use.
  ///
  /// It previously threw UnimplementedError because the service was
  /// constructed without a Ref and the author would not guess a person_id.
  /// That was the right call; the fix was simply never made. The agent side
  /// (AgentCustomerApiService.addRemark) has done exactly this all along, so
  /// this is the same write, not a new one.
  Future<void> addRemark({required String customerId, required String remark, String? priority}) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      // Loud, not silent: a remark attributed to nobody is worse than a
      // remark that failed to save, because the first looks like it worked.
      throw StateError('No logged-in person_id available — cannot set entered_by_person_id.');
    }
    await _db.from('customer_remarks').insert({
      'customer_id': customerId,
      'entered_by_person_id': int.parse(personId),
      'remark_text': remark,
      'priority': priority ?? 'Normal',
      'business_date': manaBusinessDate(),
    });
  }
}

/// Rows from app.owner_search_loan_candidate -> CustomerSummary.
///
/// Split out of the service so it can be tested without a Supabase client.
///
/// A row is DROPPED only when it identifies nobody at all -- neither a
/// customer of this book nor a person to add. An empty customerId on its own
/// is not a defect here: it means "found, but not on this book yet", and the
/// wizard adds them. What must never happen is an empty customerId travelling
/// on as if it were a borrower, which is the fault this whole path was built
/// to close; that guard now lives at the point of selection, where the row's
/// personId is turned into a real customer first.
List<CustomerSummary> manaLoanCandidates(List<Map<String, dynamic>> rows) {
  final out = <CustomerSummary>[];
  for (final row in rows) {
    final id = row['customer_id']?.toString() ?? '';
    final personId = row['person_id']?.toString();
    if (id.isEmpty && (personId == null || personId.isEmpty)) continue;
    out.add(CustomerSummary(
      customerId: id,
      personId: personId,
      fullName: titleCaseName(row['full_name'] as String? ?? ''),
      fatherHusbandName: titleCaseName(row['father_husband_name'] as String? ?? ''),
      village: row['village'] as String? ?? '',
      phoneNumber: row['mobile_number'] as String? ?? '',
      mlid: row['mlid'] as String? ?? '',
      activeLoanCount: (row['active_loans'] as num?)?.toInt() ?? 0,
      todaysDue: 0,
      outstandingBalance: 0,
      lineRepaymentIndex: 0,
      customerStatus: 'Active',
      membershipStatus: 'Active',
    ));
  }
  return out;
}

class CustomerSummary {
  final String customerId;
  final String? personId; // populated for pre-membership identity search results (OW-004 Add Customer); customerId is empty in that case since no customers row exists yet
  final String fullName;
  final String fatherHusbandName;
  final String village;
  final String phoneNumber;
  final String mlid;
  final int activeLoanCount;
  final int todaysDue;
  /// Everything lent to this customer across their live loans -- the
  /// repayment total, not the cash handed over. Zero where a path builds a
  /// summary without loans (search results, pre-membership hits).
  final int totalLoanAmount;
  final int outstandingBalance;
  final int lineRepaymentIndex;
  final String customerStatus; // Active | Inactive | Deceased (global)
  final String membershipStatus; // Active | Suspended | Removed (per-business)

  CustomerSummary({
    required this.customerId,
    this.personId,
    required this.fullName,
    required this.fatherHusbandName,
    required this.village,
    required this.phoneNumber,
    required this.mlid,
    required this.activeLoanCount,
    required this.todaysDue,
    this.totalLoanAmount = 0,
    required this.outstandingBalance,
    required this.lineRepaymentIndex,
    required this.customerStatus,
    required this.membershipStatus,
  });
}

class CustomerLoanSummary {
  final String loanId;
  final String loanNumber;
  final DateTime issueDate;
  final int loanAmount;
  final int outstanding;
  final int todaysDue;
  final double progressPercent; // percentage — not money, stays double
  final String status;

  CustomerLoanSummary({
    required this.loanId,
    required this.loanNumber,
    required this.issueDate,
    required this.loanAmount,
    required this.outstanding,
    required this.todaysDue,
    required this.progressPercent,
    required this.status,
  });
}

/// A customer's receipts, for whichever workspace is asking.
///
/// `collections: const []` was hardcoded in BOTH profile services, so the
/// Collections tab said "No Collections Yet" for every customer in the app --
/// including one with eleven payments recorded. The empty state was correct
/// code rendering data that was never asked for. The tab has been shared
/// between the two workspaces for a while; the query that fills it is shared
/// now too, so the Owner's copy and the Agent's copy cannot drift the way the
/// due list once did.
///
/// Scoped through the customer rather than their loans: somebody who closed
/// one loan and opened another still has one payment history.
Future<List<CustomerCollectionRow>> manaFetchCustomerCollections(
    SupabaseClient db, String customerId) async {
  final rows = await db
      .from('collections')
      // The FK is named because collections has TWO into business_members
      // (collected_by and deleted_by) and PostgREST answers HTTP 300 for the
      // bare form -- see test/ambiguous_embed_guard_test.dart.
      .select('business_date, receipt_number, collected_amount, '
          'difference_amount, '
          'collection_payment_splits(payment_mode, amount), '
          'business_members!collections_collected_by_membership_id_fkey('
          'persons!business_members_person_id_fkey(full_name))')
      .eq('customer_id', customerId)
      .isFilter('deleted_at', null)
      .order('business_date', ascending: false)
      .order('entry_timestamp', ascending: false);

  return (rows as List).cast<Map<String, dynamic>>().map((c) {
    final splits = ((c['collection_payment_splits'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final member = c['business_members'] as Map<String, dynamic>?;
    final person = member?['persons'] as Map<String, dynamic>?;
    return CustomerCollectionRow(
      businessDate: DateTime.parse(c['business_date'] as String),
      amount: (c['collected_amount'] as num).toInt(),
      // Every mode it arrived in. One mode read off the row would say Cash
      // for a payment that was half UPI.
      paymentMode: splits.isEmpty
          ? ''
          : splits.map((s) => s['payment_mode'] as String).join(' + '),
      collector: titleCaseName(person?['full_name'] as String? ?? ''),
      receiptNumber: c['receipt_number'] as String? ?? '',
      difference: (c['difference_amount'] as num?)?.toInt() ?? 0,
    );
  }).toList();
}

class CustomerCollectionRow {
  final DateTime businessDate;
  final int amount;
  final String paymentMode;
  final String collector;
  final String receiptNumber;
  final int difference;

  CustomerCollectionRow({
    required this.businessDate,
    required this.amount,
    required this.paymentMode,
    required this.collector,
    required this.receiptNumber,
    required this.difference,
  });
}

class CustomerRemark {
  /// customer_remarks.remark_id — needed so a remark can be deleted. The
  /// query already selected it; the model used to drop it on the floor.
  final String remarkId;
  final DateTime date;
  final String enteredBy;
  final String remark;
  final String priority;

  CustomerRemark({
    required this.remarkId,
    required this.date,
    required this.enteredBy,
    required this.remark,
    required this.priority,
  });
}

class CustomerProfile {
  final CustomerSummary summary;
  final String? occupation;
  final String? address;
  final DateTime customerSince;
  final String? currentAgent;
  final List<CustomerLoanSummary> loans;
  final List<CustomerCollectionRow> collections;
  final List<CustomerRemark> remarks;

  CustomerProfile({
    required this.summary,
    this.occupation,
    this.address,
    required this.customerSince,
    this.currentAgent,
    this.loans = const [],
    this.collections = const [],
    this.remarks = const [],
  });
}

// --- Riverpod state ----------------------------------------------------

final customerApiServiceProvider = Provider<CustomerApiService>((ref) {
  return CustomerApiService(ref: ref);
});

/// C2b — locked cascading sort: Highest Outstanding → Penalty →
/// Grace Period → Today's Due → Village → Customer Name. Not user-
/// selectable single-field options — applied as one fixed sequence.
/// Village first, then the money.
///
/// This used to lead on highest outstanding, which sorts the list the way a
/// report is read rather than the way the book is worked. A round is a
/// village: the Owner and the Agent both move through one village at a time,
/// and an outstanding-first order scatters each village's customers down the
/// whole list, so finding the six people in Uranduru means scrolling past
/// everyone else.
///
/// Within a village the old order is kept exactly -- highest outstanding, then
/// today's due, then name -- so the money ranking that mattered still decides
/// who comes first among the people standing in the same place.
///
/// Customers with no village recorded sort last rather than first, where an
/// empty string would otherwise put them: they are the exception, and the
/// exception does not belong at the top of the round.
/// How the customer list is ordered.
///
/// [village] is the order this screen has always used and stays the default:
/// a round is walked one village at a time, so scattering a village's
/// customers down the list means scrolling past everyone else to find the six
/// people in Uranduru. The other three answer questions the Owner asks at a
/// desk rather than at a door.
enum CustomerSort { village, outstanding, todaysDue, name }

/// Orders the list, with village as the default.
///
/// The three alternatives all fall back to name, so the order is total: a
/// comparator that returns 0 for two different people lets the list reshuffle
/// itself between rebuilds, and a customer who moves while being tapped is a
/// customer somebody opens by mistake.
List<CustomerSummary> manaSortCustomers(
    List<CustomerSummary> list, CustomerSort sort,
    {bool ascending = true}) {
  if (sort == CustomerSort.village) {
    final locked = _applyLockedSort(list);
    return ascending ? locked : locked.reversed.toList();
  }
  final sorted = [...list];
  int byName(CustomerSummary a, CustomerSummary b) =>
      a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  // The named orders are all "biggest first" as written, so ascending flips
  // them. Name is the exception in feel but not in code: A-Z is what its
  // comparator gives, and reversing it gives Z-A, which is what somebody
  // asking for the other direction means.
  final sign = sort == CustomerSort.name
      ? (ascending ? 1 : -1)
      : (ascending ? -1 : 1);
  sorted.sort((a, b) => sign * switch (sort) {
        CustomerSort.outstanding =>
          b.outstandingBalance.compareTo(a.outstandingBalance) != 0
              ? b.outstandingBalance.compareTo(a.outstandingBalance)
              : byName(a, b),
        CustomerSort.todaysDue => b.todaysDue.compareTo(a.todaysDue) != 0
            ? b.todaysDue.compareTo(a.todaysDue)
            : byName(a, b),
        CustomerSort.name => byName(a, b),
        CustomerSort.village => 0,
      });
  return sorted;
}

List<CustomerSummary> _applyLockedSort(List<CustomerSummary> list) {
  final sorted = [...list];
  sorted.sort((a, b) {
    final aHas = a.village.isNotEmpty, bHas = b.village.isNotEmpty;
    if (aHas != bHas) return aHas ? -1 : 1;
    final byVillage = a.village.compareTo(b.village);
    if (byVillage != 0) return byVillage;
    final byOutstanding = b.outstandingBalance.compareTo(a.outstandingBalance);
    if (byOutstanding != 0) return byOutstanding;
    final byDue = b.todaysDue.compareTo(a.todaysDue);
    if (byDue != 0) return byDue;
    return a.fullName.compareTo(b.fullName);
  });
  return sorted;
}

class CustomerListState {
  final List<CustomerSummary> customers;
  final bool loading;
  final String? villageFilter;
  final String? customerStatusFilter;
  final String searchQuery;

  /// Defaults to village, which is the order the screen had before it was
  /// selectable at all.
  final CustomerSort sort;

  /// Which way the chosen order runs. Ascending by default, which is what
  /// village and name want; an Owner looking for the biggest balances flips
  /// it, and until now could not.
  final bool ascending;

  final String? error;

  const CustomerListState({
    this.sort = CustomerSort.village,
    this.ascending = true,
    this.customers = const [],
    this.loading = false,
    this.villageFilter,
    this.customerStatusFilter,
    this.searchQuery = '',
    this.error,
  });

  List<CustomerSummary> get filtered {
    var list = customers;
    if (villageFilter != null) list = list.where((c) => c.village == villageFilter).toList();
    if (customerStatusFilter != null) {
      list = list.where((c) => c.membershipStatus == customerStatusFilter).toList();
    }
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list
          .where((c) =>
              c.fullName.toLowerCase().contains(q) ||
              c.mlid.toLowerCase().contains(q) ||
              c.phoneNumber.contains(q))
          .toList();
    }
    return manaSortCustomers(list, sort, ascending: ascending);
  }

  CustomerListState copyWith({
    CustomerSort? sort,
    bool? ascending,
    List<CustomerSummary>? customers,
    bool? loading,
    String? villageFilter,
    bool clearVillageFilter = false,
    String? customerStatusFilter,
    bool clearCustomerStatusFilter = false,
    String? searchQuery,
    String? error,
    bool clearError = false,
  }) {
    return CustomerListState(
      customers: customers ?? this.customers,
      loading: loading ?? this.loading,
      villageFilter: clearVillageFilter ? null : (villageFilter ?? this.villageFilter),
      customerStatusFilter:
          clearCustomerStatusFilter ? null : (customerStatusFilter ?? this.customerStatusFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CustomerListNotifier extends Notifier<CustomerListState> {
  @override
  CustomerListState build() => const CustomerListState();

  Future<void> load(String businessId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(customerApiServiceProvider);
      final customers = await api.fetchCustomers(businessId: businessId);
      state = state.copyWith(customers: customers, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setSearchQuery(String q) => state = state.copyWith(searchQuery: q);

  void setSort(CustomerSort s) => state = state.copyWith(sort: s);
  void setAscending(bool a) => state = state.copyWith(ascending: a);
  void setVillageFilter(String? v) =>
      state = v == null ? state.copyWith(clearVillageFilter: true) : state.copyWith(villageFilter: v);
  void setCustomerStatusFilter(String? s) => state =
      s == null ? state.copyWith(clearCustomerStatusFilter: true) : state.copyWith(customerStatusFilter: s);

  Future<List<CustomerSummary>> searchIdentity({
    String? phone,
    String? aadhaar,
    String? mlid,
    String? fullName,
  }) async {
    try {
      return await ref
          .read(customerApiServiceProvider)
          .searchIdentity(phone: phone, aadhaar: aadhaar, mlid: mlid, fullName: fullName);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      // Rethrown, NOT swallowed into an empty list: "no such person" and
      // "the search failed" must not look identical on screen. The callers
      // show the message.
      rethrow;
    }
  }

  Future<List<CustomerSummary>> searchLoanCandidates({
    required String businessId,
    required String query,
  }) async {
    try {
      return await ref
          .read(customerApiServiceProvider)
          .searchLoanCandidates(businessId: businessId, query: query);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<bool> linkExisting(String businessId, String personId) async {
    try {
      await ref.read(customerApiServiceProvider).createCustomer(businessId: businessId, existingPersonId: personId);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// [createNew] but hands back the new customer_id.
  ///
  /// The migration form needs it: it registers the person and records their
  /// existing loan against them in one pass, and cannot look the id up by
  /// name afterwards without risking the wrong match in a village where
  /// several people share one.
  ///
  /// Rethrows rather than swallowing into a bool — a caller that is about to
  /// write a loan against this id must not proceed on a failure it cannot
  /// see. [createNew] keeps its bool contract for the callers that only
  /// need "did it work".
  Future<String> createNewReturningId({
    required String businessId,
    required String fullName,
    required String fatherHusbandName,
    required String genderDigit,
    required String mobileNumber,
    String? aadhaarNumber,
    required String doorNo,
    String? pinCode,
    required String villageId,
  }) async {
    final fix = await ManaLocation.currentFix();
    final id = await ref.read(customerApiServiceProvider).createCustomer(
          businessId: businessId,
          fullName: fullName,
          fatherHusbandName: fatherHusbandName,
          genderDigit: genderDigit,
          mobileNumber: mobileNumber,
          aadhaarNumber: aadhaarNumber,
          doorNo: doorNo,
          pinCode: pinCode,
          villageId: villageId,
          gpsLatitude: fix.latitude,
          gpsLongitude: fix.longitude,
          gpsAccuracyM: fix.accuracyM,
        );
    await load(businessId);
    return id;
  }

  Future<bool> createNew({
    required String businessId,
    required String fullName,
    required String fatherHusbandName,
    required String genderDigit,
    required String mobileNumber,
    String? aadhaarNumber,
    required String doorNo,
    String? pinCode,
    required String villageId,
  }) async {
    try {
      // Capture the pin HERE rather than in the screen, so every caller gets
      // it and no new "add customer" surface can forget. Best-effort by
      // construction: currentFix never throws, and a fix that did not arrive
      // simply leaves the three parameters null — registration goes through
      // exactly as it did before GPS existed.
      //
      // The address being registered is the one in front of the Owner right
      // now, which is what makes the pin worth anything.
      final fix = await ManaLocation.currentFix();

      await ref.read(customerApiServiceProvider).createCustomer(
            businessId: businessId,
            fullName: fullName,
            fatherHusbandName: fatherHusbandName,
            genderDigit: genderDigit,
            mobileNumber: mobileNumber,
            aadhaarNumber: aadhaarNumber,
            doorNo: doorNo,
            pinCode: pinCode,
            villageId: villageId,
            gpsLatitude: fix.latitude,
            gpsLongitude: fix.longitude,
            gpsAccuracyM: fix.accuracyM,
          );
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> updateStatus(String businessId, String customerId, String status) async {
    try {
      await ref.read(customerApiServiceProvider).updateCustomerStatus(customerId: customerId, status: status);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final customerListProvider = NotifierProvider<CustomerListNotifier, CustomerListState>(
  CustomerListNotifier.new,
);

class CustomerProfileNotifier extends FamilyAsyncNotifier<CustomerProfile, String> {
  @override
  Future<CustomerProfile> build(String customerId) async {
    return ref.read(customerApiServiceProvider).fetchCustomerProfile(customerId: customerId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(customerApiServiceProvider).fetchCustomerProfile(customerId: arg));
  }

  Future<bool> addRemark(String remark, {String priority = 'Normal'}) async {
    try {
      await ref.read(customerApiServiceProvider).addRemark(customerId: arg, remark: remark, priority: priority);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final customerProfileProvider =
    AsyncNotifierProvider.family<CustomerProfileNotifier, CustomerProfile, String>(
  CustomerProfileNotifier.new,
);
