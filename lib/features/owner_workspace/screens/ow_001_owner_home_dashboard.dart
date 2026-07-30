import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_header.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/motion.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/owner_api_service.dart';
import '../state/owner_workspace_state.dart';
import '../state/customer_state.dart';
import '../../../shared/translation_service.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// OW-001 — Owner Home Dashboard. Read-only aggregation screen; every write
/// happens on the destination screens its Quick Actions/cards link to (per
/// spec's own DATA MODEL TOUCHED note). Polling refresh every 15-30s per
/// the cross-cutting live-update decision — this scaffold polls on a timer
/// rather than websockets, matching the locked API BINDING.
///
/// FIXED this batch: Workforce/Investor Snapshot "See All" AND every one
/// of the 9 Quick Actions tiles were pushing to their destination routes
/// with no `extra: businessId` — router.dart's `_resolveBusinessId(s)`
/// then fell back to `ManaSession.instance.lastBusinessId ??
/// 'stub-business-id'`, which is fragile (and in the reported case,
/// produced an empty/wrong-business list on the destination screen even
/// though this dashboard's own aggregate counts were correct). All 11
/// navigation call sites below now explicitly pass `extra: widget.businessId`
/// or `extra: businessId`, removing the dependency on that fallback
/// entirely.
class OwnerHomeDashboardScreen extends ConsumerStatefulWidget {
  final String businessId;
  const OwnerHomeDashboardScreen({super.key, required this.businessId});

  @override
  ConsumerState<OwnerHomeDashboardScreen> createState() => _OwnerHomeDashboardScreenState();
}

class _OwnerHomeDashboardScreenState extends ConsumerState<OwnerHomeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ownerDashboardProvider.notifier).load(widget.businessId);
    });
  }

  Future<void> _refresh() => ref.read(ownerDashboardProvider.notifier).load(widget.businessId);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ownerDashboardProvider);

    return Scaffold(
      // top: false so the coloured header block bleeds under the status bar —
      // that edge-to-edge colour is the whole point of the pattern. SafeArea
      // wraps its child in MediaQuery.removePadding, so leaving top on would
      // hide the inset from ManaHeaderBlock and leave a white strip above the
      // blue. Bottom is still guarded, and ManaBottomNav has its own SafeArea.
      body: SafeArea(
        top: false,
        child: async.when(
          // Skeleton rather than a centred spinner: it shows the page's real
          // structure (header, status bar, two section cards) so the wait
          // reads as "loading this screen" instead of "nothing here", and the
          // content lands without a layout jump. Only ever seen on a genuine
          // cold load now — revisits keep the previous data on screen and
          // revalidate behind it (see OwnerDashboardNotifier.load).
          loading: () => const _DashboardSkeleton(),
          error: (e, _) => _errorState(e),
          data: (data) => RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: ManaSpacing.xxl),
              children: [
                // The header is deliberately NOT wrapped in ManaAppear: fading
                // in the thing that identifies the screen reads as hesitation.
                // Identity lands immediately; the content below it arrives.
                _Header(
                  businessId: widget.businessId,
                  businessName: data.businessName,
                  businessOpen: data.businessOpen,
                  notifications: data.notifications,
                  pendingInvitations: data.pendingInvitations,
                  pendingAcceptances: data.pendingAcceptances,
                ),
                const SizedBox(height: ManaSpacing.md),
                // Staggered entrance so sections resolve in reading order
                // rather than the whole page popping in at once. 30ms apart and
                // capped at 8, so the last card is in place ~240ms after the
                // first — fast enough that it reads as the page settling, not
                // as an animation being performed at you. Skipped entirely
                // under reduce-motion.
                for (final (i, section) in <Widget>[
                  _SectionCard(
                    title: "today's business summary",
                    child: _BfRow(data: data),
                  ),
                  _SectionCard(
                    title: 'quick actions',
                    child: _QuickActions(businessId: widget.businessId),
                  ),
                  _SectionCard(
                    title: 'live business activity',
                    onSeeAll: data.liveActivity.isEmpty ? null : () {},
                    child: _LiveActivity(items: data.liveActivity),
                  ),
                  _SectionCard(
                    title: 'attention required',
                    child: _AttentionRequired(businessId: widget.businessId, cards: data.attentionRequired),
                  ),
                ].indexed)
                  ManaAppear(index: i, child: section),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _FooterNav(businessId: widget.businessId),
    );
  }

  Widget _errorState(Object e) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('could not load dashboard'),
            const SizedBox(height: ManaSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.md),
              child: ManaText.raw(
                e.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: ManaColors.statusBad),
              ),
            ),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(onPressed: _refresh, child: const ManaText('retry')),
          ],
        ),
      ),
    );
  }
}

