/// The shared Notifications inbox — every workspace, one screen.
///
/// Replaces AG-008's agent-only screen and gathers the invitation surfaces
/// that were scattered across OW-002, OW-003, OW-012, LR-012, CW-002 and
/// IW-002.
///
/// Ordered by what it asks of you, not by which table it came from:
///   1. Needs your approval  — someone wants into a business you own
///   2. Invitations to you   — a business wants you
///   3. Earlier              — the read-only feed
///
/// The two actionable sections are separate on purpose. "Approve" and
/// "Accept" look alike and mean opposite things; putting them in one list
/// would be a genuinely dangerous UI in an app about money.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design/components/mana_amount.dart';
import '../design/components/mana_skeleton.dart';
import '../design/components/mana_app_bar.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/typography.dart';
import '../design/tokens/spacing.dart';
import 'inbox_service.dart';
import 'inbox_state.dart';
import 'translation_service.dart';

final _when = DateFormat('d MMM, h:mm a');

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inboxProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inboxProvider);

    return Scaffold(
      appBar: ManaAppBar(
        title: ref.t('notifications'),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () => ref.read(inboxProvider.notifier).markAllRead(),
              child: ManaText.raw(ref.t('mark_all_read')),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(inboxProvider.notifier).load(),
          child: _body(state),
        ),
      ),
    );
  }

  Widget _body(InboxState state) {
    if (state.loading && state.actions.isEmpty && state.notices.isEmpty) {
      return const ManaSkeletonList(itemCount: 5);
    }
    if (state.error != null && state.actions.isEmpty && state.notices.isEmpty) {
      return _message(ref.t('could_not_load_notifications'), ManaColors.statusBad);
    }
    if (state.actions.isEmpty && state.notices.isEmpty) {
      return _message(ref.t('nothing_waiting_note'), ManaColors.textSecondary);
    }

    final rows = <Widget>[];

    if (state.approvals.isNotEmpty) {
      rows.add(_SectionHeader(
        label: ref.t('needs_your_approval'),
        count: state.approvals.length,
      ));
      rows.addAll(state.approvals.map((a) => _ActionCard(
            action: a,
            busy: state.busyItemId == a.itemId,
            yesLabel: ref.t('approve'),
            noLabel: ref.t('reject'),
          )));
    }

    if (state.settlements.isNotEmpty) {
      // First, above everything: an Agent who has handed their account over
      // cannot start the next round until this is answered, and the money is
      // still in their name while it waits.
      rows.add(_SectionHeader(
        label: ref.t('accounts_handed_to_you'),
        count: state.settlements.length,
      ));
      rows.addAll(state.settlements.map((a) => _ActionCard(
            action: a,
            busy: state.busyItemId == a.itemId,
            yesLabel: ref.t('approve'),
            // No "no" on this card: returning a settlement needs a reason the
            // Agent can act on, and that belongs on Account Review.
            noLabel: null,
          )));
    }

    if (state.invitations.isNotEmpty) {
      rows.add(_SectionHeader(
        label: ref.t('invitations_to_you'),
        count: state.invitations.length,
      ));
      rows.addAll(state.invitations.map((a) => _ActionCard(
            action: a,
            busy: state.busyItemId == a.itemId,
            yesLabel: ref.t('accept'),
            noLabel: ref.t('decline'),
          )));
    }

    if (state.notices.isNotEmpty) {
      rows.add(_SectionHeader(label: ref.t('earlier'), count: null));
      rows.addAll(state.notices.map((n) => _NoticeTile(notice: n)));
    }

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _message(String text, Color tone) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(ManaSpacing.xxl),
            child: ManaText.raw(text,
                textAlign: TextAlign.center, style: TextStyle(color: tone)),
          ),
        ],
      );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int? count;
  const _SectionHeader({required this.label, this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ManaColors.surfaceSunken,
      padding: const EdgeInsets.symmetric(
          horizontal: ManaSpacing.lg, vertical: ManaSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: ManaText.raw(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          if (count != null)
            ManaText.raw('$count',
                style: ManaType.fine),
        ],
      ),
    );
  }
}

class _ActionCard extends ConsumerWidget {
  final InboxAction action;
  final bool busy;
  final String yesLabel;
  /// Null for a card with no "no" -- a settlement, whose refusal needs a
  /// reason and therefore a screen.
  final String? noLabel;

  const _ActionCard({
    required this.action,
    required this.busy,
    required this.yesLabel,
    required this.noLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An approval names the person asking; an invitation names the business
    // asking. Either way the headline is "who wants what".
    final who = switch (action.kind) {
      InboxActionKind.approval => action.personName ?? '',
      InboxActionKind.settlement => action.personName ?? '',
      InboxActionKind.invitation => action.businessName,
    };
    final detail = switch (action.kind) {
      InboxActionKind.approval => ref
          .t('wants_to_join_as_note')
          .replaceAll('{business}', action.businessName)
          .replaceAll('{role}', action.role),
      // The figure is the whole point of the card: this is what approving
      // moves out of the Agent's hands and into the Owner's.
      InboxActionKind.settlement => ref
          .t('handed_over_amount_note')
          .replaceAll('{amount}', manaRupees((action.amount ?? 0).toInt())),
      InboxActionKind.invitation =>
        ref.t('invited_you_as_note').replaceAll('{role}', action.role),
    };

    return Card(
      margin: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, 0),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(who,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            ManaText.raw(detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ManaType.note),
            if (action.amount != null) ...[
              const SizedBox(height: ManaSpacing.xs),
              ManaAmount.compact(action.amount!,
                  semanticLabel: ref.t('proposed_investment')),
            ],
            const SizedBox(height: 2),
            ManaText.raw(_when.format(action.createdAt),
                style: TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.sm),
            // Wrap, not Row: two translated button labels side by side is
            // exactly where this codebase's overflow bug lives.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: ManaSpacing.sm,
              children: [
                if (noLabel != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => ref.read(inboxProvider.notifier).decide(action, yes: false),
                    child: ManaText.raw(noLabel!),
                  ),
                ElevatedButton(
                  onPressed: busy
                      ? null
                      : () => ref.read(inboxProvider.notifier).decide(action, yes: true),
                  child: busy
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(yesLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeTile extends ConsumerWidget {
  final InboxNotice notice;
  const _NoticeTile({required this.notice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(
        notice.isRead ? Icons.notifications_none : Icons.notifications_active,
        color: notice.isRead ? ManaColors.textSecondary : ManaColors.brand,
      ),
      title: ManaText.raw(notice.message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: notice.isRead ? FontWeight.w400 : FontWeight.w600,
          )),
      subtitle: ManaText.raw(_when.format(notice.createdAt),
          style: TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
      onTap: notice.isRead
          ? null
          : () => ref.read(inboxProvider.notifier).markRead(notice.id),
    );
  }
}
