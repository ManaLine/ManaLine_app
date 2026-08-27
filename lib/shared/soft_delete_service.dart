import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The record types `app.soft_delete_record` accepts. This is a CLOSED SET
/// on the server — anything else raises 22023 — so it is mirrored here as
/// an enum rather than passed around as a free string.
enum DeletableEntity {
  collection('collection', 'Collection'),
  loan('loan', 'Loan'),
  expense('expense', 'Expense'),
  chetiPayment('cheti_payment', 'Cheti Instalment'),
  cheti('cheti', 'Cheti'),
  investment('investment', 'Investment'),
  investmentWithdrawal('investment_withdrawal', 'Investor Withdrawal'),
  settlementAdjustment('settlement_adjustment', 'Settlement Adjustment'),
  cashTransfer('cash_transfer', 'Cash Transfer'),
  customerRemark('customer_remark', 'Customer Remark'),
  customerDocument('customer_document', 'Customer Document');

  final String wireName;
  final String label;
  const DeletableEntity(this.wireName, this.label);

  static DeletableEntity? fromWire(String w) {
    for (final e in DeletableEntity.values) {
      if (e.wireName == w) return e;
    }
    return null;
  }
}

/// One row in Recent Deletes.
class DeletedRecord {
  final DeletableEntity? entity;
  final String entityWireName;
  final String recordId;
  final String label;

  /// Null for records that carry no money (remarks, documents). Rendered as
  /// a dash, never as ₹0 — those are different claims.
  final int? amount;
  final DateTime? businessDate;
  final DateTime deletedAt;
  final String deletedBy;
  final String? reason;

  /// Days until the nightly purge removes it for good. 0 means it is due
  /// on the next run.
  final int daysLeft;

  DeletedRecord({
    required this.entity,
    required this.entityWireName,
    required this.recordId,
    required this.label,
    required this.amount,
    required this.businessDate,
    required this.deletedAt,
    required this.deletedBy,
    required this.reason,
    required this.daysLeft,
  });

  factory DeletedRecord.fromRow(Map<String, dynamic> r) {
    final wire = r['entity'] as String;
    return DeletedRecord(
      entity: DeletableEntity.fromWire(wire),
      entityWireName: wire,
      recordId: r['record_id'] as String,
      label: (r['label'] as String?) ?? wire,
      amount: (r['amount'] as num?)?.toInt(),
      businessDate: r['business_date'] == null
          ? null
          : DateTime.parse(r['business_date'] as String),
      deletedAt: DateTime.parse(r['deleted_at'] as String),
      deletedBy: (r['deleted_by'] as String?) ?? '—',
      reason: r['delete_reason'] as String?,
      daysLeft: (r['days_left'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Wraps the three soft-delete RPCs. Shared rather than duplicated per
/// workspace: the Owner and the Agent hit exactly the same functions, and
/// the permission difference is decided server-side by
/// app.may_delete_records, not by which service object was used.
class SoftDeleteService {
  SupabaseClient get _db => Supabase.instance.client;

  /// Marks the record deleted. Never a table delete: this is the only
  /// sanctioned path, and it is what writes the audit_log row and lets
  /// day_ledger recompute without the row.
  ///
  /// Returns the date it stops being recoverable.
  Future<DateTime> softDelete({
    required DeletableEntity entity,
    required String recordId,
    String? reason,
  }) async {
    final result = await _db.schema('app').rpc('soft_delete_record', params: {
      'p_entity': entity.wireName,
      'p_record_id': recordId,
      'p_reason': reason,
    });
    final map = result as Map<String, dynamic>;
    return DateTime.parse(map['recoverable_until'] as String);
  }

  Future<void> restore({
    required String entityWireName,
    required String recordId,
  }) async {
    await _db.schema('app').rpc('restore_record', params: {
      'p_entity': entityWireName,
      'p_record_id': recordId,
    });
  }

  /// Gone for good. There is no undo after this and the screen says so
  /// before calling it.
  ///
  /// The server refuses anything that is not ALREADY in the bin, so this
  /// cannot become a one-step destroy however it is called. Purging a loan
  /// takes its collections, schedule and penalties with it -- see
  /// app.purge_dependents, where what goes is written out rather than left to
  /// twenty foreign-key definitions.
  Future<void> purge({
    required String entityWireName,
    required String recordId,
  }) async {
    await _db.schema('app').rpc('purge_record', params: {
      'p_entity': entityWireName,
      'p_record_id': recordId,
    });
  }

  /// The bin. Must be an RPC: the restrictive RLS policies hide deleted
  /// rows from every ordinary table read, which is exactly what makes them
  /// vanish from the rest of the app.
  Future<List<DeletedRecord>> listRecentDeletes(String businessId) async {
    final rows = await _db
        .schema('app')
        .rpc('list_recent_deletes', params: {'p_business_id': businessId});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(DeletedRecord.fromRow)
        .toList();
  }
}

final softDeleteServiceProvider =
    Provider<SoftDeleteService>((ref) => SoftDeleteService());

/// Recent Deletes for one business. Family-keyed so two businesses cannot
/// share a cached bin.
final recentDeletesProvider =
    FutureProvider.family<List<DeletedRecord>, String>((ref, businessId) {
  return ref.read(softDeleteServiceProvider).listRecentDeletes(businessId);
});
