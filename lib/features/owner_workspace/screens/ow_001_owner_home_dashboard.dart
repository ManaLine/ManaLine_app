import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/auto_refresh.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_info_popup.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_header.dart';
import '../../../design/components/mana_app_shell.dart';
import '../../../shared/person_identity.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/motion.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/owner_api_service.dart';
import '../state/owner_workspace_state.dart';
import '../state/customer_state.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/mana_time.dart';

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// The Owner's drawer. Supplied by the screen rather than baked into
/// [ManaAppShell] because an Agent's "Customers" is not an Owner's — same
/// label, different destinations and different permissions.
///
/// Every destination passes `extra: businessId`. Omitting it is what made
/// router.dart fall through to `ManaSession.instance.lastBusinessId ??
/// 'stub-business-id'`, which is the confirmed cause of the "back click ->
/// dead end" bug this file's own header comment records.
List<ManaDrawerSection> _ownerDrawerSections(
    BuildContext context, String businessId) {
  return [
    ManaDrawerSection(
      icon: Icons.people_outline,
      labelKey: 'customers',
      actions: [
        ManaDrawerAction(
          labelKey: 'customer_management',
          onTap: () => context.push('/ow-004', extra: businessId),
        ),
        ManaDrawerAction(
          labelKey: 'new_loan',
          onTap: () => context.push('/ow-005', extra: businessId),
        ),
        ManaDrawerAction(
          labelKey: 'group_loan_management',
          onTap: () => context.push('/ow-015', extra: businessId),
        ),
      ],
    ),
    ManaDrawerSection(
      icon: Icons.badge_outlined,
      labelKey: 'workforce',
      actions: [
        ManaDrawerAction(
          labelKey: 'workforce_management',
          onTap: () => context.push('/ow-002', extra: businessId),
        ),
        ManaDrawerAction(
          labelKey: 'account_review',
          onTap: () => context.push('/ow-013', extra: businessId),
        ),
      ],
    ),
    ManaDrawerSection(
      icon: Icons.savings_outlined,
      labelKey: 'investors',
      actions: [
        ManaDrawerAction(
          labelKey: 'investor_management',
          onTap: () => context.push('/ow-003', extra: businessId),
        ),
      ],
    ),
    // --- Everything below was the header's overflow (kebab) menu ---------
    //
    // That menu is gone. It duplicated the drawer's job — two different
    // navigation surfaces on the same screen, one of which was invisible
    // until you knew to press it — and it lived in a header that has since
    // been cut to one row. These are the same seven destinations, in the
    // same order, as drawer rows.
    //
    // All seven are plain rows rather than expandable groups: none of them
    // has a separately routable sub-screen today. OW-012's tabs only exist
    // inside a business that has already been picked, and OW-010 is a single
    // route. A chevron opening a list of one is two taps to do one thing.
    // Business Management and Report Hub are Owner-only, so they sit here
    // rather than in manaGlobalDrawerSections, which the other three
    // workspaces share.
    ManaDrawerSection(
      icon: Icons.storefront_outlined,
      labelKey: 'business_management',
      onTap: () => context.push('/ow-012', extra: businessId),
    ),
    ManaDrawerSection(
      icon: Icons.assessment_outlined,
      labelKey: 'report_hub',
      onTap: () => context.push('/ow-010', extra: businessId),
    ),
  ];
}

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
  ConsumerState<OwnerHomeDashboardScreen> createState() =>
      _OwnerHomeDashboardScreenState();
}

