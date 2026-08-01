import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../owner_workspace/state/customer_state.dart'
    show CustomerSummary, CustomerLoanSummary, CustomerRemark, CustomerProfile;
import '../../../shared/mana_time.dart';

/// AG-004 Customer Management — real Supabase wiring, Agent-side
/// counterpart to OW-004 (owner_workspace/state/customer_state.dart).
/// Reuses that file's CustomerSummary/CustomerProfile shapes verbatim per
/// the original stub's own design note — the query logic here mirrors
/// customer_state.dart's fetchCustomers/fetchCustomerProfile (same schema
/// joins, same village/todaysDue/outstanding derivation and the same
/// KNOWN SIMPLIFICATION on lineRepaymentIndex), scoped by
/// assigned_agent_membership_id instead of just business_id.
///
/// CONSTRUCTOR CHANGE (this session): now takes a `Ref` — same
/// established pattern as `owner_workspace/state/investor_state.dart`'s
/// `InvestorApiService({required this.ref})` — so `addRemark` can read
/// `authFlowProvider.personId` for `entered_by_person_id` instead of
/// throwing UnimplementedError. This was the exact gap flagged in the
/// prior session's comment on `addRemark` below; fixed the same way the
/// Investor Workspace already fixed it, not invented fresh. The provider
/// definition at the bottom of this file is updated to pass `ref` in
/// accordingly. No other constructor/consumer outside this file needed
/// touching since `agentCustomerApiServiceProvider` is the only
/// construction site (screens consume the provider, never the class
/// directly) — but flagging per the briefing's "unless genuinely
/// required" instruction, since this is a constructor signature change.
class AgentCustomerApiService {
  final Ref ref;
  AgentCustomerApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  Future<List<CustomerSummary>> fetchAssignedCustomers({
    required String businessId,
    required String agentMembershipId,
  }) async {
    final rows = await _db
        .from('customers')
        .select('''
          customer_id, customer_status, membership_id,
          business_members!customers_membership_id_fkey!inner(business_id, membership_status),
          persons!inner(full_name, father_husband_name, mobile_number, mlid,
            person_addresses(village_id, is_current, locations(village_town_name))),
          loans(loan_id, loan_status, installment_amount, remaining_balance)
        ''')
        .eq('business_members.business_id', businessId)
        .eq('assigned_agent_membership_id', agentMembershipId);

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
        fullName: person['full_name'] as String? ?? '',
        fatherHusbandName: person['father_husband_name'] as String? ?? '',
        village: village,
        phoneNumber: person['mobile_number'] as String? ?? '',
        mlid: person['mlid'] as String? ?? '',
        activeLoanCount: activeLoans.length,
        todaysDue: todaysDue,
        outstandingBalance: outstanding,
        lineRepaymentIndex: 0, // see customer_state.dart's identical KNOWN SIMPLIFICATION note
        customerStatus: m['customer_status'] as String,
        membershipStatus: (m['business_members'] as Map<String, dynamic>)['membership_status'] as String,
      );
    }).toList();
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
          customer_remarks(remark_id, remark_text, priority, business_date)
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
    final loans = ((row['loans'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final activeLoans = loans.where((l) => ['Active', 'Grace Period', 'Penalty'].contains(l['loan_status']));
    final todaysDue = activeLoans.fold<double>(0, (sum, l) => sum + (l['installment_amount'] as num).toDouble());
    final outstanding = activeLoans.fold<double>(0, (sum, l) => sum + (l['remaining_balance'] as num).toDouble());

    return CustomerProfile(
      summary: CustomerSummary(
        customerId: row['customer_id'] as String,
        fullName: person['full_name'] as String? ?? '',
        fatherHusbandName: person['father_husband_name'] as String? ?? '',
        village: village,
        phoneNumber: person['mobile_number'] as String? ?? '',
        mlid: person['mlid'] as String? ?? '',
        activeLoanCount: activeLoans.length,
        todaysDue: todaysDue,
        outstandingBalance: outstanding,
        lineRepaymentIndex: 0,
        customerStatus: row['customer_status'] as String,
        membershipStatus: (row['business_members'] as Map<String, dynamic>)['membership_status'] as String,
      ),
      occupation: row['occupation'] as String?,
      address: village,
      customerSince: DateTime.parse(row['customer_since'] as String),
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
      collections: const [], // requires a separate collections query scoped per-loan — same simplification as customer_state.dart
      remarks: ((row['customer_remarks'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((r) => CustomerRemark(
                date: DateTime.parse(r['business_date'] as String),
                enteredBy: '',
                remark: r['remark_text'] as String,
                priority: r['priority'] as String,
              ))
          .toList(),
    );
  }

  /// Real write. `entered_by_person_id` now comes from
  /// `ref.read(authFlowProvider).personId` (see class-level constructor
  /// note) instead of being unimplemented. `business_date` has NO default
  /// in the schema (`customer_remarks.business_date DATE NOT NULL`, no
  /// `DEFAULT now()::date` unlike `created_at`) — defaults to today's
  /// calendar date here, matching the same "today, absent an explicit
  /// override" convention used elsewhere in this codebase (e.g.
  /// `customer_state.dart`'s `createCustomer` for `customer_since`).
  /// AG-004's own remark-reason list (`agentRemarkReasons` below) is
  /// passed through as `remark` free text by the caller, same as before —
  /// this method doesn't validate against that list; the picker UI is
  /// responsible for constraining it.
  Future<void> addRemark({required String customerId, required String remark, String priority = 'Normal'}) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      throw StateError('No logged-in person_id available — cannot set entered_by_person_id.');
    }
    final today = manaBusinessDate();
    await _db.from('customer_remarks').insert({
      'customer_id': customerId,
      'entered_by_person_id': int.parse(personId),
      'remark_text': remark,
      'priority': priority,
      'business_date': today,
    });
  }

  Future<void> uploadDocument({
    required String customerId,
    required String documentType,
    required String fileUrl,
  }) async {
    await _db.from('customer_documents').insert({
      'customer_id': customerId,
      'document_type': documentType,
      'file_url': fileUrl,
    });
  }

  /// BR-238 phone history now wired for real: `person_phone_history`
  /// (migration 0019) exists, so the phone half of this method follows
  /// the exact same close-old-row/insert-new-row pattern already
  /// established in `investor_workspace`/`customer_workspace`'s
  /// `updatePhone` (see `investor_profile_state.dart`) — close the
  /// current `person_phone_history` row (`to_date`/`is_current=false`),
  /// insert a new current row, then update the live
  /// `persons.mobile_number` column that the rest of the app reads from.
  ///
  /// `address` remains genuinely unimplemented — UNCHANGED from the prior
  /// flag: this method's own signature takes `address` as free text, but
  /// `person_addresses` is a structured row (door_no/pin_code/village_id/
  /// mandal/district/state) with no safe free-text-to-structured mapping.
  /// Fixing this needs the caller (AG-004 screen) to pass structured
  /// fields instead of one string — that's a signature change on a file
  /// FIXED (this pass, migration 0026): both phone and address now call
  /// SECURITY DEFINER RPCs — app.agent_update_customer_phone /
  /// app.agent_update_customer_address — gated on app.agent_covers_customer
  /// + can_edit_customer_contact, confirmed against the real permission
  /// column. This flag was correct: there really is no RLS policy anywhere
  /// in 0012-0018 granting an Agent UPDATE/INSERT on another person's
  /// persons/person_phone_history/person_addresses rows — the prior direct
  /// client-side writes would have failed under real RLS. Fixed the same
  /// way the equivalent Owner-side gap was fixed in 0021.
  ///
  /// address is now structured (mirrors owner_update_customer_address's
  /// param shape) rather than free text — the caller (AG-004 screen) must
  /// be updated to collect door_no/pin_code/village_id/mandal/district/
  /// state instead of one text field. This is a signature change, flagged
  /// per the "check for a signature change" convention established this
  /// session (WithdrawalRequestApiService, LoanDetailsApiService).
  Future<void> updateContactInfo({
    required String customerId,
    String? phoneNumber,
    String? doorNo,
    String? pinCode,
    String? villageId,
  }) async {
    if (phoneNumber != null) {
      await _db.schema('app').rpc('agent_update_customer_phone', params: {
        'p_customer_id': customerId,
        'p_phone_number': phoneNumber,
      });
    }
    if (villageId != null) {
      await _db.schema('app').rpc('agent_update_customer_address', params: {
        'p_customer_id': customerId,
        'p_door_no': doorNo,
        'p_pin_code': pinCode,
        'p_village_id': villageId,
      });
    }
  }

  Future<AgentPermissions> fetchPermissions({required String agentMembershipId}) async {
    final agentRow = await _db.from('agents').select('agent_id').eq('membership_id', agentMembershipId).single();
    final row = await _db
        .from('agent_permissions')
        .select()
        .eq('agent_id', agentRow['agent_id'])
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return const AgentPermissions();
    return AgentPermissions(
      canViewCustomers: row['can_view_customers'] as bool? ?? false,
      canCreateCustomer: row['can_create_customer'] as bool? ?? false,
      canIssueLoans: row['can_issue_loans'] as bool? ?? false,
      canUploadDocuments: row['can_upload_documents'] as bool? ?? false,
      canEditCustomerContact: row['can_edit_customer_contact'] as bool? ?? false,
      canAddRemarks: row['can_add_remarks'] as bool? ?? false,
      canCollectPayments: row['can_collect_payments'] as bool? ?? false,
    );
  }
}

final agentCustomerApiServiceProvider = Provider<AgentCustomerApiService>((ref) {
  return AgentCustomerApiService(ref: ref);
});

// ============================================================================
// Models
// ============================================================================

class AgentPermissions {
  final bool canViewCustomers;
  final bool canCreateCustomer;
  final bool canIssueLoans;
  final bool canUploadDocuments;
  final bool canEditCustomerContact;
  final bool canAddRemarks;
  final bool canCollectPayments;

  const AgentPermissions({
    this.canViewCustomers = false,
    this.canCreateCustomer = false,
    this.canIssueLoans = false,
    this.canUploadDocuments = false,
    this.canEditCustomerContact = false,
    this.canAddRemarks = false,
    this.canCollectPayments = false,
  });
}

enum AgentDocumentType { customerPhoto, addressPhoto, identityProof, other }

extension AgentDocumentTypeLabel on AgentDocumentType {
  String get displayLabel => switch (this) {
        AgentDocumentType.customerPhoto => 'Customer Photo',
        AgentDocumentType.addressPhoto => 'Address Photo',
        AgentDocumentType.identityProof => 'Identity Proof',
        AgentDocumentType.other => 'Other Documents',
      };
}

const List<String> agentRemarkReasons = [
  'Customer Requested Visit Tomorrow',
  'Customer Shifted House',
  'Customer Requested Extension',
  'Address Changed',
  'Phone Number Changed',
  'Seasonal Business Closed',
  'Other',
];

// ============================================================================
// State — Customer List (S1)
// ============================================================================

List<CustomerSummary> _applySort(List<CustomerSummary> list) {
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

class AgentCustomerListState {
  final List<CustomerSummary> customers;
  final bool loading;
  final String? error;
  final AgentPermissions permissions;

  final String? villageFilter;
  final String? loanStatusFilter;
  final String searchQuery;

  const AgentCustomerListState({
    this.customers = const [],
    this.loading = false,
    this.error,
    this.permissions = const AgentPermissions(),
    this.villageFilter,
    this.loanStatusFilter,
    this.searchQuery = '',
  });

  List<CustomerSummary> get filtered {
    var list = customers;
    if (villageFilter != null) list = list.where((c) => c.village == villageFilter).toList();
    if (loanStatusFilter == 'HasDue') {
      // BUG FIXED this pass: was comparing c.customerStatus (Active/
      // Inactive/Deceased) against the literal 'HasDue', which can never
      // match — the "today's due" chip silently showed "no customers
      // match this view" for every Agent regardless of real dues.
      list = list.where((c) => c.todaysDue > 0).toList();
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
    return _applySort(list);
  }

  List<String> get villages => customers.map((c) => c.village).toSet().toList()..sort();

  AgentCustomerListState copyWith({
    List<CustomerSummary>? customers,
    bool? loading,
    String? error,
    bool clearError = false,
    AgentPermissions? permissions,
    String? villageFilter,
    bool clearVillageFilter = false,
    String? loanStatusFilter,
    bool clearLoanStatusFilter = false,
    String? searchQuery,
  }) {
    return AgentCustomerListState(
      customers: customers ?? this.customers,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      permissions: permissions ?? this.permissions,
      villageFilter: clearVillageFilter ? null : (villageFilter ?? this.villageFilter),
      loanStatusFilter: clearLoanStatusFilter ? null : (loanStatusFilter ?? this.loanStatusFilter),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class AgentCustomerListNotifier extends Notifier<AgentCustomerListState> {
  @override
  AgentCustomerListState build() => const AgentCustomerListState();

  Future<void> load({required String businessId, required String agentMembershipId}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(agentCustomerApiServiceProvider);
      final results = await Future.wait([
        api.fetchAssignedCustomers(businessId: businessId, agentMembershipId: agentMembershipId),
        api.fetchPermissions(agentMembershipId: agentMembershipId),
      ]);
      state = state.copyWith(
        customers: results[0] as List<CustomerSummary>,
        permissions: results[1] as AgentPermissions,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setSearchQuery(String q) => state = state.copyWith(searchQuery: q);
  void setVillageFilter(String? v) =>
      state = v == null ? state.copyWith(clearVillageFilter: true) : state.copyWith(villageFilter: v);
  void setLoanStatusFilter(String? s) =>
      state = s == null ? state.copyWith(clearLoanStatusFilter: true) : state.copyWith(loanStatusFilter: s);
}

final agentCustomerListProvider = NotifierProvider<AgentCustomerListNotifier, AgentCustomerListState>(
  AgentCustomerListNotifier.new,
);

// ============================================================================
// State — Customer Profile (S2/S3)
// ============================================================================

class AgentCustomerProfileNotifier extends FamilyAsyncNotifier<CustomerProfile, String> {
  @override
  Future<CustomerProfile> build(String customerId) async {
    return ref.read(agentCustomerApiServiceProvider).fetchCustomerProfile(customerId: customerId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(agentCustomerApiServiceProvider).fetchCustomerProfile(customerId: arg),
    );
  }

  Future<bool> addRemark(String remark, {String priority = 'Normal'}) async {
    try {
      await ref.read(agentCustomerApiServiceProvider).addRemark(customerId: arg, remark: remark, priority: priority);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> uploadDocument({required AgentDocumentType documentType, required String fileUrl}) async {
    try {
      await ref.read(agentCustomerApiServiceProvider).uploadDocument(
            customerId: arg,
            documentType: documentType.displayLabel,
            fileUrl: fileUrl,
          );
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateContactInfo({
    String? phoneNumber,
    String? doorNo,
    String? pinCode,
    String? villageId,
  }) async {
    try {
      await ref.read(agentCustomerApiServiceProvider).updateContactInfo(
            customerId: arg,
            phoneNumber: phoneNumber,
            doorNo: doorNo,
            pinCode: pinCode,
            villageId: villageId,
          );
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final agentCustomerProfileProvider =
    AsyncNotifierProvider.family<AgentCustomerProfileNotifier, CustomerProfile, String>(
  AgentCustomerProfileNotifier.new,
);
