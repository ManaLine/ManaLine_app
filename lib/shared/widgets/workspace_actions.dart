import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/components/mana_app_bar.dart';
import '../../design/components/mana_header.dart';
import '../../features/login_registration/state/auth_flow_state.dart';
import '../notification_bell.dart';
import '../translation_service.dart';
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
/// Who the header's + adds, on the screen it is drawn on.
///
/// The + used to add a Customer everywhere, including on Workforce Management
/// and Investor Management — so on the two screens whose entire subject is
/// agents and investors, the one button that creates something created the
/// wrong kind of person. The Owner asked for this three separate ways (a way to
/// add an agent while assigning areas, a way to add one from Workforce, and a
/// header that matches the screen); it is one contract, decided here.
enum ManaMemberKind {
  customer,
  agent,
  investor;

  /// OW-014 pre-fills its first step from this.
  String get workflowType => name;
}

/// The screen's subject, from its route.
///
/// Route prefixes rather than a parameter on 60-odd call sites, for the same
/// reason the bar itself is installed by route: a screen says where it is, it
/// does not restate what its header should offer. Anything not named here adds
/// a Customer, which is what every collection round and customer list wants.
ManaMemberKind manaMemberKindForRoute(String location) {
  if (location.startsWith('/ow-002')) return ManaMemberKind.agent;
  if (location.startsWith('/ow-003')) return ManaMemberKind.investor;
  return ManaMemberKind.customer;
}

List<Widget> manaWorkspaceActions({
  required ManaWorkspace workspace,
  required String businessId,
  ManaMemberKind kind = ManaMemberKind.customer,
}) =>
    [
      const ManaNotificationBell(),
      _AddMemberAction(workspace: workspace, businessId: businessId, kind: kind),
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
      kind: manaMemberKindForRoute(location),
    );
  };
}

/// Adding a customer, from wherever the person is standing.
///
/// The + used to record an expense. It adds a customer now, at the Owner's
/// instruction: a round produces new borrowers far more often than it
/// produces receipts to file, and adding one meant leaving whatever screen
/// you were on for Customer Management. Recording an expense moved to the
/// drawer, where it is still one tap from anywhere.
///
/// Ends with a choice -- add them, or add them and go straight to a loan --
/// so somebody standing in front of a new borrower does not have to find
/// them again in a list of fifty-six to lend to them.
class _AddMemberAction extends ConsumerWidget {
  final ManaWorkspace workspace;
  final String businessId;
  final ManaMemberKind kind;

  const _AddMemberAction({
    required this.workspace,
    required this.businessId,
    required this.kind,
  });

  /// Agents and Investors go through OW-014, which already searches for an
  /// existing person by MLID or name and registers a new one when there is no
  /// match — the "search & add, or register new" the Owner asked for. It was
  /// built and reachable at /ow-014?type=…; nothing pointed at it.
  ///
  /// Customers keep /customer-new, because that sheet ends with a choice OW-014
  /// does not have: add them, or add them and go straight to a loan.
  String get _route => switch (kind) {
        ManaMemberKind.customer => '/customer-new',
        ManaMemberKind.agent => '/ow-014?type=agent',
        ManaMemberKind.investor => '/ow-014?type=investor',
      };

  String _label(WidgetRef ref) => switch (kind) {
        ManaMemberKind.customer => ref.t('add_a_customer'),
        ManaMemberKind.agent => ref.t('add_an_agent'),
        ManaMemberKind.investor => ref.t('add_investor'),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kind != ManaMemberKind.customer) {
      return ManaHeaderAction(
        icon: Icons.add,
        bold: true,
        label: _label(ref),
        onPressed: businessId.isEmpty
            ? null
            : () => context.push(_route, extra: businessId),
      );
    }
    return ManaHeaderAction(
      // Bold: this is the only action in the bar that CREATES something, and
      // at a glance among three glyphs the weight is what separates it from
      // the two that only look things up.
      icon: Icons.add,
      bold: true,
      label: ref.t('add_a_customer'),
      // Disabled rather than hidden when there is no business in scope --
      // first-run setup, a profile screen reached before a workspace is
      // chosen. A greyed control says "not here"; a control that vanishes on
      // some screens and not others reads as a bug.
      onPressed: businessId.isEmpty
          ? null
          : () async {
              final customerId = await context.push<String?>(
                  '/customer-new', extra: businessId);
              if (customerId == null || !context.mounted) return;
              // They asked to lend to the person they just added. Each
              // workspace issues loans from its own screen.
              context.push(
                switch (workspace) {
                  ManaWorkspace.owner => '/ow-005?customerId=$customerId',
                  ManaWorkspace.agent => '/ag-007?customerId=$customerId',
                },
                extra: businessId,
              );
            },
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
