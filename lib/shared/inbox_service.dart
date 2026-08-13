/// The shared Notifications inbox, for every workspace.
///
/// WHY THIS EXISTS: invitations were scattered across OW-002, OW-003, OW-012,
/// LR-012, CW-002 and IW-002, and the only notifications screen in the app was
/// AG-008 — agent-only. There was no one place to see what was waiting on you.
///
/// Two kinds of thing live here and they are NOT the same:
///
///   ACTIONABLE  read live from app.my_inbox_actions(). Membership requests
///               awaiting your approval as an Owner, and invitations awaiting
///               your acceptance. Deliberately not copied into the
///               notifications table — a row would need a trigger and would go
///               stale the moment the request was decided elsewhere, and an
///               inbox insisting something is pending after it was approved is
///               worse than no inbox.
///
///   FEED        the notifications table. Already per-person
///               (recipient_person_id) with is_read, so it works unchanged for
///               every workspace, not just agents.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which decision an actionable item is asking for.
///
/// The two are shown in separate sections because the verbs mean opposite
/// things: approving lets someone into a business you own; accepting puts you
/// into someone else's. Two identical-looking buttons doing those two things
/// would be a genuinely dangerous UI.
enum InboxActionKind {
  /// Someone asked to join a business you own — approve or reject.
  approval('approval'),

  /// A business added you and is waiting — accept or decline.
  invitation('invitation');

  const InboxActionKind(this.wire);
  final String wire;

  static InboxActionKind fromWire(String v) => InboxActionKind.values.firstWhere(
        (k) => k.wire == v,
        orElse: () => throw ArgumentError('Unknown inbox action kind: $v'),
      );
}

class InboxAction {
  final InboxActionKind kind;

  /// request_id for an approval, membership_id for an invitation.
  final String itemId;
  final String businessId;
  final String businessName;

  /// Who is asking. Null on an invitation — that one is about you.
  final String? personName;
  final String role;

  /// Proposed investment, when an investor is asking to join. Whole rupees.
  final int? amount;
  final DateTime createdAt;

  const InboxAction({
    required this.kind,
    required this.itemId,
    required this.businessId,
    required this.businessName,
    required this.role,
    required this.createdAt,
    this.personName,
    this.amount,
  });

  factory InboxAction.fromRow(Map<String, dynamic> r) => InboxAction(
        kind: InboxActionKind.fromWire(r['kind'] as String),
        itemId: r['item_id'] as String,
        businessId: r['business_id'] as String,
        businessName: (r['business_name'] as String?) ?? '',
        personName: r['person_name'] as String?,
        role: (r['role'] as String?) ?? '',
        amount: (r['amount'] as num?)?.round(),
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}

class InboxNotice {
  final String id;
  final String type;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  const InboxNotice({
    required this.id,
    required this.type,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory InboxNotice.fromRow(Map<String, dynamic> r) => InboxNotice(
        id: r['notification_id'] as String,
        type: (r['notification_type'] as String?) ?? 'Other',
        message: (r['message'] as String?) ?? '',
        isRead: r['is_read'] as bool? ?? false,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}

class InboxService {
  InboxService(this._db);
  final SupabaseClient _db;

  /// `.schema('app')` is required — a bare `.rpc()` targets public and 404s.
  Future<List<InboxAction>> pendingActions() async {
    final rows = await _db.schema('app').rpc('my_inbox_actions');
    return (rows as List).cast<Map<String, dynamic>>().map(InboxAction.fromRow).toList();
  }

  /// The read-only feed. Not scoped to a business on purpose: this inbox is
  /// per person, and someone who is an Agent in one business and a Customer
  /// in another should see both without switching workspace first.
  Future<List<InboxNotice>> notices({int limit = 100}) async {
    final rows = await _db
        .from('notifications')
        .select('notification_id, notification_type, message, is_read, created_at')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>().map(InboxNotice.fromRow).toList();
  }

  Future<void> markRead(String notificationId) async {
    await _db
        .from('notifications')
        .update({'is_read': true})
        .eq('notification_id', notificationId);
  }

  /// PostgREST needs a filter; `.neq('is_read', true)` is the "all mine that
  /// are unread" form, with RLS already limiting the rows to this person.
  Future<void> markAllRead() async {
    await _db.from('notifications').update({'is_read': true}).neq('is_read', true);
  }

  Future<bool> decideRequest({
    required String requestId,
    required bool approve,
    String? rejectionReason,
  }) async {
    await _db.from('membership_requests').update({
      'status': approve ? 'Approved' : 'Rejected',
      'rejection_reason': rejectionReason,
    }).eq('request_id', requestId);
    return true;
  }

  /// Accepting activates the membership; declining marks it Removed rather
  /// than deleting the row, so the business can see it was declined instead of
  /// the invitation silently vanishing.
  Future<bool> respondToInvitation({
    required String membershipId,
    required bool accept,
  }) async {
    await _db.from('business_members').update({
      'membership_status': accept ? 'Active' : 'Removed',
    }).eq('membership_id', membershipId);
    return true;
  }
}

final inboxServiceProvider =
    Provider<InboxService>((ref) => InboxService(Supabase.instance.client));
