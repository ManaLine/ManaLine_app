import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AG-008 Notifications — real Supabase wiring. RLS
/// (`notifications_self_select`) already scopes every query to
/// `recipient_person_id = current person` — no explicit person_id filter
/// needed client-side, matching the spec's own reasoning that the server
/// never writes a row against the wrong recipient.
class NotificationsApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<AgentNotification>> fetchNotifications({
    required String businessId,
    bool? isRead,
    AgentNotificationType? notificationType,
  }) async {
    var q = _db
        .from('notifications')
        .select('notification_id, notification_type, message, related_entity_type, '
            'related_entity_id, created_at, is_read')
        .eq('business_id', businessId);
    if (isRead != null) q = q.eq('is_read', isRead);
    final rows = await q.order('created_at', ascending: false);
    return (rows as List).map((r) => _fromRow(r as Map<String, dynamic>)).toList();
  }

  Future<AgentNotification> fetchNotification({required String notificationId}) async {
    final row = await _db
        .from('notifications')
        .select('notification_id, notification_type, message, related_entity_type, '
            'related_entity_id, created_at, is_read')
        .eq('notification_id', notificationId)
        .single();
    return _fromRow(row);
  }

  Future<void> markRead({required String notificationId}) async {
    await _db.from('notifications').update({'is_read': true}).eq('notification_id', notificationId);
  }

  /// Scoped to this business by the filter, and to this PERSON by RLS —
  /// notifications_self_update_read restricts every UPDATE to
  /// recipient_person_id = app.current_person_id(). Without that policy this
  /// would mark a colleague's notifications read too, so the safety is real
  /// but it lives in the database, not in this query.
  Future<void> markAllRead({required String businessId}) async {
    await _db
        .from('notifications')
        .update({'is_read': true})
        .eq('business_id', businessId)
        .eq('is_read', false);
  }

  /// Removes this person's notifications for this business.
  ///
  /// Same story as above: the DELETE is scoped to the caller by
  /// notifications_self_delete, added alongside this method — before that
  /// policy existed a delete matched zero rows and PostgREST answered 200, so
  /// the list would have emptied on screen and refilled on the next refresh.
  Future<void> clearAll({required String businessId}) async {
    await _db.from('notifications').delete().eq('business_id', businessId);
  }

  AgentNotification _fromRow(Map<String, dynamic> row) {
    return AgentNotification(
      notificationId: row['notification_id'] as String,
      notificationType: _typeFromString(row['notification_type'] as String?),
      message: row['message'] as String,
      relatedEntityType: relatedEntityTypeFromString(row['related_entity_type'] as String?),
      relatedEntityId: row['related_entity_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      isRead: row['is_read'] as bool? ?? false,
    );
  }

  // FLAGGED: mapping from the real notifications.notification_type enum
  // values to this screen's AgentNotificationType wasn't confirmed against
  // the actual enum labels in 0010_module9_notifications_audit.sql this
  // session (only the table shape, not every enum value, was checked) —
  // this string-match is best-effort; confirm exact enum spelling before
  // relying on it not silently falling through to `other`.
  AgentNotificationType _typeFromString(String? raw) {
    switch (raw) {
      case 'Account Period Due':
        return AgentNotificationType.accountPeriodDue;
      case 'Account Period Overdue':
        return AgentNotificationType.accountPeriodOverdue;
      case 'Pending Approval':
        return AgentNotificationType.pendingApproval;
      case 'Penalty Applied':
        return AgentNotificationType.penaltyApplied;
      case 'Extension Request':
        return AgentNotificationType.extensionRequest;
      case 'New Device Login':
        return AgentNotificationType.newDeviceLogin;
      case 'Incomplete Profile':
        return AgentNotificationType.incompleteProfile;
      default:
        return AgentNotificationType.other;
    }
  }
}

final notificationsApiServiceProvider = Provider<NotificationsApiService>((ref) {
  return NotificationsApiService();
});

// ============================================================================
// Models
// ============================================================================

/// Locked `notifications.notification_type` ENUM subset relevant to the
/// Agent, per 03_Database_Schema.md §9.1 and AG-008's own NOTIFICATION
/// LIST section. Do not add types not already named there.
enum AgentNotificationType {
  accountPeriodDue,
  accountPeriodOverdue,
  pendingApproval,
  penaltyApplied,
  extensionRequest,
  newDeviceLogin,
  incompleteProfile,
  other,
}

extension AgentNotificationTypeLabel on AgentNotificationType {
  String get label => switch (this) {
        AgentNotificationType.accountPeriodDue => 'Account Period Due',
        AgentNotificationType.accountPeriodOverdue => 'Account Period Overdue',
        AgentNotificationType.pendingApproval => 'Pending Approval',
        AgentNotificationType.penaltyApplied => 'Penalty Applied',
        AgentNotificationType.extensionRequest => 'Extension Request',
        AgentNotificationType.newDeviceLogin => 'New Device Login',
        AgentNotificationType.incompleteProfile => 'Incomplete Profile',
        AgentNotificationType.other => 'Other',
      };
}

