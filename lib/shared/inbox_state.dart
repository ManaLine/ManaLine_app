/// State for the shared Notifications inbox.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'inbox_service.dart';

class InboxState {
  final List<InboxAction> actions;
  final List<InboxNotice> notices;
  final bool loading;

  /// Set while a specific approve/accept is in flight, so only that card
  /// disables rather than the whole screen.
  final String? busyItemId;
  final String? error;

  const InboxState({
    this.actions = const [],
    this.notices = const [],
    this.loading = true,
    this.busyItemId,
    this.error,
  });

  List<InboxAction> get approvals =>
      actions.where((a) => a.kind == InboxActionKind.approval).toList();

  List<InboxAction> get invitations =>
      actions.where((a) => a.kind == InboxActionKind.invitation).toList();

  /// Accounts an Agent has handed over and is waiting on.
  List<InboxAction> get settlements =>
      actions.where((a) => a.kind == InboxActionKind.settlement).toList();

  /// Money an Investor has asked to take out.
  List<InboxAction> get withdrawals =>
      actions.where((a) => a.kind == InboxActionKind.withdrawal).toList();

  /// What the bell badges. Actionable items only — an unread informational
  /// notice is not something the person has to do, and badging both would
  /// train people to ignore the badge.
  int get actionCount => actions.length;

  int get unreadCount => notices.where((n) => !n.isRead).length;

  InboxState copyWith({
    List<InboxAction>? actions,
    List<InboxNotice>? notices,
    bool? loading,
    String? busyItemId,
    bool clearBusy = false,
    String? error,
    bool clearError = false,
  }) =>
      InboxState(
        actions: actions ?? this.actions,
        notices: notices ?? this.notices,
        loading: loading ?? this.loading,
        busyItemId: clearBusy ? null : (busyItemId ?? this.busyItemId),
        error: clearError ? null : (error ?? this.error),
      );
}

class InboxNotifier extends Notifier<InboxState> {
  @override
  InboxState build() => const InboxState();

  InboxService get _svc => ref.read(inboxServiceProvider);

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      // Both together: a half-loaded inbox that shows the feed but not the
      // three things awaiting a decision is worse than a spinner.
      final results = await Future.wait([
        _svc.pendingActions(),
        _svc.notices(),
      ]);
      state = state.copyWith(
        actions: results[0] as List<InboxAction>,
        notices: results[1] as List<InboxNotice>,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<bool> decide(InboxAction action, {required bool yes}) async {
    state = state.copyWith(busyItemId: action.itemId, clearError: true);
    try {
      switch (action.kind) {
        case InboxActionKind.approval:
          await _svc.decideRequest(requestId: action.itemId, approve: yes);
        case InboxActionKind.invitation:
          await _svc.respondToInvitation(membershipId: action.itemId, accept: yes);
        case InboxActionKind.settlement:
          // Only approval happens here. Returning one needs a reason the
          // Agent can act on, which belongs on Account Review, so the card
          // for a settlement offers no "no".
          if (!yes) {
            throw StateError(
                'Returning a settlement needs a reason — open Account Review.');
          }
          await _svc.approveSettlement(settlementId: action.itemId);
        case InboxActionKind.withdrawal:
          // Paying moves cash out of the business, so there is no "no" here
          // either: rejecting one needs a reason the Investor can read, which
          // lives on the Withdrawal Requests screen.
          if (!yes) {
            throw StateError(
                'Rejecting a withdrawal needs a reason — open Withdrawal Requests.');
          }
          await _svc.payOutWithdrawal(requestId: action.itemId);
      }
      // Reload rather than removing locally: approving a membership request
      // can create a membership, which may itself change what is pending.
      // Guessing the new state in memory is how a list starts lying.
      await load();
      state = state.copyWith(clearBusy: true);
      return true;
    } catch (e) {
      state = state.copyWith(clearBusy: true, error: e.toString());
      return false;
    }
  }

  Future<void> markRead(String id) async {
    // Optimistic: this is a read flag, not money.
    state = state.copyWith(
      notices: [
        for (final n in state.notices)
          if (n.id == id)
            InboxNotice(
                id: n.id,
                type: n.type,
                message: n.message,
                isRead: true,
                createdAt: n.createdAt)
          else
            n,
      ],
    );
    try {
      await _svc.markRead(id);
    } catch (_) {
      await load();
    }
  }

  /// Puts a notice away. Removed from the list immediately -- the person has
  /// just said they are done with it, and leaving it there while the write
  /// lands reads as the tap not working.
  Future<void> dismiss(String id) async {
    final previous = state.notices;
    state = state.copyWith(
      notices: [for (final n in previous) if (n.id != id) n],
    );
    try {
      await _svc.dismiss(id);
    } catch (e) {
      // Put it back rather than pretending: a notice that vanished from the
      // screen but not from the server comes back on the next load anyway,
      // and silently is the worst way for it to return.
      state = state.copyWith(notices: previous, error: e.toString());
    }
  }

  Future<void> markAllRead() async {
    try {
      await _svc.markAllRead();
    } finally {
      await load();
    }
  }
}

final inboxProvider = NotifierProvider<InboxNotifier, InboxState>(InboxNotifier.new);