class _OwnerHomeDashboardScreenState
    extends ConsumerState<OwnerHomeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ownerDashboardProvider.notifier).load(widget.businessId);
    });
  }

  Future<void> _refresh() =>
      ref.read(ownerDashboardProvider.notifier).load(widget.businessId);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ownerDashboardProvider);

    // The shell owns the Scaffold, the drawer and the one header bar.
    // Everything the old in-body header block carried now rides on the
    // shell's own bar. There were two headers before, one directly under
    // the other, both showing the business name and both showing the date
    // — see the screenshots that prompted this. One bar now.
    final data = async.valueOrNull;
    final unreadCount = data == null
        ? 0
        : data.notifications.where((n) => !n.read).length +
            data.pendingInvitations +
            data.pendingAcceptances;

    return ManaAppShell(
      userName: ref.watch(personDisplayNameProvider).valueOrNull ?? '',
      businessName: async.valueOrNull?.businessName,
      subtitle: '${manaWeekday()}, ${manaDisplayDate()}',
      leading: Container(
        color: ManaColors.brandFaint,
        child: data?.logoUrl == null
            ? Icon(Icons.storefront, color: ManaColors.brandDeep)
            // PERF: cached — this header rebuilds on every dashboard visit
            // and the logo does not change between them.
            : CachedNetworkImage(
                imageUrl: data!.logoUrl!,
                fit: BoxFit.cover,
                // A signed storage URL can expire or 404. Falling back to the
                // placeholder is right; a broken-image glyph in the header of
                // every screen is not.
                errorWidget: (_, __, ___) =>
                    Icon(Icons.storefront, color: ManaColors.brandDeep),
              ),
      ),
      onLeadingTap: () => context.push('/ow-012', extra: widget.businessId),
      actions: [
        ManaHeaderAction(
          icon: Icons.notifications_outlined,
          label: 'Notifications',
          badgeCount: unreadCount,
          onPressed: data == null
              ? null
              : () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _NotificationsSheet(
                      businessId: widget.businessId,
                      notifications: data.notifications,
                      pendingInvitations: data.pendingInvitations,
                      pendingAcceptances: data.pendingAcceptances,
                    ),
                  ),
        ),
        ManaHeaderAction(
          icon: Icons.search,
          label: 'Universal Search',
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => _UniversalSearchSheet(businessId: widget.businessId),
          ),
        ),
      ],
      sections: [
        ..._ownerDrawerSections(context, widget.businessId),
        ...manaGlobalDrawerSections(
          onProfile: () => context.push('/ow-016'),
          onSwitchWorkspace: () => context.go('/lr-012'),
          onSwitchRole: () => context.go('/lr-013', extra: widget.businessId),
          onSettings: () =>
              context.push('/ow-settings', extra: widget.businessId),
          onLogout: () {
            ref.read(authFlowProvider.notifier).reset();
            context.go('/lr-009');
          },
        ),
      ],
      bottomNavigationBar: _FooterNav(businessId: widget.businessId),
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
          data: (data) => AutoRefresh(
            onRefresh: _refresh,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.only(bottom: ManaSpacing.xxl),
                children: [
                  // No header here any more — identity, date, notifications
                  // and search all live on the shell's single bar above.
                  const SizedBox(height: ManaSpacing.md),
                  // Staggered entrance so sections resolve in reading order
                  // rather than the whole page popping in at once. 30ms apart and
                  // capped at 8, so the last card is in place ~240ms after the
                  // first — fast enough that it reads as the page settling, not
                  // as an animation being performed at you. Skipped entirely
                  // under reduce-motion.
                  for (final (i, section) in <Widget>[
                    _SectionCard(
                      title: ref.t('todays_business_summary'),
                      child: _BfRow(data: data),
                    ),
                    _SectionCard(
                      title: ref.t('quick_actions'),
                      child: _QuickActions(businessId: widget.businessId),
                    ),
                    _SectionCard(
                      title: ref.t('live_business_activity'),
                      onSeeAll: data.liveActivity.isEmpty ? null : () {},
                      child: _LiveActivity(items: data.liveActivity),
                    ),
                    _SectionCard(
                      title: ref.t('attention_required'),
                      child: _AttentionRequired(
                          businessId: widget.businessId,
                          cards: data.attentionRequired),
                    ),
                  ].indexed)
                    ManaAppear(index: i, child: section),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState(Object e) {
    // A timed-out session is not a load failure and Retry cannot fix it —
    // the same dead token goes back out. Send the person to PIN entry,
    // which re-mints, and say so in words rather than showing
    // "PostgrestException(... JWT expired ...)".
    final expired = NetworkErrorHandler.isSessionExpired(e);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(expired ? Icons.lock_clock : Icons.cloud_off,
                size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(
                expired ? ref.t('session_timed_out') : ref.t('could_not_load_dashboard')),
            const SizedBox(height: ManaSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.md),
              child: ManaText.raw(
                expired
                    ? NetworkErrorHandler.sessionExpiredMessage
                    : e.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      expired ? ManaColors.textSecondary : ManaColors.statusBad,
                ),
              ),
            ),
            const SizedBox(height: ManaSpacing.md),
            expired
                ? ElevatedButton(
                    onPressed: () => context.go('/lr-009'),
                    child: ManaText.raw(ref.t('enter_pin')),
                  )
                : ElevatedButton(
                    onPressed: _refresh, child: ManaText.raw(ref.t('retry'))),
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
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.md),
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
                padding:
                    EdgeInsets.only(bottom: i == rows - 1 ? 0 : ManaSpacing.sm),
                child: const Row(
                  children: [
                    Expanded(
                        child: ManaSkeleton(height: 32, radius: ManaRadius.sm)),
                    SizedBox(width: ManaSpacing.sm),
                    Expanded(
                        child: ManaSkeleton(height: 32, radius: ManaRadius.sm)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsSheet extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('notifications'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
            if (pendingInvitations > 0 || pendingAcceptances > 0)
              const Divider(),
            Expanded(
              child: notifications.isEmpty
                  ? Center(
                      child: ManaText.raw(
                        pendingInvitations > 0 || pendingAcceptances > 0
                            ? ref.t('nothing_else_to_report')
                            : ref.t('no_notifications_yet'),
                        style: TextStyle(color: ManaColors.textSecondary),
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
                            n.read
                                ? Icons.notifications_none
                                : Icons.notifications_active,
                            color: n.read
                                ? ManaColors.textSecondary
                                : ManaColors.brand,
                          ),
                          title: ManaText.raw(n.label,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: ManaText.raw(n.type,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: ManaColors.textSecondary)),
                          trailing: ManaText.raw(
                              DateFormat('d MMM, hh:mm a').format(n.timestamp),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: ManaColors.textSecondary)),
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
  ConsumerState<_UniversalSearchSheet> createState() =>
      _UniversalSearchSheetState();
}

class _UniversalSearchSheetState extends ConsumerState<_UniversalSearchSheet> {
  final _query = TextEditingController();
  bool _searching = false;
  String? _error;
  /// All matches, with each one's roles in THIS business. A name is not
  /// unique, so a search for "sai" legitimately returns several people —
  /// showing only the first is how the Owner opens the wrong record.
  List<({CustomerSummary person, List<String> roles})> _found = const [];

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _found = const [];
    });
    final isMlid = RegExp(r'^ML[A-Za-z]{2}\d+$').hasMatch(query);
    final digitsOnly = RegExp(r'^\d+$').hasMatch(query);
    try {
      final result = await ref
          .read(customerListProvider.notifier)
          .searchIdentity(
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
      // One membership query for ALL matches rather than one per person —
      // a name search can return 25, and 25 serial round trips on a village
      // connection is a hang, not a search.
      final ids = [
        for (final r in result)
          if (r.personId != null) int.parse(r.personId!),
      ];
      final roleRows = ids.isEmpty
          ? const <Map<String, dynamic>>[]
          : ((await Supabase.instance.client
                  .from('business_members')
                  .select('person_id, role')
                  .eq('business_id', widget.businessId)
                  .inFilter('person_id', ids)) as List)
              .cast<Map<String, dynamic>>();
      final rolesByPerson = <String, List<String>>{};
      for (final row in roleRows) {
        rolesByPerson
            .putIfAbsent(row['person_id'].toString(), () => [])
            .add(row['role'] as String);
      }
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = [
          for (final person in result)
            (person: person, roles: rolesByPerson[person.personId] ?? const []),
        ];
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
            ManaText.raw(ref.t('search'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
                ref.t('search_by_phone_mlid_aadhaar_name'),
                style:
                    TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: InputDecoration(labelText: ref.t('search')),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                FilledButton(
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(ref.t('search')),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            if (_error != null)
              ManaText.raw(_error!,
                  style: TextStyle(
                      color: ManaColors.statusBad, fontSize: 13)),
            for (final match in _found)
              Card(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: ManaText.raw(match.person.fullName),
                      subtitle: ManaText.raw([
                        match.person.mlid,
                        if (match.person.fatherHusbandName.isNotEmpty)
                          match.person.fatherHusbandName,
                      ].join(' · ')),
                    ),
                    if (match.roles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.md),
                        child: ManaText.raw(ref.t('not_a_member_of_business'),
                            style: TextStyle(
                                color: ManaColors.textSecondary, fontSize: 13)),
                      )
                    else
                      // A person can hold more than one role in the same
                      // business (e.g. an Owner who is also an Agent) —
                      // one tappable row per role rather than guessing.
                      ...match.roles.map((role) => ListTile(
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
  const _MembershipRow(
      {required this.label, required this.subtitle, required this.onTap});

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
              Icon(Icons.mark_email_unread_outlined,
                  color: ManaColors.brand),
              const SizedBox(width: ManaSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ManaText.raw(label,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ManaText.raw(subtitle,
                        style: TextStyle(
                            fontSize: 13, color: ManaColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: ManaColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Shared section wrapper ------------------------------------------------

class _SectionCard extends ConsumerWidget {
  final String title;
  final Widget child;
  final VoidCallback? onSeeAll;
  const _SectionCard({required this.title, required this.child, this.onSeeAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: ManaText.raw(title,
                      style: Theme.of(context).textTheme.titleMedium)),
              if (onSeeAll != null)
                TextButton(
                    onPressed: onSeeAll, child: ManaText.raw(ref.t('see_all'))),
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
class _BfRow extends ConsumerWidget {
  final OwnerDashboardData data;
  const _BfRow({required this.data});

  void _openSheet(BuildContext context, WidgetRef ref) {
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
            ManaText.raw(ref.t('todays_business_summary'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.md),
            _TodaysSummary(data: data),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // excludeSemantics so the row is announced once, as one control, rather
    // than as a button plus a stray "₹0" — the amount is folded into the
    // label instead.
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Brought forward, ${_currency.format(data.openingBalance)}. '
          "Opens today's business summary",
      child: ManaPressable(
        onTap: () => _openSheet(context, ref),
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
                  ManaInfoWord(ref.t('brought_forward'),
                      infoKey: 'bf',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: ManaSpacing.sm),
                  ManaText.raw('=',
                      style: TextStyle(color: ManaColors.textSecondary)),
                  const SizedBox(width: ManaSpacing.sm),
                  Expanded(
                    child: ManaAmount(data.openingBalance),
                  ),
                  Icon(Icons.chevron_right,
                      color: ManaColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodaysSummary extends ConsumerWidget {
  final OwnerDashboardData data;
  const _TodaysSummary({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <(String, int, bool)>[
      (ref.t('opening_balance'), data.openingBalance, false),
      (ref.t('todays_collections'), data.todaysCollections, false),
      (ref.t('todays_loan_distribution'), data.todaysLoanDistribution, false),
      (ref.t('todays_investments'), data.todaysInvestments, false),
      (ref.t('todays_withdrawals'), data.todaysWithdrawals, false),
      (ref.t('todays_expenses'), data.todaysExpenses, false),
      (ref.t('todays_outstanding'), data.todaysOutstanding, false),
      (ref.t('todays_difference'), data.todaysDifference, true),
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
                      Expanded(
                          child: ManaText.raw(r.$1,
                              style: const TextStyle(fontSize: 13))),
                      // ManaAmount rather than a raw formatted string: tabular
                      // figures so this column of rupee values actually aligns
                      // digit-for-digit, and a spoken form ("Today's
                      // Collections, 4,500 rupees") instead of a screen reader
                      // spelling out the symbol and every comma.
                      ManaAmount(
                        r.$2,
                        size: ManaAmountSize.compact,
                        tone: r.$3 && r.$2 < 0
                            ? ManaAmountTone.negative
                            : ManaAmountTone.neutral,
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
                Expanded(
                  child: ManaText.raw(ref.t('closing_balance'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
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
//
// PRESENTATION (changed this pass): the three groups used to render one
// under another, all expanded. That is 14 tiles stacked before the rest of
// the dashboard, so Investors was below the fold on a 640dp phone and the
// live-activity feed under it was effectively unreachable without a long
// scroll. They are now behind a row of category chips — one group visible
// at a time, the others one tap away. Same tiles, same destinations, a
// third of the height. Chips rather than an accordion or tabs because this
// screen already uses ChoiceChip for filtering elsewhere (OW-003/OW-004),
// so the affordance is one the Owner has already learned.
class _QuickActions extends ConsumerStatefulWidget {
  final String businessId;
  const _QuickActions({required this.businessId});

  @override
  ConsumerState<_QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends ConsumerState<_QuickActions> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final businessId = widget.businessId;
    final groups = <(String, List<(IconData, String, String, String?)>)>[
      (
        ref.t('customers'),
        [
            // Registration on the doorstep: opens OW-004 with the Add
            // Customer sheet already up, so signing someone up in the field
            // is two taps from Home rather than a list-then-hunt-for-the-
            // button trip.
            (Icons.person_add_alt_1_outlined, ref.t('register_customer'), '/ow-004?action=register', null),
            (Icons.request_quote_outlined, ref.t('new_loan'), '/ow-005', null),
            (Icons.point_of_sale_outlined, ref.t('collections'), '/ow-006', null),
            // 'Search Customers' removed (item 4.1) — the header's Universal
            // Search covers it, and OW-004 has its own search field.
            (Icons.people_outline, ref.t('customer_management'), '/ow-004', null),
            (Icons.inbox_outlined, ref.t('loan_requests'), '/ow-loan-requests', null),
            // BUG FIXED this pass: OW-015 was a real, fully-built screen
            // with zero links from anywhere in the app.
          (Icons.groups_2_outlined, ref.t('group_loans'), '/ow-015', null),
        ],
      ),
      (
        ref.t('workforce'),
        [
            // 'Register New Agent' and 'Add Existing Agent' removed (item
            // 5.1) — both already exist as header actions inside Workforce
            // Management, which this tile opens.
            (Icons.groups_outlined, ref.t('workforce_management'), '/ow-002', null),
            (Icons.lock_clock_outlined, ref.t('day_closure'), '/ow-011', null),
            (Icons.menu_book_outlined, ref.t('daily_record_book'), '/ow-009', null),
            (Icons.bar_chart_outlined, ref.t('reports'), '/ow-010', null),
            // BUG FIXED this pass: OW-013 was a real, fully-built screen
            // with zero links from anywhere in the app.
          (Icons.fact_check_outlined, ref.t('account_review'), '/ow-013', null),
        ],
      ),
      (
        ref.t('investor'),
        [
          (
            Icons.person_add_alt_1_outlined,
            ref.t('add_existing_investor'),
            '/ow-003',
            'open=existing'
          ),
          (
            Icons.inbox_outlined,
            ref.t('investor_requests'),
            '/ow-003',
            'filter=Pending%20Acceptance'
          ),
          (Icons.savings_outlined, ref.t('investor_management'), '/ow-003', null),
          // BUG FIXED this pass: investment_withdrawal_requests had a
          // real INSERT path with no reachable Owner review screen at
          // all — requests sat Pending forever.
          (
            Icons.payments_outlined,
            ref.t('withdrawal_requests'),
            '/ow-withdrawal-requests',
            null
          ),
        ],
      ),
    ];

    // Defensive: a group list that shrinks (a permission change, a future
    // role split) must not leave _selected pointing past the end.
    final index = _selected.clamp(0, groups.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap, not a Row or a scrolling strip: these are translated labels,
        // so their width is data. In Kannada at 2.0x three chips do not fit
        // on one line, and a Row would overflow — the exact bug class this
        // codebase has shipped five times.
        Wrap(
          spacing: ManaSpacing.xs,
          runSpacing: ManaSpacing.xs,
          children: [
            for (final (i, (title, _)) in groups.indexed)
              ChoiceChip(
                label: ManaText.raw(title),
                selected: index == i,
                // onSelected fires for a tap on the already-selected chip
                // too; ignoring deselection keeps one group always showing,
                // rather than collapsing to an empty panel.
                onSelected: (_) => setState(() => _selected = i),
              ),
          ],
        ),
        const SizedBox(height: ManaSpacing.sm),
        _QuickActionGroup(
          businessId: businessId,
          actions: groups[index].$2,
        ),
      ],
    );
  }
}

class _QuickActionGroup extends StatelessWidget {
  final String businessId;
  final List<(IconData, String, String, String?)> actions;
  const _QuickActionGroup(
      {required this.businessId, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The group's own title heading is gone — the selected chip above
        // already names the group, and repeating it directly underneath was
        // two labels saying the same thing.
        //
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

class _LiveActivity extends ConsumerWidget {
  final List<ActivityItem> items;
  const _LiveActivity({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: ManaText.raw(ref.t('no_activity_today'),
              style: TextStyle(color: ManaColors.textSecondary)),
        ),
      );
    }
    return Card(
      child: Column(
        children: items
            .take(5)
            .map((a) => ListTile(
                  leading: Icon(Icons.circle,
                      size: 8, color: ManaColors.brand),
                  title: ManaText.raw(a.label,
                      style: const TextStyle(fontSize: 13)),
                  trailing: ManaText.raw(
                      DateFormat('hh:mm a').format(a.timestamp),
                      style: TextStyle(
                          fontSize: 13, color: ManaColors.textSecondary)),
                ))
            .toList(),
      ),
    );
  }
}

// --- C6 Attention Required --------------------------------------------

class _AttentionRequired extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    if (cards.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: ManaText.raw(ref.t('nothing_needs_attention'),
              style: TextStyle(color: ManaColors.textSecondary)),
        ),
      );
    }
    return Column(
      children: cards
          .map((c) => Card(
                child: ListTile(
                  leading: Icon(Icons.priority_high,
                      color: c.priority == 'High'
                          ? ManaColors.statusBad
                          : ManaColors.statusWarn),
                  title: ManaText.raw(c.type,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: ManaText.raw(
                      'Updated ${DateFormat('d MMM, hh:mm a').format(c.lastUpdated)}',
                      style: const TextStyle(fontSize: 13)),
                  trailing: ManaStatusPill(
                    label: '${c.count}',
                    status:
                        c.priority == 'High' ? ManaStatus.bad : ManaStatus.warn,
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