/// `related_entity_type` values this screen knows how to route on Open —
/// per AG-008's own NAVIGATION section. `unknown` covers both a value the
/// server added that this build predates and the notifications that have no
/// destination at all (New Device Login); AG-008 tells those apart by whether
/// `related_entity_id` is set, and only complains about the first.
enum RelatedEntityType { accountPeriod, loan, customer, unknown }

RelatedEntityType relatedEntityTypeFromString(String? raw) {
  switch (raw) {
    case 'account_period':
      return RelatedEntityType.accountPeriod;
    case 'loan':
      return RelatedEntityType.loan;
    case 'customer':
      return RelatedEntityType.customer;
    default:
      return RelatedEntityType.unknown;
  }
}

class AgentNotification {
  final String notificationId;
  final AgentNotificationType notificationType;
  final String message;
  final RelatedEntityType relatedEntityType;
  final String? relatedEntityId;
  final DateTime createdAt;
  final bool isRead;

  AgentNotification({
    required this.notificationId,
    required this.notificationType,
    required this.message,
    required this.relatedEntityType,
    this.relatedEntityId,
    required this.createdAt,
    this.isRead = false,
  });

  AgentNotification copyWith({bool? isRead}) => AgentNotification(
        notificationId: notificationId,
        notificationType: notificationType,
        message: message,
        relatedEntityType: relatedEntityType,
        relatedEntityId: relatedEntityId,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
      );
}

// ============================================================================
// State
// ============================================================================

enum NotificationsFilter { all, unread }

class AgentNotificationsState {
  final bool loading;
  final List<AgentNotification> notifications;
  final NotificationsFilter filter;
  final String? error;

  const AgentNotificationsState({
    this.loading = false,
    this.notifications = const [],
    this.filter = NotificationsFilter.all,
    this.error,
  });

  List<AgentNotification> get visible =>
      filter == NotificationsFilter.unread ? notifications.where((n) => !n.isRead).toList() : notifications;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  AgentNotificationsState copyWith({
    bool? loading,
    List<AgentNotification>? notifications,
    NotificationsFilter? filter,
    String? error,
    bool clearError = false,
  }) {
    return AgentNotificationsState(
      loading: loading ?? this.loading,
      notifications: notifications ?? this.notifications,
      filter: filter ?? this.filter,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AgentNotificationsNotifier extends Notifier<AgentNotificationsState> {
  @override
  AgentNotificationsState build() => const AgentNotificationsState();

  Future<void> load({required String businessId}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(notificationsApiServiceProvider);
      final list = await api.fetchNotifications(businessId: businessId);
      state = state.copyWith(loading: false, notifications: list);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setFilter(NotificationsFilter filter) => state = state.copyWith(filter: filter);

  /// S3 — Open action's first step: mark read, then the caller (screen)
  /// navigates to the related entity.
  Future<void> markRead({required String notificationId}) async {
    final existing = state.notifications;
    // Optimistic — matches the app's other is_read-style toggles.
    state = state.copyWith(
      notifications: existing.map((n) => n.notificationId == notificationId ? n.copyWith(isRead: true) : n).toList(),
    );
    try {
      final api = ref.read(notificationsApiServiceProvider);
      await api.markRead(notificationId: notificationId);
    } catch (e) {
      state = state.copyWith(notifications: existing, error: e.toString());
    }
  }

  Future<void> markAllRead({required String businessId}) async {
    final existing = state.notifications;
    state = state.copyWith(notifications: existing.map((n) => n.copyWith(isRead: true)).toList());
    try {
      final api = ref.read(notificationsApiServiceProvider);
      await api.markAllRead(businessId: businessId);
    } catch (e) {
      state = state.copyWith(notifications: existing, error: e.toString());
    }
  }

  /// Optimistically empties the list, and puts it back if the server refuses.
  /// Same pattern as markAllRead — the alternative is a screen that sits
  /// unchanged for a round trip and looks broken on a village connection.
  Future<void> clearAll({required String businessId}) async {
    final existing = state.notifications;
    state = state.copyWith(notifications: const []);
    try {
      final api = ref.read(notificationsApiServiceProvider);
      await api.clearAll(businessId: businessId);
    } catch (e) {
      state = state.copyWith(notifications: existing, error: e.toString());
    }
  }
}

final agentNotificationsProvider = NotifierProvider<AgentNotificationsNotifier, AgentNotificationsState>(
  AgentNotificationsNotifier.new,
);
