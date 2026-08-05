import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// P4 Business Transfer — offers made and offers received.
///
/// Every rule lives in the database (app.assert_business_transferable and the
/// three RPCs). This class carries requests and results, and deliberately
/// re-checks nothing: a client-side copy of "can this business be transferred"
/// would drift from the server's, and the server's is the one that decides.
class BusinessTransferApiService {
  BusinessTransferApiService(this._db);
  final SupabaseClient _db;

  Future<List<BusinessTransfer>> list() async {
    final rows = await _db.schema('app').rpc('my_business_transfers');
    return [
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        BusinessTransfer.fromRow(r),
    ];
  }

  /// Resolves an MLID to a person. Reuses the RPC OW-002's "Add Existing
  /// Agent" already uses, rather than adding a second way to find someone.
  Future<TransferCandidate?> findByMlid(String mlid) async {
    final rows = await _db
        .schema('app')
        .rpc('owner_search_person_by_mlid', params: {'p_mlid': mlid.trim()});
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    final r = list.first;
    return TransferCandidate(
      personId: (r['person_id'] as num).toInt(),
      fullName: (r['full_name'] ?? '').toString(),
      mlid: (r['mlid'] ?? '').toString(),
      mobile: (r['mobile_number'] ?? '').toString(),
    );
  }

  Future<void> offer({
    required String businessId,
    required int toPersonId,
    String? note,
  }) async {
    await _db.schema('app').rpc('request_business_transfer', params: {
      'p_business_id': businessId,
      'p_to_person_id': toPersonId,
      'p_note': note,
    });
  }

  Future<void> respond({
    required String transferId,
    required bool accept,
    String? reason,
  }) async {
    await _db.schema('app').rpc('respond_business_transfer', params: {
      'p_transfer_id': transferId,
      'p_accept': accept,
      'p_reason': reason,
    });
  }

  Future<void> cancel(String transferId) async {
    await _db.schema('app').rpc('cancel_business_transfer', params: {
      'p_transfer_id': transferId,
    });
  }
}

class TransferCandidate {
  final int personId;
  final String fullName;
  final String mlid;
  final String mobile;
  const TransferCandidate({
    required this.personId,
    required this.fullName,
    required this.mlid,
    required this.mobile,
  });
}

class BusinessTransfer {
  final String transferId;
  final String businessId;
  final String businessName;
  final String mlbi;

  /// 'outgoing' when the caller is handing the business over, 'incoming' when
  /// it is being offered to them. The two read very differently on screen, so
  /// the server decides which it is rather than the client comparing ids.
  final String direction;
  final String counterparty;
  final String counterpartyMlid;
  final String status;
  final String? note;
  final String? declineReason;

  const BusinessTransfer({
    required this.transferId,
    required this.businessId,
    required this.businessName,
    required this.mlbi,
    required this.direction,
    required this.counterparty,
    required this.counterpartyMlid,
    required this.status,
    this.note,
    this.declineReason,
  });

  bool get isPending => status == 'Pending';
  bool get isIncoming => direction == 'incoming';

  factory BusinessTransfer.fromRow(Map<String, dynamic> r) => BusinessTransfer(
        transferId: r['transfer_id'].toString(),
        businessId: r['business_id'].toString(),
        businessName: (r['business_name'] ?? '').toString(),
        mlbi: (r['mlbi'] ?? '').toString(),
        direction: (r['direction'] ?? '').toString(),
        counterparty: (r['counterparty'] ?? '').toString(),
        counterpartyMlid: (r['counterparty_mlid'] ?? '').toString(),
        status: (r['status'] ?? '').toString(),
        note: r['note'] as String?,
        declineReason: r['decline_reason'] as String?,
      );
}

final businessTransferApiServiceProvider = Provider<BusinessTransferApiService>(
  (ref) => BusinessTransferApiService(Supabase.instance.client),
);

final businessTransfersProvider =
    FutureProvider<List<BusinessTransfer>>((ref) async {
  return ref.read(businessTransferApiServiceProvider).list();
});
