import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/components/mana_app_bar.dart';
import '../../design/components/mana_header.dart';
import '../../features/login_registration/state/auth_flow_state.dart';
import '../notification_bell.dart';
import '../translation_service.dart';
import 'quick_expense.dart';
import 'workspace_nav.dart';

/// The three actions every Owner and Agent screen carries, in one order:
/// notifications, add expense, search.
///
/// Assembled here rather than at 60-odd call sites for the same reason
/// ManaAppBar exists: 79 screens hand-rolled their own bar, and a contract
/// spread across 79 files is not a contract. A screen says which workspace it
/// is in; it does not decide what the header offers.
///
/// NOT on Login/Registration, and not in the customer or investor workspaces.
/// Those have no business context to record an expense against, so the button
/// would be dead or would have to ask which business first — a header action
/// that opens a question is not an action.
List<Widget> manaWorkspaceActions({
  required ManaWorkspace workspace,
  required String businessId,

  /// The Agent's `agents.agent_id`. An Agent's expense comes out of their own
  /// float; the Owner's comes out of the business. Null means the Owner.
  String? agentId,
}) =>
    [
      const ManaNotificationBell(),
      _ExpenseAction(
          workspace: workspace, businessId: businessId, agentId: agentId),
      _SearchAction(workspace: workspace, businessId: businessId),
    ];

/// Installs the three on every Owner and Agent screen, by route.
///
/// Called once from main(). The alternative was editing 45 ManaAppBar call
/// sites across 33 files and then editing the next one somebody adds -- which
/// is precisely how this app came to have 79 hand-rolled app bars in the first
/// place. The screen ID is already the routing contract, so the route prefix
/// is a reliable answer to "whose workspace is this".
///
/// Everything outside /ow- and /ag- gets nothing: login and registration have
/// no session yet, and the customer and investor workspaces have no business
/// to spend from.
void manaInstallWorkspaceActions() {
  ManaAppBar.trailingActionsBuilder = (context, location) {
    final workspace = switch (location) {
      _ when location.startsWith('/ow-') => ManaWorkspace.owner,
      _ when location.startsWith('/ag-') => ManaWorkspace.agent,
      _ => null,
    };
    if (workspace == null) return const [];
    return manaWorkspaceActions(
      workspace: workspace,
      businessId: ManaSession.instance.lastBusinessId ?? '',
      agentId: workspace == ManaWorkspace.agent
          ? ManaSession.instance.lastAgentId
          : null,
    );
  };
}

/// Recording an expense, from wherever the person is standing.
///
/// This was a `+ Expense` floating button on the two home screens, which meant
/// an Agent who spent Rs 40 on fuel between two villages had to leave the
/// round, go home, record it, and find their place again. It is in the header
/// of every screen they might be on instead.
class _ExpenseAction extends ConsumerWidget {
  final ManaWorkspace workspace;
  final String businessId;
  final String? agentId;

  const _ExpenseAction({
    required this.workspace,
    required this.businessId,
    this.agentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaHeaderAction(
      // Bold, per the Owner's own spec: this is the only action in the bar
      // that CREATES something, and at a glance among three glyphs the weight
      // is what separates it from the two that only look things up.
      icon: Icons.add,
      bold: true,
      label: ref.t('add_expense'),
      // Disabled rather than hidden when there is no business in scope --
      // first-run setup, a profile screen reached before a workspace is
      // chosen. A greyed control says "not here"; a control that vanishes on
      // some screens and not others reads as a bug.
      onPressed: businessId.isEmpty
          ? null
          : () => showQuickExpense(context, ref,
              businessId: businessId, agentId: agentId),
    );
  }
}

/// Finding a person.
///
/// The two workspaces land in different places, and that is not an
/// inconsistency to be papered over. `owner_search_person` is Owner-only
/// server-side, so an Agent has no cross-business identity lookup to open --
/// their search is their own assigned roster, which is AG-004's field. Sending
/// an Agent to a screen that cannot answer would be worse than sending them to
/// the one that can.
class _SearchAction extends ConsumerWidget {
  final ManaWorkspace workspace;
  final String businessId;

  const _SearchAction({required this.workspace, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaHeaderAction(
      icon: Icons.search,
      label: ref.t('search'),
      onPressed: () => context.push(
        switch (workspace) {
          ManaWorkspace.owner => '/ow-search',
          ManaWorkspace.agent => '/ag-004',
        },
        extra: businessId,
      ),
    );
  }
}
