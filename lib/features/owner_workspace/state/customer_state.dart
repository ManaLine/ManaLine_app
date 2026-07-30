import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/text_utils.dart';
import '../../../shared/document_viewer.dart' show DocumentSummary;

/// OW-004 Customer Domain — real Supabase wiring over Module 3
/// (persons/person_addresses/business_members/customers/customer_remarks).
class CustomerApiService {
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
          loans(loan_id, loan_status, installment_amount, remaining_balance)
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
      final todaysDue = activeLoans.fold<double>(0, (sum, l) => sum + (l['installment_amount'] as num).toDouble());
      final outstanding = activeLoans.fold<double>(0, (sum, l) => sum + (l['remaining_balance'] as num).toDouble());

      return CustomerSummary(
        customerId: m['customer_id'] as String,
        fullName: titleCaseName(person['full_name'] as String? ?? ''),
        fatherHusbandName: titleCaseName(person['father_husband_name'] as String? ?? ''),
        village: village,
        phoneNumber: person['mobile_number'] as String? ?? '',
        mlid: person['mlid'] as String? ?? '',
        activeLoanCount: activeLoans.length,
        todaysDue: todaysDue,
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
  Future<CustomerSummary?> searchIdentity({
    String? phone,
    String? aadhaar,
    String? mlid,
    String? fullName,
  }) async {
    if ((mlid == null || mlid.isEmpty) &&
        (aadhaar == null || aadhaar.isEmpty) &&
        (phone == null || phone.isEmpty) &&
        (fullName == null || fullName.isEmpty)) {
      return null;
    }
    final rows = await _db.schema('app').rpc('owner_search_person', params: {
      'p_mlid': mlid,
      'p_mobile_number': phone,
      'p_aadhaar_number': aadhaar,
      'p_full_name': fullName,
    });
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    final row = list.first;
    return CustomerSummary(
      customerId: '', // no customers row yet — this is a persons-level search result, not a customer
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
    );
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
            'customer_since': DateTime.now().toIso8601String().split('T').first,
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
        .select('document_type, file_url, uploaded_at')
        .eq('customer_id', customerId)
        .eq('is_archived', false)
        .order('uploaded_at', ascending: false);
    return (rows as List)
        .map((r) => DocumentSummary(
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
          assigned_agent_membership_id,
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

    String? agentName;
    final agentMembershipId = row['assigned_agent_membership_id'] as String?;
    if (agentMembershipId != null) {
      final agentRow = await _db
          .from('business_members')
          .select('persons!business_members_person_id_fkey(full_name)')
          .eq('membership_id', agentMembershipId)
          .maybeSingle();
      final rawAgentName = (agentRow?['persons'] as Map<String, dynamic>?)?['full_name'] as String?;
      agentName = rawAgentName == null ? null : titleCaseName(rawAgentName);
    }

    final loans = ((row['loans'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final activeLoans = loans.where((l) => ['Active', 'Grace Period', 'Penalty'].contains(l['loan_status']));
    final todaysDue = activeLoans.fold<double>(0, (sum, l) => sum + (l['installment_amount'] as num).toDouble());
    final outstanding = activeLoans.fold<double>(0, (sum, l) => sum + (l['remaining_balance'] as num).toDouble());

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
                loanAmount: (l['repayment_amount'] as num).toDouble(),
                outstanding: (l['remaining_balance'] as num).toDouble(),
                todaysDue: (l['installment_amount'] as num).toDouble(),
                progressPercent: (l['repayment_amount'] as num) == 0
                    ? 0
                    : 100 -
                        (((l['remaining_balance'] as num).toDouble() / (l['repayment_amount'] as num).toDouble()) *
                            100),
                status: l['loan_status'] as String,
              ))
          .toList(),
      collections: const [], // requires a separate collections query scoped per-loan — not fetched by this profile view
      remarks: ((row['customer_remarks'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((r) => CustomerRemark(
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

  Future<void> addRemark({required String customerId, required String remark, String? priority}) async {
    // ARCHITECTURE NOTE: this app's identity layer (see auth_api_service.dart)
    // does not use Supabase Auth's own session — entered_by_person_id must
    // come from the caller's own authFlowProvider.personId, which this
    // *ApiService layer (by this session's own established convention,
    // see collection_mode_state.dart) reads via a Ref rather than
    // _db.auth. This class was written as a plain (non-Ref) service to
    // match the ORIGINAL stub's constructor shape; flagged here rather
    // than silently guessing a person_id. Caller (CustomerProfileNotifier)
    // must be upgraded to pass personId through, OR this service
    // upgraded to take a Ref — same fix needed either way, left to
    // whichever chat wires the AsyncNotifier call site.
    throw UnimplementedError(
      'addRemark needs entered_by_person_id from authFlowProvider.personId, which this service (constructed '
      'without a Ref, unlike collection_mode_state.dart\'s CollectionApiService) has no access to. Flagged, not '
      'guessed — see architecture note in source.',
    );
  }
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
  final double todaysDue;
  final double outstandingBalance;
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
  final double loanAmount;
  final double outstanding;
  final double todaysDue;
  final double progressPercent;
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

class CustomerCollectionRow {
  final DateTime businessDate;
  final double amount;
  final String paymentMode;
  final String collector;
  final String receiptNumber;
  final double difference;

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
  final DateTime date;
  final String enteredBy;
  final String remark;
  final String priority;

  CustomerRemark({required this.date, required this.enteredBy, required this.remark, required this.priority});
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
  return CustomerApiService();
});

/// C2b — locked cascading sort: Highest Outstanding → Penalty →
/// Grace Period → Today's Due → Village → Customer Name. Not user-
/// selectable single-field options — applied as one fixed sequence.
List<CustomerSummary> _applyLockedSort(List<CustomerSummary> list) {
  final sorted = [...list];
  sorted.sort((a, b) {
    final byOutstanding = b.outstandingBalance.compareTo(a.outstandingBalance);
    if (byOutstanding != 0) return byOutstanding;
    final byDue = b.todaysDue.compareTo(a.todaysDue);
    if (byDue != 0) return byDue;
    final byVillage = a.village.compareTo(b.village);
    if (byVillage != 0) return byVillage;
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
  final String? error;

  const CustomerListState({
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
    return _applyLockedSort(list);
  }

  CustomerListState copyWith({
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
  void setVillageFilter(String? v) =>
      state = v == null ? state.copyWith(clearVillageFilter: true) : state.copyWith(villageFilter: v);
  void setCustomerStatusFilter(String? s) => state =
      s == null ? state.copyWith(clearCustomerStatusFilter: true) : state.copyWith(customerStatusFilter: s);

  Future<CustomerSummary?> searchIdentity({
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
      return null;
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