// --- C1 Header ---------------------------------------------------------

/// Mirrors the real dashboard's structure so the cold-load wait shows the
/// shape of what's coming: header block, status strip, then the two section
/// cards. Sizes are deliberately close to the live widgets' so content
/// arriving doesn't shift the layout.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ManaSkeletonGroup(
      child: ListView(
        padding: const EdgeInsets.only(bottom: ManaSpacing.xxl),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // The header is rendered as the FINAL brandDeep block, not as
          // placeholders. Shimmering grey where the coloured header will be
          // would flash white-to-blue the moment data lands, which is a worse
          // artifact than the wait itself. The colour and geometry are known
          // before the fetch returns, so they are drawn immediately and only
          // the unknown parts below shimmer.
          Container(
            height: MediaQuery.paddingOf(context).top + 84,
            color: ManaColors.brandDeep,
          ),
          // Business status strip.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
            child: ManaSkeleton(height: 44, radius: ManaRadius.md),
          ),
          const SizedBox(height: ManaSpacing.md),
          // Today's Business Summary — a grid of figures.
          const _SkeletonSection(rows: 3),
          // Quick Actions — a grid of tiles.
          const _SkeletonSection(rows: 2),
        ],
      ),
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  final int rows;
  const _SkeletonSection({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(ManaSpacing.md),
        decoration: BoxDecoration(
          color: ManaColors.surface,
          borderRadius: BorderRadius.circular(ManaRadius.md),
          border: Border.all(color: ManaColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaSkeleton(width: 130, height: 12),
            const SizedBox(height: ManaSpacing.md),
            for (var i = 0; i < rows; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : ManaSpacing.sm),
                child: const Row(
                  children: [
                    Expanded(child: ManaSkeleton(height: 32, radius: ManaRadius.sm)),
                    SizedBox(width: ManaSpacing.sm),
                    Expanded(child: ManaSkeleton(height: 32, radius: ManaRadius.sm)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final String businessId;
  final String businessName;
  final bool businessOpen;
  final List<NotificationItem> notifications;
  // Item 2: the Invitations/Acceptances pills that used to live in
  // _BusinessStatusBar below the header now ride in the notifications
  // sheet — they are notifications, not status, and the strip was costing
  // a full row of above-the-fold height for two counts that are usually 0.
  final int pendingInvitations;
  final int pendingAcceptances;
  const _Header({
    required this.businessId,
    required this.businessName,
    required this.businessOpen,
    required this.notifications,
    required this.pendingInvitations,
    required this.pendingAcceptances,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    // The badge counts the pending memberships too, otherwise removing the
    // strip would hide them behind an unbadged icon.
    final unread =
        notifications.where((n) => !n.read).length + pendingInvitations + pendingAcceptances;

    // Was a white Container with a hand-rolled Row. Now the shared coloured
    // header block: identity on brandDeep, actions forced to the 48dp floor
    // with real accessible names, and the unread count surfaced as a badge
    // instead of being invisible until the sheet is opened.
    return ManaHeaderBlock(
      title: businessName.isEmpty ? 'Business' : businessName,
      subtitle: DateFormat('EEE, d MMM').format(now),
      leading: Container(
        color: ManaColors.brandFaint,
        child: const Icon(Icons.storefront, color: ManaColors.brandDeep),
      ),
      actions: [
        ManaHeaderAction(
          icon: Icons.notifications_outlined,
          label: 'Notifications',
          badgeCount: unread,
          onPressed: () => _openNotifications(context),
        ),
        ManaHeaderAction(
          icon: Icons.search,
          label: 'Universal Search',
          onPressed: () => _openUniversalSearch(context),
        ),
        _overflowMenu(context, ref),
      ],
      // The status pills stay on the light body below, not inside the header:
      // ManaStatusPill uses faint tinted backgrounds that are designed to sit
      // on white and would lose their contrast on brandDeep. Putting them
      // there would mean restyling the whole status vocabulary for one screen.
    );
  }

  /// Kept as a PopupMenuButton rather than a ManaHeaderAction: this opens a
  /// menu rather than performing an action, so it needs Flutter's own anchor
  /// and dismissal behaviour. Sized and labelled to the same floor by hand.
  Widget _overflowMenu(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'More options',
      child: PopupMenuButton<String>(
        tooltip: 'More options',
        iconSize: 24,
        constraints: const BoxConstraints(minWidth: kManaMinTapTarget),
        icon: const Icon(Icons.more_vert, color: ManaColors.textOnDark),
        onSelected: (v) {
              switch (v) {
                case 'switch_business':
                  context.go('/lr-012');
                case 'switch_role':
                  context.go('/lr-013');
                case 'profile':
                  context.push('/ow-016');
                case 'business_management':
                  context.push('/ow-012', extra: businessId);
                case 'report_hub':
                  context.push('/ow-010', extra: businessId);
                case 'settings':
                  context.push('/ow-settings', extra: businessId);
                case 'admin_panel':
                  context.push('/admin-panel');
                case 'logout':
                  ref.read(authFlowProvider.notifier).reset();
                  context.go('/lr-003');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'profile', child: ManaText('profile')),
              const PopupMenuItem(value: 'business_management', child: ManaText('business management')),
              const PopupMenuItem(value: 'report_hub', child: ManaText('report hub')),
              const PopupMenuItem(value: 'switch_business', child: ManaText('switch workspace')),
              const PopupMenuItem(value: 'switch_role', child: ManaText('switch role')),
              const PopupMenuItem(value: 'settings', child: ManaText('settings')),
              if (ref.watch(authFlowProvider).isPlatformAdmin) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'admin_panel',
                  child: ManaText.raw('admin panel', style: TextStyle(color: ManaColors.statusBad, fontWeight: FontWeight.bold)),
                ),
              ],
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: ManaText('logout')),
        ],
      ),
    );
  }

  // Both header icons were previously no-op `onPressed: () {}` placeholders.
  void _openNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NotificationsSheet(
        businessId: businessId,
        notifications: notifications,
        pendingInvitations: pendingInvitations,
        pendingAcceptances: pendingAcceptances,
      ),
    );
  }

  void _openUniversalSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UniversalSearchSheet(businessId: businessId),
    );
  }
}

