import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AG-010 Transaction History (new this batch) — the 4th footer nav tab,
/// parity with the Owner side's request for "same nav bar throughout."
/// Shows THIS Agent's own recorded collections on THIS business only —
/// not every collection at the business (that's OW-009 Daily Record
/// Book's job, an Owner-only screen this file does not touch or
/// duplicate).
///
/// RLS NOTE: `collections_agent_select_assigned` already restricts what
/// an Agent can see at all to customers they currently cover
/// (`app.agent_covers_customer`) — the explicit
/// `.eq('collected_by_membership_id', agentId)` filter below is an
/// ADDITIONAL narrowing on top of that, for "did I personally record
/// this" rather than "am I currently assigned to this customer." Both
/// conditions together are what makes this genuinely "MY transaction
/// history" rather than "my current customers' full history."
class AgentHistoryApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<AgentTransactionEntry>> fetchHistory({
    required String businessId,
    required String agentMembershipId,
  }) async {
    final rows = await _db
        .from('collections')
        .select('collection_id, collected_amount, business_date, entry_timestamp, receipt_number, '
            'result_type, remarks, loans!inner(loan_number, business_id), '
            'customers(persons(full_name))')
        .eq('collected_by_membership_id', agentMembershipId)
        .eq('loans.business_id', businessId)
        .order('entry_timestamp', ascending: false)
        .limit(100);

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final loan = r['loans'] as Map<String, dynamic>?;
      final customer = r['customers'] as Map<String, dynamic>?;
      final person = customer?['persons'] as Map<String, dynamic>?;
      return AgentTransactionEntry(
        collectionId: r['collection_id'] as String,
        customerName: person?['full_name'] as String? ?? 'Unknown Customer',
        loanNumber: loan?['loan_number'] as String? ?? '—',
        amount: (r['collected_amount'] as num).toDouble(),
        resultType: r['result_type'] as String? ?? 'Full',
        receiptNumber: r['receipt_number'] as String?,
        remarks: r['remarks'] as String?,
        businessDate: DateTime.parse(r['business_date'] as String),
        entryTimestamp: DateTime.parse(r['entry_timestamp'] as String),
      );
    }).toList();
  }
}

final agentHistoryApiServiceProvider = Provider<AgentHistoryApiService>((ref) {
  return AgentHistoryApiService();
});

// ============================================================================
// Models
// ============================================================================

class AgentTransactionEntry {
  final String collectionId;
  final String customerName;
  final String loanNumber;
  final double amount;
  final String resultType; // 'Full' | 'Partial' | 'Excess' | 'No Collection' etc.
  final String? receiptNumber;
  final String? remarks;
  final DateTime businessDate;
  final DateTime entryTimestamp;

  AgentTransactionEntry({
    required this.collectionId,
    required this.customerName,
    required this.loanNumber,
    required this.amount,
    required this.resultType,
    this.receiptNumber,
    this.remarks,
    required this.businessDate,
    required this.entryTimestamp,
  });
}

// ============================================================================
// State
// ============================================================================

class AgentHistoryState {
  final bool loading;
  final List<AgentTransactionEntry> entries;
  final String? error;

  const AgentHistoryState({this.loading = false, this.entries = const [], this.error});

  double get totalCollected => entries.fold<double>(0, (sum, e) => sum + e.amount);

  AgentHistoryState copyWith({
    bool? loading,
    List<AgentTransactionEntry>? entries,
    String? error,
    bool clearError = false,
  }) {
    return AgentHistoryState(
      loading: loading ?? this.loading,
      entries: entries ?? this.entries,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AgentHistoryNotifier extends Notifier<AgentHistoryState> {
  @override
  AgentHistoryState build() => const AgentHistoryState();

  Future<void> load({required String businessId, required String agentMembershipId}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(agentHistoryApiServiceProvider);
      final entries = await api.fetchHistory(businessId: businessId, agentMembershipId: agentMembershipId);
      state = state.copyWith(loading: false, entries: entries);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final agentHistoryProvider = NotifierProvider<AgentHistoryNotifier, AgentHistoryState>(
  AgentHistoryNotifier.new,
);
