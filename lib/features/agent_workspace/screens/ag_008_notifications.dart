import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/agent_notifications_state.dart';
import 'ag_004_customer_management.dart';
import 'ag_006_owner_settlement.dart';
import 'ag_007_loan_distribution.dart';

final _dateTime = DateFormat('d MMM yyyy, h:mm a');

/// AG-008 — Notifications. Central list of system notifications addressed
/// to this Agent. Per spec's own NOTIFICATION LIST section: no UI-side
/// type filtering needed (see agent_notifications_state.dart doc
/// comment) — this screen just renders whatever the server returns for
/// `recipient_person_id` = this Agent.
class Ag008NotificationsScreen extends ConsumerStatefulWidget {
  final String agentId;
  final String businessId;
  const Ag008NotificationsScreen({super.key, required this.agentId, required this.businessId});

  @override
  ConsumerState<Ag008NotificationsScreen> createState() => _Ag008NotificationsScreenState();
}

class _Ag008NotificationsScreenState extends ConsumerState<Ag008NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentNotificationsProvider.notifier).load(businessId: widget.businessId);
    });
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const ManaText('clear all notifications?'),
        content: const ManaText.raw(
            'They will be removed from this list. Your loans, collections and '
            'records are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const ManaText('cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const ManaText.raw('Clear All')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      await ref
          .read(agentNotificationsProvider.notifier)
          .clearAll(businessId: widget.businessId);
      return true;
    });
  }

  Future<void> _open(AgentNotification n) async {
    await NetworkErrorHandler.run(context, () async {
      await ref.read(agentNotificationsProvider.notifier).markRead(notificationId: n.notificationId);
      return true;
    });
    if (!mounted) return;

    // Per AG-008's own NAVIGATION section — routes by related_entity_type.
    // Targets this chat doesn't own (AG-006, AG-004) are referenced by
    // route name only, not reimplemented.
    switch (n.relatedEntityType) {
      case RelatedEntityType.accountPeriod:
        // Account Period Due/Overdue → AG-006 Owner Settlement, this
        // Agent's own current settlement (AG-006 has no per-period-id
        // param — it resolves the open settlement for businessId+agentId).
        final now = DateTime.now();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OwnerSettlementScreen(
              businessId: widget.businessId,
              agentId: widget.agentId,
              periodStart: DateTime(now.year, now.month, now.day),
              periodEnd: DateTime(now.year, now.month, now.day, 23, 59, 59),
            ),
          ),
        );
        return;
      case RelatedEntityType.customer:
        // Extension Request → AG-004 Customer Management, opened to this
        // Agent's assigned-customer roster (relatedEntityId is the
        // customer_id; AG-004's list screen handles selecting into it).
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AgentCustomerManagementScreen(
              businessId: widget.businessId,
              agentMembershipId: widget.agentId,
            ),
          ),
        );
        return;
      case RelatedEntityType.loan:
        if (n.notificationType == AgentNotificationType.penaltyApplied) {
          // Penalty Applied → AG-007 (this chat's own screen) — wired
          // live since the loan_id is available on the notification.
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Ag007LoanDistributionScreen(agentId: widget.agentId, businessId: widget.businessId),
            ),
          );
          return;
        }
        break;
      case RelatedEntityType.unknown:
        break;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open target not available in this build yet.')), // TODO stub
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('notifications'),
        actions: [
          TextButton(
            onPressed: state.unreadCount == 0
                ? null
                : () => ref.read(agentNotificationsProvider.notifier).markAllRead(businessId: widget.businessId),
            child: const ManaText.raw('Mark All Read'),
          ),
          // Clearing deletes; marking read does not. So this one asks first,
          // and the two are not put side by side as if they were the same
          // weight of action.
          IconButton(
            tooltip: 'Clear All',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: state.notifications.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(agentNotificationsProvider.notifier).load(businessId: widget.businessId),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, ManaSpacing.sm),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const ManaText('all'),
                      selected: state.filter == NotificationsFilter.all,
                      onSelected: (_) =>
                          ref.read(agentNotificationsProvider.notifier).setFilter(NotificationsFilter.all),
                    ),
                    const SizedBox(width: ManaSpacing.sm),
                    ChoiceChip(
                      label: ManaText('unread (${state.unreadCount})'),
                      selected: state.filter == NotificationsFilter.unread,
                      onSelected: (_) =>
                          ref.read(agentNotificationsProvider.notifier).setFilter(NotificationsFilter.unread),
                    ),
                  ],
                ),
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(ManaSpacing.md),
                    margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
                    decoration:
                        BoxDecoration(color: ManaColors.statusBadFaint, borderRadius: BorderRadius.circular(8)),
                    child: ManaText.raw(state.error!, style: TextStyle(color: ManaColors.statusBad)),
                  ),
                ),
              Expanded(
                child: state.loading && state.notifications.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : state.visible.isEmpty
                        // S2 — Empty.
                        ? Center(
                            child: ManaText.raw('No notifications.',
                                style: TextStyle(color: ManaColors.textSecondary)),
                          )
                        // S1 — List, unread highlighted.
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.lg),
                            itemCount: state.visible.length,
                            itemBuilder: (context, i) => _NotificationRow(
                              notification: state.visible[i],
                              onOpen: () => _open(state.visible[i]),
                              onMarkRead: () => ref
                                  .read(agentNotificationsProvider.notifier)
                                  .markRead(notificationId: state.visible[i].notificationId),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final AgentNotification notification;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;

  const _NotificationRow({required this.notification, required this.onOpen, required this.onMarkRead});

  ({IconData icon, Color color}) get _typeIcon => switch (notification.notificationType) {
        AgentNotificationType.accountPeriodDue => (icon: Icons.schedule, color: ManaColors.statusWarn),
        AgentNotificationType.accountPeriodOverdue => (icon: Icons.error_outline, color: ManaColors.statusBad),
        AgentNotificationType.pendingApproval => (icon: Icons.hourglass_empty, color: ManaColors.statusWarn),
        AgentNotificationType.penaltyApplied => (icon: Icons.warning_amber_outlined, color: ManaColors.statusBad),
        AgentNotificationType.extensionRequest => (icon: Icons.event_note_outlined, color: ManaColors.statusWarn),
        AgentNotificationType.newDeviceLogin => (icon: Icons.phonelink_lock_outlined, color: ManaColors.ink),
        AgentNotificationType.incompleteProfile => (icon: Icons.person_off_outlined, color: ManaColors.statusWarn),
        AgentNotificationType.other => (icon: Icons.notifications_none, color: ManaColors.textSecondary),
      };

  @override
  Widget build(BuildContext context) {
    final t = _typeIcon;
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      color: notification.isRead ? null : ManaColors.brandFaint,
      child: ListTile(
        leading: Icon(t.icon, color: t.color),
        title: Row(
          children: [
            Flexible(
              child: ManaText(notification.notificationType.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (!notification.isRead) ...[
              const SizedBox(width: ManaSpacing.xs),
              const ManaStatusPill(label: 'Unread', status: ManaStatus.warn),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(notification.message, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 2),
              ManaText.raw(_dateTime.format(notification.createdAt),
                  style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'open') onOpen();
            if (v == 'read') onMarkRead();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'open', child: ManaText('open')),
            if (!notification.isRead) const PopupMenuItem(value: 'read', child: ManaText('mark read')),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}