class _NotificationsSheet extends StatelessWidget {
  final String businessId;
  final List<NotificationItem> notifications;
  final int pendingInvitations;
  final int pendingAcceptances;
  const _NotificationsSheet({
    required this.businessId,
    required this.notifications,
    required this.pendingInvitations,
    required this.pendingAcceptances,
  });

  // Unchanged destination from the deleted status strip: OW-012's Members
  // tab already holds the pending-invitation / pending-acceptance lists and
  // the investor accept/reject queue.
  void _openInvitations(BuildContext context) {
    Navigator.of(context).pop();
    context.push('/ow-012?tab=members', extra: businessId);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.md),
            if (pendingInvitations > 0)
              _MembershipRow(
                label: '$pendingInvitations Invitations',
                subtitle: 'Sent, waiting for the person to respond',
                onTap: () => _openInvitations(context),
              ),
            if (pendingAcceptances > 0)
              _MembershipRow(
                label: '$pendingAcceptances Acceptances',
                subtitle: 'Waiting for you to accept',
                onTap: () => _openInvitations(context),
              ),
            if (pendingInvitations > 0 || pendingAcceptances > 0) const Divider(),
            Expanded(
              child: notifications.isEmpty
                  ? Center(
                      child: ManaText.raw(
                        pendingInvitations > 0 || pendingAcceptances > 0
                            ? 'Nothing else to report.'
                            : 'No notifications yet.',
                        style: const TextStyle(color: ManaColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        final n = notifications[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            n.read ? Icons.notifications_none : Icons.notifications_active,
                            color: n.read ? ManaColors.textSecondary : ManaColors.brand,
                          ),
                          title: ManaText.raw(n.label, style: const TextStyle(fontSize: 13)),
                          subtitle: ManaText.raw(n.type, style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                          trailing: ManaText.raw(DateFormat('d MMM, hh:mm a').format(n.timestamp),
                              style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reuses the same identity-search RPC already wired for OW-004/OW-005/
// AG-007's customer search (owner_search_person, MLID/phone/Aadhaar/name)
// — the only cross-role identity lookup this backend actually exposes.
// After a match, resolves the person's role in THIS business via
// business_members so the Owner lands on the right management screen
// directly, instead of guessing between Customer/Workforce/Investor.
class _UniversalSearchSheet extends ConsumerStatefulWidget {
  final String businessId;
  const _UniversalSearchSheet({required this.businessId});

  @override
  ConsumerState<_UniversalSearchSheet> createState() => _UniversalSearchSheetState();
}

class _UniversalSearchSheetState extends ConsumerState<_UniversalSearchSheet> {
  final _query = TextEditingController();
  bool _searching = false;
  String? _error;
  CustomerSummary? _found;
  List<String> _foundRoles = const [];

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _found = null;
      _foundRoles = const [];
    });
    final isMlid = RegExp(r'^ML[A-Za-z]{2}\d+$').hasMatch(query);
    final digitsOnly = RegExp(r'^\d+$').hasMatch(query);
    try {
      final result = await ref.read(customerListProvider.notifier).searchIdentity(
            mlid: isMlid ? query : null,
            aadhaar: !isMlid && digitsOnly && query.length == 12 ? query : null,
            phone: !isMlid && digitsOnly && query.length == 10 ? query : null,
            fullName: isMlid || digitsOnly ? null : query,
          );
      // Plain list, not .maybeSingle() — a person can hold more than one
      // role in the same business (e.g. the Owner themselves also
      // holding an Agent membership, per the UNIQUE constraint being on
      // (person_id, business_id, role), not (person_id, business_id)).
      // .maybeSingle() throws "Results contain N rows" the moment that's
      // true for whoever was searched, instead of just listing them.
      var roles = <String>[];
      if (result?.personId != null) {
        final rows = await Supabase.instance.client
            .from('business_members')
            .select('role')
            .eq('business_id', widget.businessId)
            .eq('person_id', int.parse(result!.personId!));
        roles = (rows as List).map((r) => r['role'] as String).toList();
      }
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = result;
        _foundRoles = roles;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e.toString();
      });
    }
  }

  void _goToRoleScreen(BuildContext context, String role) {
    final route = switch (role) {
      'Agent' => '/ow-002',
      'Investor' => '/ow-003',
      'Customer' => '/ow-004',
      _ => null,
    };
    if (route == null) return;
    Navigator.of(context).pop();
    context.push(route, extra: widget.businessId);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('search', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.xs),
            const ManaText.raw('Search by Phone, MANA LINE ID, Aadhaar, or Name.',
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(labelText: 'Search'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                FilledButton(
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const ManaText('search'),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            if (_error != null)
              ManaText.raw(_error!, style: const TextStyle(color: ManaColors.statusBad, fontSize: 13)),
            if (_found != null)
              Card(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: ManaText.raw(_found!.fullName),
                      subtitle: ManaText.raw(_found!.mlid),
                    ),
                    if (_foundRoles.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.md),
                        child: ManaText.raw('Not a member of this business.',
                            style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
                      )
                    else
                      // A person can hold more than one role in the same
                      // business (e.g. an Owner who is also an Agent) —
                      // one tappable row per role rather than guessing.
                      ..._foundRoles.map((role) => ListTile(
                            title: ManaText.raw(role),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _goToRoleScreen(context, role),
                          )),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// C2 Business Status Bar was DELETED (item 2). The Open/Closed pill, the
// Approvals pill and the Day Closure Pending pill went with it: the first
// duplicated nothing an Owner acts on from here, and the other two are
// already surfaced as tappable rows in Attention Required, which routes to
// the screen that actions them. Only the Invitations/Acceptances counts
// were kept, and they moved into _NotificationsSheet above.

/// One pending-membership count inside the notifications sheet. Its own
/// widget rather than a bare ListTile so the whole row is the tap target at
/// the 48dp floor, and the count is spoken as part of the action.
class _MembershipRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _MembershipRow({required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label. $subtitle',
      excludeSemantics: true,
      child: ManaPressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kManaMinTapTarget),
          child: Row(
            children: [
              const Icon(Icons.mark_email_unread_outlined, color: ManaColors.brand),
              const SizedBox(width: ManaSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ManaText.raw(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ManaText.raw(subtitle,
                        style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: ManaColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Shared section wrapper ------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onSeeAll;
  const _SectionCard({required this.title, required this.child, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: ManaText(title, style: Theme.of(context).textTheme.titleMedium)),
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: const ManaText('see all')),
            ],
          ),
          const SizedBox(height: ManaSpacing.sm),
          child,
        ],
      ),
    );
  }
}

// --- C3 Today's Business Summary --------------------------------------------

/// Item 3: the eight-row summary card collapsed to the one figure an Owner
/// opens this screen for — BF (Brought Forward) = the opening balance. The
/// full card is unchanged, it just moved behind a tap into a bottom sheet.
///
/// The WHOLE row is the tap target, not the digit: on a cheap phone in
/// sunlight, aiming at a ₹ figure is a miss waiting to happen. 48dp floor,
/// and the label carries the action for a screen reader rather than leaving
/// "₹0" as an unexplained tappable.
class _BfRow extends StatelessWidget {
  final OwnerDashboardData data;
  const _BfRow({required this.data});

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            const ManaText("today's business summary",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.md),
            _TodaysSummary(data: data),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // excludeSemantics so the row is announced once, as one control, rather
    // than as a button plus a stray "₹0" — the amount is folded into the
    // label instead.
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Brought forward, ${_currency.format(data.openingBalance)}. '
          "Opens today's business summary",
      child: ManaPressable(
        onTap: () => _openSheet(context),
        borderRadius: BorderRadius.circular(ManaRadius.md),
        child: Card(
          margin: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kManaMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: ManaSpacing.md, vertical: ManaSpacing.sm),
              child: Row(
                children: [
                  const ManaText.raw('BF', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: ManaSpacing.sm),
                  const ManaText.raw('=', style: TextStyle(color: ManaColors.textSecondary)),
                  const SizedBox(width: ManaSpacing.sm),
                  Expanded(
                    child: ManaAmount(data.openingBalance),
                  ),
                  const Icon(Icons.chevron_right, color: ManaColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodaysSummary extends StatelessWidget {
  final OwnerDashboardData data;
  const _TodaysSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double, bool)>[
      ('Opening Balance', data.openingBalance, false),
      ("Today's Collections", data.todaysCollections, false),
      ("Today's Loan Distribution", data.todaysLoanDistribution, false),
      ("Today's Investments", data.todaysInvestments, false),
      ("Today's Withdrawals", data.todaysWithdrawals, false),
      ("Today's Expenses", data.todaysExpenses, false),
      ("Today's Outstanding", data.todaysOutstanding, false),
      ("Today's Difference", data.todaysDifference, true),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          children: [
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: ManaText.raw(r.$1, style: const TextStyle(fontSize: 13))),
                      // ManaAmount rather than a raw formatted string: tabular
                      // figures so this column of rupee values actually aligns
                      // digit-for-digit, and a spoken form ("Today's
                      // Collections, 4,500 rupees") instead of a screen reader
                      // spelling out the symbol and every comma.
                      ManaAmount(
                        r.$2,
                        size: ManaAmountSize.compact,
                        tone: r.$3 && r.$2 < 0 ? ManaAmountTone.negative : ManaAmountTone.neutral,
                        // Only the Difference row shows a sign — direction is
                        // the information there, whereas a signed balance just
                        // adds noise.
                        showSign: r.$3,
                        semanticLabel: r.$1,
                      ),
                    ],
                  ),
                )),
            const Divider(height: ManaSpacing.lg),
            Row(
              children: [
                const Expanded(
                  child: ManaText('live closing balance', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                // The figure this card exists to deliver, so it gets the
                // larger size rather than matching the rows above it.
                ManaAmount(
                  data.liveClosingBalance,
                  semanticLabel: 'Live closing balance',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- C4 Quick Actions --------------------------------------------------
//
// Grouped by who the action is about (Customers / Workforce / Investor)
// rather than one flat 9-tile grid, and expanded to cover every action an
// Owner actually has available in that group — not just the original
// one-tile-per-management-screen set. Tiles that need a screen to do
// something more specific than "open the list" (register vs add-existing,
// search vs browse, a pre-filtered request queue) drive that via a route
// query param the destination screen reads in its own initState, so each
// tile is a real distinct destination, not a decorative duplicate.
//
// NOTE (flagged, not silently built): "assign agent to an operating area"
// has no dedicated screen outside the OW-000 setup wizard — OW-012's
// Operating Areas tab only supports add-area/configure-cycle today, not
// re-assigning an area to a different agent. Folded into "Workforce
// Management" below rather than shipping a tile that points at a flow
// that doesn't exist. Same reasoning for "Add Investments": recording an
// investment requires picking the investor first (Investor Profile's own
// "record investment" action) — folded into "Investor Management" rather
// than a fake shortcut with nowhere distinct to land.
class _QuickActions extends StatelessWidget {
  final String businessId;
  const _QuickActions({required this.businessId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QuickActionGroup(
          title: 'customers',
          businessId: businessId,
          actions: const [
            (Icons.request_quote_outlined, 'New Loan', '/ow-005', null),
            (Icons.point_of_sale_outlined, 'Collections', '/ow-006', null),
            // 'Search Customers' removed (item 4.1) — the header's Universal
            // Search covers it, and OW-004 has its own search field.
            (Icons.people_outline, 'Customer Management', '/ow-004', null),
            (Icons.inbox_outlined, 'Loan Requests', '/ow-loan-requests', null),
            // BUG FIXED this pass: OW-015 was a real, fully-built screen
            // with zero links from anywhere in the app.
            (Icons.groups_2_outlined, 'Group Loans', '/ow-015', null),
          ],
        ),
        const SizedBox(height: ManaSpacing.md),
        _QuickActionGroup(
          title: 'workforce',
          businessId: businessId,
          actions: const [
            // 'Register New Agent' and 'Add Existing Agent' removed (item
            // 5.1) — both already exist as header actions inside Workforce
            // Management, which this tile opens.
            (Icons.groups_outlined, 'Workforce Management', '/ow-002', null),
            (Icons.lock_clock_outlined, 'Day Closure', '/ow-011', null),
            (Icons.menu_book_outlined, 'Daily Record Book', '/ow-009', null),
            (Icons.bar_chart_outlined, 'Reports', '/ow-010', null),
            // BUG FIXED this pass: OW-013 was a real, fully-built screen
            // with zero links from anywhere in the app.
            (Icons.fact_check_outlined, 'Account Review', '/ow-013', null),
          ],
        ),
        const SizedBox(height: ManaSpacing.md),
        _QuickActionGroup(
          title: 'investor',
          businessId: businessId,
          actions: const [
            (Icons.person_add_alt_1_outlined, 'Add Existing Investor', '/ow-003', 'open=existing'),
            (Icons.inbox_outlined, 'Investor Requests', '/ow-003', 'filter=Pending%20Acceptance'),
            (Icons.savings_outlined, 'Investor Management', '/ow-003', null),
            // BUG FIXED this pass: investment_withdrawal_requests had a
            // real INSERT path with no reachable Owner review screen at
            // all — requests sat Pending forever.
            (Icons.payments_outlined, 'Withdrawal Requests', '/ow-withdrawal-requests', null),
          ],
        ),
      ],
    );
  }
}

class _QuickActionGroup extends StatelessWidget {
  final String title;
  final String businessId;
  final List<(IconData, String, String, String?)> actions;
  const _QuickActionGroup({required this.title, required this.businessId, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.xs),
        // Was a GridView with crossAxisCount: 3 and childAspectRatio: 0.95 —
        // a fixed aspect ratio wrapping up-to-2-line labels, i.e. the same
        // latent overflow shape that broke the five stat strips. A user raising
        // their system font size would have clipped every tile. ManaActionGrid
        // sizes to content instead, and goes 4-up on phones (5 or 6 on larger
        // screens) so the tile a thumb has memorised doesn't move between
        // devices.
        ManaActionGrid(
          actions: [
            for (final (icon, label, route, query) in actions)
              ManaAction(
                icon: icon,
                label: label,
                onTap: () => context.push(
                  query == null ? route : '$route?$query',
                  extra: businessId,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// --- C5 Live Business Activity --------------------------------------------

class _LiveActivity extends StatelessWidget {
  final List<ActivityItem> items;
  const _LiveActivity({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(ManaSpacing.lg),
          child: ManaText.raw('No activity yet today.', style: TextStyle(color: ManaColors.textSecondary)),
        ),
      );
    }
    return Card(
      child: Column(
        children: items
            .take(5)
            .map((a) => ListTile(
                  leading: const Icon(Icons.circle, size: 8, color: ManaColors.brand),
                  title: ManaText.raw(a.label, style: const TextStyle(fontSize: 13)),
                  trailing: ManaText.raw(DateFormat('hh:mm a').format(a.timestamp),
                      style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                ))
            .toList(),
      ),
    );
  }
}

// --- C6 Attention Required --------------------------------------------

class _AttentionRequired extends StatelessWidget {
  final String businessId;
  final List<AttentionCard> cards;
  const _AttentionRequired({required this.businessId, required this.cards});

  // BUG FIXED this pass: every card here had onTap: () {} — an Owner
  // tapping a flagged HIGH-priority item (e.g. Pending Customer Approval)
  // saw nothing happen. Routes each card to wherever that type is
  // actually actioned; falls back to Report Hub (a safe, always-correct
  // "see everything" destination) for any type string this doesn't
  // recognize rather than silently doing nothing.
  void _open(BuildContext context, AttentionCard c) {
    final route = switch (c.type) {
      'Pending Customer Approval' => '/ow-004',
      'Pending Loan Approval' => '/ow-loan-requests',
      'Pending Day Closure' => '/ow-011',
      _ => '/ow-010',
    };
    context.push(route, extra: businessId);
  }

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(ManaSpacing.lg),
          child: ManaText.raw('Nothing needs attention right now.', style: TextStyle(color: ManaColors.textSecondary)),
        ),
      );
    }
    return Column(
      children: cards
          .map((c) => Card(
                child: ListTile(
                  leading: Icon(Icons.priority_high,
                      color: c.priority == 'High' ? ManaColors.statusBad : ManaColors.statusWarn),
                  title: ManaText.raw(c.type, style: const TextStyle(fontSize: 13)),
                  subtitle: ManaText.raw('Updated ${DateFormat('d MMM, hh:mm a').format(c.lastUpdated)}',
                      style: const TextStyle(fontSize: 13)),
                  trailing: ManaStatusPill(
                    label: '${c.count}',
                    status: c.priority == 'High' ? ManaStatus.bad : ManaStatus.warn,
                  ),
                  onTap: () => _open(context, c),
                ),
              ))
          .toList(),
    );
  }
}

// --- C11 Footer Navigation --------------------------------------------

class _FooterNav extends ConsumerWidget {
  final String businessId;
  const _FooterNav({required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Was a Material NavigationBar. Swapped for the shared ManaBottomNav so
    // Owner/Agent/Customer/Investor all get identical navigation — the other
    // three workspaces will adopt the same widget rather than each
    // reinterpreting it. It also supplies selectedIcon per item (the old
    // version only set one for Home, so the other three never changed shape
    // when selected) and refuses to re-navigate to the current tab, which
    // pushed a duplicate route and broke Back.
    return ManaBottomNav(
      currentIndex: 0,
      items: [
        ManaNavItem(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: ref.t('home'),
          onTap: () {},
        ),
        ManaNavItem(
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          label: ref.t('customers'),
          onTap: () => context.go('/ow-004', extra: businessId),
        ),
        ManaNavItem(
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale,
          label: ref.t('collections'),
          onTap: () => context.go('/ow-006', extra: businessId),
        ),
        ManaNavItem(
          icon: Icons.history,
          selectedIcon: Icons.history_toggle_off,
          label: ref.t('history'),
          onTap: () => context.go('/ow-017', extra: businessId),
        ),
      ],
    );
  }
}
