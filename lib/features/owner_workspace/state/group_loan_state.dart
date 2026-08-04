import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';

/// OW-015 Group Loan Management — real Supabase wiring.
///
/// GAP RESOLVED (this session): the original stub flagged every method as
/// "unconfirmed shape only" because 04_API_Specification_v1 Parts 1-4B
/// never got a Group Loan addendum. That's still true of the REST-spec
/// docs, but the actual delivered schema (0007_module6_loan_domain.sql)
/// DOES have real `loan_groups`/`loan_group_members` tables with a
/// confirmed shape — group_name, created_by_membership_id, and a plain
/// membership join table with no per-row status of its own (BUSINESS
/// RULES: "One member's Penalty/Default status has zero effect on
/// others" — membership itself carries no state, only the referenced
/// loan does). Wired directly against those tables.
class GroupLoanApiService {
  final Ref ref;
  GroupLoanApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  Future<List<GroupSummary>> fetchGroups({required String businessId}) async {
    final rows = await _db
        .from('loan_groups')
        .select('group_id, group_name, loan_group_members(group_member_id)')
        .eq('business_id', businessId);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return GroupSummary(
        groupId: m['group_id'] as String,
        groupName: m['group_name'] as String,
        memberCount: ((m['loan_group_members'] as List?) ?? const []).length,
      );
    }).toList();
  }

  /// Any individual loan in this business not already a member of a group
  /// is eligible, per spec's own Create Group step 2 ("any status"). Where
  /// businesses.allow_multi_group_membership is FALSE (app-layer toggle,
  /// per the schema's own COMMENT ON loan_group_members), loans already in
  /// a group are excluded here — this IS enforced client-side since
  /// there's no DB constraint backing it (documented as app-layer only).
  Future<List<GroupMemberLoan>> searchEligibleLoans({required String businessId, String? query}) async {
    final biz = await _db
        .from('businesses')
        .select('allow_multi_group_membership')
        .eq('business_id', businessId)
        .single();
    final allowMulti = biz['allow_multi_group_membership'] as bool? ?? false;

    var q = _db
        .from('loans')
        .select('loan_id, loan_number, remaining_balance, installment_amount, loan_status, '
            'customers!inner(persons!inner(full_name)), loan_group_members(group_member_id)')
        .eq('business_id', businessId);
    if (query != null && query.trim().isNotEmpty) {
      q = q.ilike('loan_number', '%${query.trim()}%');
    }
    final rows = await q;

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) => allowMulti || ((r['loan_group_members'] as List?) ?? const []).isEmpty)
        .map((r) => GroupMemberLoan(
              loanId: r['loan_id'] as String,
              customerName: ((r['customers'] as Map<String, dynamic>)['persons'] as Map<String, dynamic>)['full_name']
                      as String? ??
                  '',
              loanNumber: r['loan_number'] as String,
              remainingBalance: (r['remaining_balance'] as num).toInt(),
              installmentAmount: (r['installment_amount'] as num).toInt(),
              status: r['loan_status'] as String,
            ))
        .toList();
  }

  Future<String> createGroup({
    required String businessId,
    required String groupName,
    required List<String> memberLoanIds,
  }) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) throw StateError('No logged-in person_id available.');
    final memberRow = await _db
        .from('business_members')
        .select('membership_id')
        .eq('person_id', int.parse(personId))
        .eq('business_id', businessId)
        .eq('membership_status', 'Active')
        .inFilter('role', ['Owner', 'Agent'])
        .limit(1)
        .single();
    final membershipId = memberRow['membership_id'] as String;

    final groupRow = await _db
        .from('loan_groups')
        .insert({
          'business_id': businessId,
          'group_name': groupName,
          'created_by_membership_id': membershipId,
        })
        .select('group_id')
        .single();
    final groupId = groupRow['group_id'] as String;

    if (memberLoanIds.isNotEmpty) {
      await _db.from('loan_group_members').insert(
            memberLoanIds.map((loanId) => {'group_id': groupId, 'loan_id': loanId}).toList(),
          );
    }
    return groupId;
  }

  Future<GroupLoanDetail> fetchGroupDetail({required String groupId}) async {
    final row = await _db
        .from('loan_groups')
        .select('group_id, group_name, loan_group_members(loans(loan_id, loan_number, remaining_balance, '
            'installment_amount, loan_status, customers!inner(persons!inner(full_name))))')
        .eq('group_id', groupId)
        .single();

    final members = ((row['loan_group_members'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((gm) {
          final l = gm['loans'] as Map<String, dynamic>;
          return GroupMemberLoan(
            loanId: l['loan_id'] as String,
            customerName:
                ((l['customers'] as Map<String, dynamic>)['persons'] as Map<String, dynamic>)['full_name'] as String? ??
                    '',
            loanNumber: l['loan_number'] as String,
            remainingBalance: (l['remaining_balance'] as num).toInt(),
            installmentAmount: (l['installment_amount'] as num).toInt(),
            status: l['loan_status'] as String,
          );
        })
        .toList();

    return GroupLoanDetail(
      summary: GroupSummary(groupId: row['group_id'] as String, groupName: row['group_name'] as String, memberCount: members.length),
      members: members,
    );
  }

  Future<void> renameGroup({required String groupId, required String newName}) async {
    await _db.from('loan_groups').update({'group_name': newName}).eq('group_id', groupId);
  }

  /// Gated on Group Balance = ₹0 by the UI already (per spec's own note);
  /// the delete itself only needs the group_members rows removed then the
  /// group row — member loans themselves are never touched, only the
  /// grouping association.
  Future<void> deleteGroup({required String groupId}) async {
    await _db.from('loan_group_members').delete().eq('group_id', groupId);
    await _db.from('loan_groups').delete().eq('group_id', groupId);
  }
}

final groupLoanApiServiceProvider = Provider<GroupLoanApiService>((ref) {
  return GroupLoanApiService(ref: ref);
});

class GroupSummary {
  final String groupId;
  final String groupName;
  final int memberCount;
  GroupSummary({required this.groupId, required this.groupName, required this.memberCount});
}

/// Shared shape for both the "eligible loan" search results (Create
/// Group step 2) and each member row in Group Detail — same underlying
/// per-loan data either way.
class GroupMemberLoan {
  final String loanId;
  final String customerName;
  final String loanNumber;
  final int remainingBalance;
  final int installmentAmount;
  final String status;
  GroupMemberLoan({
    required this.loanId,
    required this.customerName,
    required this.loanNumber,
    required this.remainingBalance,
    required this.installmentAmount,
    required this.status,
  });
}

class GroupLoanDetail {
  final GroupSummary summary;
  final List<GroupMemberLoan> members;

  GroupLoanDetail({required this.summary, this.members = const []});

  // Group Balance/EMI are always computed live from member loans, never
  // stored — no reconciliation risk between a stored total and the
  // member loans (spec's own BUSINESS RULES).
  int get groupBalance => members.fold(0, (sum, m) => sum + m.remainingBalance);
  int get groupEmi => members.fold(0, (sum, m) => sum + m.installmentAmount);

  // Deletion gated on Group Balance = ₹0 — every member loan fully
  // paid/Closed.
  bool get eligibleForDeletion => groupBalance <= 0;
}

class GroupLoanListState {
  final List<GroupSummary> groups;
  final bool loading;
  final String? error;

  const GroupLoanListState({this.groups = const [], this.loading = false, this.error});

  GroupLoanListState copyWith({
    List<GroupSummary>? groups,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return GroupLoanListState(
      groups: groups ?? this.groups,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class GroupLoanListNotifier extends Notifier<GroupLoanListState> {
  @override
  GroupLoanListState build() => const GroupLoanListState();

  Future<void> load(String businessId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(groupLoanApiServiceProvider);
      final groups = await api.fetchGroups(businessId: businessId);
      state = state.copyWith(groups: groups, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<List<GroupMemberLoan>> searchEligibleLoans(String businessId, {String? query}) async {
    try {
      final api = ref.read(groupLoanApiServiceProvider);
      return await api.searchEligibleLoans(businessId: businessId, query: query);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return const [];
    }
  }

  Future<bool> createGroup({
    required String businessId,
    required String groupName,
    required List<String> memberLoanIds,
  }) async {
    try {
      final api = ref.read(groupLoanApiServiceProvider);
      await api.createGroup(businessId: businessId, groupName: groupName, memberLoanIds: memberLoanIds);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final groupLoanListProvider = NotifierProvider<GroupLoanListNotifier, GroupLoanListState>(
  GroupLoanListNotifier.new,
);

class GroupLoanDetailNotifier extends FamilyAsyncNotifier<GroupLoanDetail, String> {
  @override
  Future<GroupLoanDetail> build(String groupId) async {
    return ref.read(groupLoanApiServiceProvider).fetchGroupDetail(groupId: groupId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(groupLoanApiServiceProvider).fetchGroupDetail(groupId: arg));
  }

  Future<bool> rename(String newName) async {
    try {
      await ref.read(groupLoanApiServiceProvider).renameGroup(groupId: arg, newName: newName);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteGroup() async {
    try {
      await ref.read(groupLoanApiServiceProvider).deleteGroup(groupId: arg);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final groupLoanDetailProvider = AsyncNotifierProvider.family<GroupLoanDetailNotifier, GroupLoanDetail, String>(
  GroupLoanDetailNotifier.new,
);
