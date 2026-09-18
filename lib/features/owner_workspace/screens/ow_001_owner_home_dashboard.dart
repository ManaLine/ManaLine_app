import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/auto_refresh.dart';
import '../../../design/tokens/icons.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_info_popup.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_header.dart';
import '../../../design/components/mana_app_shell.dart';
import '../../../design/components/mana_business_logo.dart';
import '../../../shared/notification_bell.dart';
import '../../../shared/person_identity.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/motion.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/owner_api_service.dart';
import '../state/owner_workspace_state.dart';
import '../state/customer_state.dart';
import '../state/business_management_state.dart'
    show businessManagementApiServiceProvider;
import 'ow_pre_existing_loan_sheet.dart';
import '../state/global_workflow_state.dart'
    show MemberType, MemberTypeLabel, ManaRoleOutcome, globalWorkflowApiServiceProvider;
import '../state/investor_state.dart' show investorApiServiceProvider, InvestorSummary;
import 'ow_004_customer_management.dart'
    show CustomerProfileScreen, ManaAddCustomerSheet;
import 'ow_003_investor_management.dart' show InvestorProfileScreen;
import 'ow_002_workforce_management.dart' show AgentProfileScreen;
import '../../../shared/widgets/workspace_nav.dart';
import '../../../shared/widgets/workspace_actions.dart'
    show ManaMemberKind;
import '../../../shared/app_actions.dart';
import '../../../shared/location_api_service.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/mana_time.dart';


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
      labelKey: 'agents',
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
      icon: ManaIcons.investor,
      labelKey: 'investors',
      actions: [
        ManaDrawerAction(
          labelKey: 'investor_management',
          onTap: () => context.push('/ow-003', extra: businessId),
        ),
      ],
    ),
    // EVERYONE, in one list. Agents, investors and customers each have their
    // own screen above; nothing showed the whole book's people together, so
    // "who is in this business" could only be answered three screens at a
    // time. Opens Business Management on its Members tab -- the roster that
    // already exists, rather than a second one to keep in step with it.
    // A DESTINATION, NOT A GROUP. This was a section holding exactly one
    // action, labelled the same word as the section -- so tapping Members
    // opened a list whose only entry was Members, and the roster was two taps
    // away. Reported from a handset: "no need of dropdown and again showing
    // members to select, direct tap on members show the list."
    //
    // ManaDrawerSection.onTap already existed for this and says so in its own
    // doc: "giving it a chevron that opens a list containing only itself
    // would be two taps to do one thing." This row simply never used it.
    ManaDrawerSection(
      icon: Icons.groups_outlined,
      labelKey: 'members',
      onTap: () => context.push('/ow-012?tab=members', extra: businessId),
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

  /// Pull down to re-derive the figures, then reload them.
  ///
  /// Not just load(): BF is a cached derivation and this book carried a figure
  /// Rs 2,37,800 too high for sixteen days after a withdrawal. A reload would
  /// have fetched that number again, correctly and uselessly.
  Future<void> _refresh() =>
      ref.read(ownerDashboardProvider.notifier).refresh(widget.businessId);


  // _addCustomer went with the + above. The add-then-lend flow it opened is
  // NOT lost: /customer-new still ends with that choice, and the header + on
  // every customer screen still routes there. Home simply is not one of them.

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ownerDashboardProvider);

    // The shell owns the Scaffold, the drawer and the one header bar.
    // Everything the old in-body header block carried now rides on the
    // shell's own bar. There were two headers before, one directly under
    // the other, both showing the business name and both showing the date
    // — see the screenshots that prompted this. One bar now.
    final data = async.valueOrNull;
    // The header badge count moved to ManaNotificationBell, which counts
    // actionable items from app.my_inbox_actions rather than summing this
    // dashboard's own notification list with two pending counters.

    return ManaAppShell(
      // No + Expense floating button.
      //
      // It sat over the bottom-right of the dashboard -- the one screen an
      // Agent is NOT on when they buy petrol between two villages. The same
      // action is in the header of every Owner and Agent screen now, so it is
      // available where the money is actually spent, and the dashboard gets
      // its corner back.
      userName: ref.watch(personDisplayNameProvider).valueOrNull ?? '',
      businessName: async.valueOrNull?.businessName,
      subtitle: '${manaWeekday()}, ${manaDisplayDate()}',
      leading: ManaBusinessLogo(logoUrl: data?.logoUrl),
      onLeadingTap: () => context.push('/ow-012', extra: widget.businessId),
      actions: [
        // Was a bottom sheet carrying this dashboard's own notifications plus
        // pendingInvitations/pendingAcceptances — one of six places
        // invitations surfaced. It now opens the shared /notifications inbox,
        // which reads both directions live via app.my_inbox_actions and works
        // the same in every workspace.
        const ManaNotificationBell(),
        // DRAFTS, beside the bell, because a draft nobody can reach is a loan
        // quietly deleted.
        //
        // A loan refused for float is parked as a draft and the refusal says
        // so -- "Saved as a draft. Nothing you entered is lost." That sentence
        // was a promise the app could not keep from this workspace: AG-005
        // exists and is routed, and nothing on the Owner's side linked to it.
        // Reported from a handset: "saved as draft but no screen showing
        // drafts".
        //
        // SHOWN ONLY WHEN THERE IS SOMEWHERE TO GO. AG-005 is keyed by an
        // AGENT membership -- drafts are parked under the collecting agent --
        // so an Owner who is not also an agent of this book has no drafts of
        // their own and would get an empty screen that reads as a bug. On
        // every live book the Owner IS also an agent, which is the case this
        // serves.
        //
        // WORTH SAYING PLAINLY: a draft parked under ANOTHER agent belongs to
        // that agent's screen and is not reachable here. That is unchanged by
        // this button, and it matters less now that the float is checked at
        // step 3 -- an Owner should rarely produce one of these at all.
        if (ManaSession.instance.lastAgentMembershipId != null)
          ManaHeaderAction(
            icon: Icons.drafts_outlined,
            label: ref.t('drafts'),
            onPressed: () => context.push('/ag-005', extra: widget.businessId),
          ),
        // NO + ON HOME, deliberately, and this is the one screen where that
        // is right.
        //
        // The + means "add a member of THIS SCREEN's kind" -- an Agent on
        // Workforce, an Investor on Investor Management, a Customer on a
        // customer screen. Home has no kind. A + here would have to ask which
        // role, which is exactly what the magnifier beside it already does, so
        // the two would be one button drawn twice.
        //
        // Removing it rather than renaming it keeps + meaning one thing
        // everywhere it appears. On Home the magnifier is the way in: it finds
        // anyone and asks.
        ManaHeaderAction(
          icon: Icons.search,
          label: 'Universal Search',
          // A pushed screen, not a bottom sheet. As a sheet the field opened
          // at the bottom of the display under the keyboard, so the thing you
          // had come to type into was the last thing on screen and the results
          // grew downwards off the edge — they were laid out in a plain
          // non-scrolling Column, so a name search matching twenty people
          // overflowed rather than scrolling.
          //
          // The ROUTE, not a bare MaterialPageRoute. This was the last screen
          // still pushed above the router's own pages, which router.dart names
          // as the shape that broke the Agent's back button -- and it left the
          // router's location on /ow-001 while Universal Search was the thing
          // on screen. The header's + reads that location to decide whom it
          // adds, so the one screen you reach a stranger from was the one
          // screen whose + could not know what it was looking at.
          onPressed: () => context.push('/ow-search', extra: widget.businessId),
        ),
      ],
      sections: [
        ..._ownerDrawerSections(context, widget.businessId),
        ...manaGlobalDrawerSections(
          onProfile: () => context.push('/ow-016'),
          onSwitchWorkspace: () => context.go('/lr-012?pick=1'),
          onSwitchRole: () => context.go('/lr-013', extra: widget.businessId),
          onSettings: () =>
              context.push('/ow-settings', extra: widget.businessId),
          onLogout: () {
            ref.read(authFlowProvider.notifier).reset();
            context.go('/lr-009');
          },
        ),
      ],
      bottomNavigationBar: ManaWorkspaceNav(
          workspace: ManaWorkspace.owner,
          businessId: widget.businessId,
          currentIndex: 0),
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

// Reuses the same identity-search RPC already wired for OW-004/OW-005/
// AG-007's customer search (owner_search_person, MLID/phone/Aadhaar/name)
// — the only cross-role identity lookup this backend actually exposes.
// After a match, resolves the person's role in THIS business via
// business_members so the Owner lands on the right management screen
// directly, instead of guessing between Customer/Workforce/Investor.
/// Universal Search — find a person anywhere in this business by phone, MLID,
/// Aadhaar or name, then jump to whichever role they hold.
///
/// The search field lives in the app bar and the matches scroll beneath it,
/// which is the only arrangement that works on a phone: the field stays put
/// and visible above the keyboard while the list under it grows.
class UniversalSearchScreen extends ConsumerStatefulWidget {
  final String businessId;

  /// The role this search adds in, when the screen it was opened from already
  /// answers that question.
  ///
  /// TWO CONTROLS, TWO JOBS. The header's + and its magnifier had both been
  /// pointed here and so did exactly the same thing, which is what made three
  /// buttons on OW-005 serve one purpose. They are told apart now:
  ///
  ///   + ........ adds a member of THIS SCREEN's kind. On Workforce that is an
  ///              Agent, on Investor Management an Investor, everywhere else a
  ///              Customer. It still searches first -- adding somebody always
  ///              begins by looking for them -- it simply does not ask a
  ///              question the screen has already answered.
  ///
  ///   magnifier  finds anyone and asks which role. Null here.
  ///
  /// This is what "add them as customer" on the Agent and Investor screens
  /// was: the + landed on the role-choosing search, and its empty state
  /// offered the one sheet it knew, which made customers.
  final ManaMemberKind? fixedRole;

  const UniversalSearchScreen({
    super.key,
    required this.businessId,
    this.fixedRole,
  });

  @override
  ConsumerState<UniversalSearchScreen> createState() =>
      _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends ConsumerState<UniversalSearchScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  bool _searching = false;
  bool _searched = false;

  /// Set while a profile is being loaded for a tapped role. Agent and Investor
  /// need a round trip before their screen can be opened, and without this the
  /// row looks dead for the second it takes on a village connection.
  String? _opening;

  /// Set while a person is being attached to this business, keyed by
  /// person_id, so only that card's button disables.
  String? _adding;
  String? _error;
  /// All matches, with each one's roles in THIS business. A name is not
  /// unique, so a search for "sai" legitimately returns several people —
  /// showing only the first is how the Owner opens the wrong record.
  /// customerId is resolved here rather than left empty, because it is the
  /// whole difference between landing on this person and landing on a list of
  /// everyone. searchIdentity returns persons-level rows whose customerId is
  /// '' by design; without the lookup below, "open Customer" could only ever
  /// mean "open Customer Management".
  /// Active roles, the roles still WAITING to be accepted, and the customer
  /// row behind a Customer membership.
  ///
  /// Pending is its own list rather than a flag on the role, because the two
  /// are drawn as different things: an active role is a door you can open, a
  /// pending one is a sentence saying what was asked and that nobody has
  /// answered.
  List<({
    CustomerSummary person,
    List<String> roles,
    List<String> pendingRoles,
    String? customerId
  })> _found = const [];

  @override
  void initState() {
    super.initState();
    // Opening a search screen and then having to tap the field is a wasted
    // tap on the only thing this screen does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _loadVillages();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The two enums say the same thing to different halves of the app --
  /// ManaMemberKind is what the header knows, MemberType is what the RPC
  /// wrapper takes. Mapped in one place so a fifth role cannot be added to one
  /// and not the other without this failing to compile.
  MemberType _memberTypeFor(ManaMemberKind kind) => switch (kind) {
        ManaMemberKind.customer => MemberType.customer,
        ManaMemberKind.agent => MemberType.agent,
        ManaMemberKind.investor => MemberType.investor,
      };

  /// Adding somebody the search found who is not in this business yet.
  ///
  /// THE DEAD END THIS REPLACES: a search that found a real person with no
  /// role here printed "Not a member of this business." and stopped. The Add
  /// button appeared only when the search found NOBODY -- so the app offered
  /// to create a brand new person, and offered nothing at all for the person
  /// it had just put on screen. Searching a phone number, recognising the
  /// name, and then having no way to act on it is the case this screen exists
  /// for.
  ///
  /// Search, choose a role, add: one path for all three kinds of member, at
  /// the Owner's instruction. app.attach_person_to_business is the whole
  /// backend for it -- it checks ownership itself, refuses a role that is not
  /// one of the three, and writes the membership, the role-side row and (for
  /// an Agent) the permissions together, which is what a membership with no
  /// agents row taught this project to insist on.
  /// Which roles this person holds here. One, or several, or none chosen.
  ///
  /// MULTI-SELECT, because a person is routinely two things at once -- an
  /// agent who also borrows, an investor who is also a customer -- and
  /// business_members has always allowed it. Asking one at a time meant
  /// walking the whole search twice for one person.
  ///
  /// Returns null when the Owner backs out, which is not the same as choosing
  /// nothing; the Add button is simply disabled until something is ticked.
  Future<List<MemberType>?> _askRoles() => showModalBottomSheet<List<MemberType>>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          final chosen = <MemberType>{};
          return StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.sm),
                    child: ManaText.raw(ref.t('select_role'),
                        style: ManaType.cardTitle),
                  ),
                  // Named, not iconed. Three unlabelled glyphs competing for
                  // one corner is what the add actions on Customer Management
                  // were before they became rows carrying their names.
                  for (final option in MemberType.values)
                    CheckboxListTile(
                      value: chosen.contains(option),
                      title: ManaText.raw(ref.t(option.name)),
                      // Said on the row itself, not only in the confirmation
                      // afterwards: an Owner ticking Agent is choosing to send
                      // a request, and that is worth knowing BEFORE pressing
                      // Add rather than after.
                      subtitle: option.needsAcceptance
                          ? ManaText.raw(ref.t('role_must_accept_note'),
                              style: ManaType.note)
                          : null,
                      onChanged: (on) => setSheetState(() {
                        if (on == true) {
                          chosen.add(option);
                        } else {
                          chosen.remove(option);
                        }
                      }),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: chosen.isEmpty
                            ? null
                            : () => Navigator.pop(sheetContext, chosen.toList()),
                        child: ManaText.raw(ref.t('add_to_this_business')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  /// What to say once the server has answered.
  ///
  /// Names the two outcomes separately. An Agent or Investor is ASKED and sits
  /// at Pending Invitation until they answer; a Customer is in immediately.
  /// One word for both would tell the Owner an agent is on their book when
  /// that agent has not replied, and they would find out by wondering why
  /// nothing was collected.
  String _outcomeMessage(List<ManaRoleOutcome> outcomes) {
    final waiting = outcomes.where((o) => o.isWaiting).map((o) => o.role);
    final joined = outcomes.where((o) => !o.isWaiting).map((o) => o.role);
    final parts = <String>[
      if (joined.isNotEmpty)
        ref.t('added_as_roles_note').replaceAll('{roles}', joined.join(', ')),
      if (waiting.isNotEmpty)
        ref.t('request_sent_as_roles_note')
            .replaceAll('{roles}', waiting.join(', ')),
    ];
    return parts.join(' ');
  }

  /// Is this book still being brought across?
  ///
  /// Decides which KIND of loan the next step offers, which is a money
  /// question, not a cosmetic one: a pre-existing loan is a balance carried in
  /// through app.migrate_loan, while a new loan is cash leaving the till today
  /// through the lending flow and it moves BF. Writing one when the Owner
  /// meant the other is the sort of wrong number nobody notices.
  ///
  /// Unknown counts as LOCKED. Being unable to read the flag is not evidence
  /// that a migration is open, and offering to record a pre-existing loan on a
  /// running book is the more damaging of the two mistakes.
  Future<bool> _migrationOpen() async {
    try {
      final detail = await ref
          .read(businessManagementApiServiceProvider)
          .fetchBusinessDetail(businessId: widget.businessId);
      return detail.migrationLocked == false;
    } catch (_) {
      return false;
    }
  }

  /// Offer the loan, once the person is a Customer here.
  ///
  /// THE OWNER'S RULE, verbatim: while the migration is open, ASK whether this
  /// loan is pre-existing or new; once it is locked, only new. The question
  /// disappears by itself when a book goes live, so nobody is ever asked
  /// something with one answer.
  Future<void> _offerLoan({
    required String mlid,
    required String fullName,
    String? customerId,
  }) async {
    final open = await _migrationOpen();
    if (!mounted) return;

    var preExisting = false;
    if (open) {
      final choice = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.sm),
                child: ManaText.raw(ref.t('which_kind_of_loan'),
                    style: ManaType.cardTitle),
              ),
              ListTile(
                title: ManaText.raw(ref.t('pre_existing_loan')),
                subtitle: ManaText.raw(ref.t('pre_existing_loan_note'),
                    style: ManaType.note),
                onTap: () => Navigator.pop(sheetContext, true),
              ),
              ListTile(
                title: ManaText.raw(ref.t('new_loan')),
                subtitle: ManaText.raw(ref.t('new_loan_cash_note'),
                    style: ManaType.note),
                onTap: () => Navigator.pop(sheetContext, false),
              ),
              const SizedBox(height: ManaSpacing.md),
            ],
          ),
        ),
      );
      // Backed out. Not an error and not a default -- the person is already
      // added, and nothing about a loan should be assumed from silence.
      if (choice == null || !mounted) return;
      preExisting = choice;
    }

    if (!preExisting) {
      if (customerId == null) {
        // A new loan is issued against a customer row, and the found-person
        // path has only a person. Saying so beats opening a screen that
        // cannot find them.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: ManaText.raw(ref.t('open_customer_to_lend_note')),
        ));
        return;
      }
      context.push('/ow-005?customerId=$customerId', extra: widget.businessId);
      return;
    }

    final saved = await manaEnterPreExistingLoan(
      context,
      ref,
      businessId: widget.businessId,
      mlid: mlid,
      fullName: fullName,
    );
    if (!saved || !mounted) return;
    await _offerAnother(fullName);
  }

  /// Save and enter another, or close.
  ///
  /// Asked because this screen is used in runs -- an Owner bringing a book
  /// across does twenty of these in a sitting, and making them find the search
  /// box again between each one is the irritation the whole door exists to
  /// remove. Closing is the other half of the same courtesy: a run that cannot
  /// end without backing out reads as a trap.
  Future<void> _offerAnother(String fullName) async {
    final again = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: ManaText.raw(
            ref.t('loan_saved_for_note').replaceAll('{name}', fullName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: ManaText.raw(ref.t('close')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: ManaText.raw(ref.t('save_and_enter_another')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (again == true) {
      // Cleared, focused, ready for the next name. Leaving the last person's
      // query in the box means the next search starts by deleting it.
      _query.clear();
      setState(() {
        _found = const [];
        _searched = false;
      });
      return;
    }
    await _search();
  }

  Future<void> _addToBusiness(CustomerSummary person) async {
    final personId = person.personId;
    if (personId == null || personId.isEmpty) return;

    // The screen may already know. Workforce adds Agents; Investor Management
    // adds Investors; asking again would be a question with one answer.
    final fixed = widget.fixedRole;
    final types =
        fixed != null ? [_memberTypeFor(fixed)] : await _askRoles();
    if (types == null || types.isEmpty || !mounted) return;

    setState(() => _adding = personId);
    final outcomes = await NetworkErrorHandler.run(context, () async {
      return ref.read(globalWorkflowApiServiceProvider).attachNewPersonInRoles(
            businessId: widget.businessId,
            personId: personId,
            types: types,
          );
    });
    if (!mounted) return;
    setState(() => _adding = null);
    if (outcomes == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(_outcomeMessage(outcomes))),
    );

    // A Customer is the only role a loan belongs to. An Agent or Investor who
    // has not accepted yet certainly has no loan, and offering one would be
    // the app acting on an answer nobody has given.
    if (types.contains(MemberType.customer)) {
      await _offerLoan(mlid: person.mlid, fullName: person.fullName);
      if (!mounted) return;
    }

    // Re-run the search rather than adding the role to the list in memory:
    // the roles on these cards are what the server says they are, and a list
    // that guesses is a list that can be wrong about who is in the business.
    await _search();
  }

  /// Registering somebody the directory has never heard of.
  ///
  /// Routed by the role this search is adding in, because the two paths make
  /// genuinely different things: the sheet creates a person AND a customer of
  /// this business, while OW-014 creates a person and attaches them as an
  /// Agent or Investor.
  Future<void> _addNewPerson() async {
    final fixed = widget.fixedRole;

    // WHICH ROLES, ASKED BEFORE ANYTHING IS CREATED.
    //
    // This branch used to make a Customer whatever was intended, because the
    // screen that knows the role answers with fixedRole and the GLOBAL search
    // has no fixedRole -- so it fell through to the customer sheet. Renaming
    // the button to "Add a User" made the label honest and left the behaviour
    // exactly as wrong, which is worse: a label that promises a question it
    // never asks. Filing an intended agent as a borrower is the specific
    // mistake this whole search exists to prevent.
    final types = fixed != null ? [_memberTypeFor(fixed)] : await _askRoles();
    if (types == null || types.isEmpty || !mounted) return;

    // Registering a brand new person happens through ONE of two doors, and
    // which one depends on whether they are a Customer here. The customer
    // sheet creates a person AND their customer row; OW-014 creates a person
    // and attaches them as an Agent or Investor. Neither can create the other
    // side, so whichever runs first creates the person and the rest of the
    // roles are attached afterwards by person_id.
    if (!types.contains(MemberType.customer)) {
      final first = types.first;
      // ?new=1 -- this button only exists under "No identity found", so the
      // search has already run and already answered. Without it OW-014 opened
      // on its own "Search Existing MLID" step and asked for the same person
      // again by mobile number or MLID, which is the app disbelieving the
      // answer it had just given.
      await context.push(
          '/ow-014?type=${_workflowTypeFor(first)}&new=1',
          extra: widget.businessId);
      if (!mounted) return;
      // The remaining roles cannot be applied from here: OW-014 does not hand
      // back the person it made, and guessing which search result is theirs in
      // a village where several people share a name is how the wrong record
      // gets a membership. Searching again and adding is two taps and is
      // never wrong.
      if (types.length > 1) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: ManaText.raw(ref.t('search_again_for_other_roles_note')),
        ));
      }
      _search();
      return;
    }

    // The sheet pops the new customerId when "Add & Issue Loan" was pressed
    // and null when it was "Add Only" -- and null is also what cancelling
    // gives. onCreated fires on creation regardless, which is the only way to
    // learn the person_id on the "Add Only" path.
    int? createdPersonId;
    String? createdMlid;
    final customerId = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ManaAddCustomerSheet(
        businessId: widget.businessId,
        initialQuery: _query.text.trim(),
        onCreated: (_, personId, mlid) {
          createdPersonId = personId;
          createdMlid = mlid;
        },
      ),
    );
    if (!mounted) return;

    // Everything except Customer, which the sheet has already done.
    final rest =
        types.where((t) => t != MemberType.customer).toList(growable: false);
    if (createdPersonId != null && rest.isNotEmpty) {
      final outcomes = await NetworkErrorHandler.run(context, () async {
        return ref.read(globalWorkflowApiServiceProvider).attachNewPersonInRoles(
              businessId: widget.businessId,
              personId: '$createdPersonId',
              types: rest,
            );
      });
      if (!mounted) return;
      if (outcomes != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: ManaText.raw(_outcomeMessage(outcomes))),
        );
      }
    }

    // "Add & Issue Loan" on the sheet says they want a loan next, and this
    // screen can now offer the right KIND of one. "Add Only" leaves them
    // added, which is what it says.
    if (customerId != null && createdMlid != null) {
      await _offerLoan(
        mlid: createdMlid!,
        fullName: _query.text.trim(),
        customerId: customerId,
      );
      if (!mounted) return;
    }
    _search();
  }

  /// OW-014's `type` query parameter for a role it can register.
  ///
  /// Customer is not one of them -- that screen registers Agents and
  /// Investors, and the customer sheet is the other door.
  String _workflowTypeFor(MemberType type) => switch (type) {
        MemberType.agent => ManaMemberKind.agent.workflowType,
        MemberType.investor => ManaMemberKind.investor.workflowType,
        MemberType.customer => ManaMemberKind.customer.workflowType,
      };

  /// VILLAGE FIRST, THEN THE PERSON.
  ///
  /// The Owner: "Global search - while searching a user - select village first
  /// - then search becomes easy and findable when the user count goes up."
  ///
  /// A name search across a whole book returns everyone called Lakshmi. Inside
  /// one village it returns the one they mean, and with a dozen villages that
  /// is a twelvefold cut for a single tap. It also answers the empty query:
  /// pick a village and its people are listed without typing anything.
  List<ManaVillage> _villages = const [];
  ManaVillage? _village;
  List<ManaVillagePerson> _villagePeople = const [];
  bool _loadingVillage = false;

  /// The village's people narrowed by what has been typed. Filtered in the
  /// app, because they are already in hand and a village is seventeen rows,
  /// not seventeen thousand.
  List<ManaVillagePerson> get _villageMatches =>
      [for (final p in _villagePeople) if (p.matches(_query.text)) p];

  Future<void> _loadVillages() async {
    final rows = await NetworkErrorHandler.run(
      context,
      () => ref.read(locationApiServiceProvider).businessVillages(widget.businessId),
    );
    if (!mounted) return;
    setState(() => _villages = rows ?? const []);
  }

  Future<void> _pickVillage(ManaVillage? v) async {
    setState(() {
      _village = v;
      _villagePeople = const [];
      _loadingVillage = v != null;
    });
    if (v == null) return;
    final people = await NetworkErrorHandler.run(
      context,
      () => ref.read(locationApiServiceProvider).peopleInVillage(
            businessId: widget.businessId,
            villageId: v.locationId,
          ),
    );
    if (!mounted) return;
    setState(() {
      _villagePeople = people ?? const [];
      _loadingVillage = false;
    });
  }

  /// The app's own options matching what has been typed, recomputed on every
  /// build because it is a scan of twenty-five consts and caching it would be
  /// a second copy of the query to keep in step.
  List<ManaAppAction> get _actions =>
      manaSearchActions(_query.text, ref.t);

  Widget _actionTile(ManaAppAction a) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(a.icon, color: ManaColors.brandDeep),
        title: ManaText.raw(ref.t(a.labelKey)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        // PUSHED, so Back returns to the search with the query still in the
        // box. An Owner who opens the wrong one of two similar options should
        // not have to retype three letters to try the other.
        onTap: () => context.push(
          a.path.contains('?')
              ? '${a.path}&businessId=${widget.businessId}'
              : '${a.path}?businessId=${widget.businessId}',
          extra: widget.businessId,
        ),
      );

  /// The villages this book works, offered before anything is typed.
  ///
  /// A dropdown rather than a row of chips: a dozen chips wrapped onto three
  /// lines on a real handset and pushed the thing being searched below the
  /// fold, which is the same mistake the collection round's village filter
  /// already made and already fixed.
  Widget _villageChooser() {
    if (_villages.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: DropdownButtonFormField<ManaVillage>(
        initialValue: _village,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: ref.t('search_within_a_village'),
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.place_outlined),
        ),
        items: [
          for (final v in _villages)
            DropdownMenuItem(value: v, child: ManaText.raw(v.name)),
        ],
        onChanged: _pickVillage,
      ),
    );
  }

  /// Which village is being looked in, and the way back out of it.
  Widget _villageBar() => Padding(
        padding: const EdgeInsets.fromLTRB(
            ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, ManaSpacing.sm),
        // Wrap, not Row: a Telugu village name beside a Clear button does not
        // share a 360dp line at a 2.0x text scale.
        child: Wrap(
          spacing: ManaSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.place_outlined, size: 18, color: ManaColors.brandDeep),
            ManaText.raw(_village!.name, style: ManaType.strong),
            ManaText.raw(
              ref
                  .t('people_here')
                  .replaceAll('{count}', '${_villagePeople.length}'),
              style: ManaType.note,
            ),
            TextButton(
              onPressed: () => _pickVillage(null),
              child: ManaText.raw(ref.t('clear_selection')),
            ),
          ],
        ),
      );

  Widget _villageTile(ManaVillagePerson p) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: ManaText.raw(p.fullName),
        subtitle: ManaText.raw(
          [p.careOf, p.mlid, if (p.mobile.isNotEmpty) p.mobile]
              .where((x) => x.isNotEmpty)
              .join('  •  '),
          style: ManaType.fine,
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        // Straight into the search this screen already does, by MLID, which
        // is the one thing about a person that is unique. That reuses every
        // role-resolving branch below rather than growing a second one.
        onTap: () {
          _query.text = p.mlid;
          _pickVillage(null);
          _search();
        },
      );

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searched = true;
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
                  .select('person_id, role, membership_id, membership_status')
                  .eq('business_id', widget.businessId)
                  .inFilter('person_id', ids)) as List)
              .cast<Map<String, dynamic>>();
      final rolesByPerson = <String, List<String>>{};
      final pendingByPerson = <String, List<String>>{};
      // membership_id -> person_id, so the customers rows below can be put
      // back against the person they belong to.
      final personByMembership = <String, String>{};
      for (final row in roleRows) {
        final personId = row['person_id'].toString();
        final role = row['role'] as String;
        // THE STATUS WAS NOT EVEN SELECTED, so every row became a live role --
        // a pending invitation and a removed membership both drew the same
        // tappable chevron as somebody who had accepted. Labels read out of
        // membership_status_enum, not guessed.
        final status = row['membership_status'] as String? ?? '';
        if (status == 'Pending Invitation' ||
            status == 'Pending Acceptance' ||
            status == 'Pending Approval') {
          pendingByPerson.putIfAbsent(personId, () => []).add(role);
          continue;
        }
        // Removed, Suspended and Temporarily Disabled are not memberships.
        // Drawing one as a role is the app saying somebody has reach into a
        // book they were taken off.
        if (status != 'Active') continue;
        rolesByPerson.putIfAbsent(personId, () => []).add(role);
        if (role == 'Customer' && row['membership_id'] != null) {
          personByMembership[row['membership_id'] as String] = personId;
        }
      }

      // The customers row for each Customer membership.
      //
      // Queried by membership_id rather than through an embed on purpose:
      // customers -> business_members has more than one foreign key, and an
      // unnamed embed is PGRST201 (HTTP 300), which reaches the screen as
      // "could not load" with nothing to act on. Two plain queries cannot be
      // ambiguous.
      final customerRows = personByMembership.isEmpty
          ? const <Map<String, dynamic>>[]
          : ((await Supabase.instance.client
                  .from('customers')
                  .select('customer_id, membership_id')
                  .inFilter('membership_id', personByMembership.keys.toList()))
              as List)
              .cast<Map<String, dynamic>>();
      final customerByPerson = <String, String>{};
      for (final row in customerRows) {
        final personId = personByMembership[row['membership_id'] as String];
        if (personId != null) {
          customerByPerson[personId] = row['customer_id'] as String;
        }
      }
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = [
          for (final person in result)
            (
              person: person,
              roles: rolesByPerson[person.personId] ?? const [],
              pendingRoles: pendingByPerson[person.personId] ?? const [],
              customerId: customerByPerson[person.personId],
            ),
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

  /// Open the person that was searched for.
  ///
  /// This used to push the role's MANAGEMENT screen -- '/ow-004' for a
  /// Customer -- which is the list of everybody. Somebody who has just typed a
  /// name, waited for the match and tapped it has already said who they mean;
  /// answering with the full list makes them find the same person a second
  /// time.
  ///
  /// A Customer with a resolved customerId opens their own profile. Agent and
  /// Investor still land on their management screens: those profile screens
  /// need an AgentSummary / investor record this search does not load, and
  /// sending someone to the right list beats sending them to a half-built
  /// profile.
  Future<void> _openMatch(
    BuildContext context,
    String role,
    CustomerSummary person,
    String? customerId,
  ) async {
    if (role == 'Customer' && customerId != null && customerId.isNotEmpty) {
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CustomerProfileScreen(
          businessId: widget.businessId,
          // Rebuilt with the resolved customerId, which is what
          // customerProfileProvider keys on -- the searched row carries an
          // empty one and would load nothing.
          customer: CustomerSummary(
            customerId: customerId,
            personId: person.personId,
            fullName: person.fullName,
            fatherHusbandName: person.fatherHusbandName,
            village: person.village,
            phoneNumber: person.phoneNumber,
            mlid: person.mlid,
            activeLoanCount: person.activeLoanCount,
            todaysDue: person.todaysDue,
            outstandingBalance: person.outstandingBalance,
            lineRepaymentIndex: person.lineRepaymentIndex,
            customerStatus: person.customerStatus,
            membershipStatus: person.membershipStatus,
          ),
        ),
      ));
      return;
    }

    // Agent and Investor need their real record before their profile can be
    // opened: AgentProfileScreen keys on agents.agent_id and shows today's
    // collections and loans, InvestorProfileScreen keys on
    // investors.investor_id and shows a balance. Building either by hand from
    // an identity-search row would fill those with zeros -- a confidently
    // wrong number on a money screen, which is worse than the list.
    //
    // So the record is fetched and matched on person_id. If it cannot be
    // found the management screen is still the honest answer.
    if (role == 'Agent' || role == 'Investor') {
      setState(() => _opening = '${person.personId}:$role');
      final opened = await NetworkErrorHandler.run(context, () async {
        if (role == 'Agent') {
          final agents = await ref
              .read(ownerApiServiceProvider)
              .fetchAgents(businessId: widget.businessId);
          return agents
              .where((a) => a.personId == person.personId)
              .cast<Object?>()
              .firstOrNull;
        }
        final investors = await ref
            .read(investorApiServiceProvider)
            .fetchInvestors(businessId: widget.businessId);
        return investors
            .where((i) => i.personId == person.personId)
            .cast<Object?>()
            .firstOrNull;
      });
      if (!mounted) return;
      setState(() => _opening = null);
      if (!context.mounted) return;

      if (opened is AgentSummary) {
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AgentProfileScreen(
              businessId: widget.businessId, agent: opened),
        ));
        return;
      }
      if (opened is InvestorSummary) {
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => InvestorProfileScreen(
              businessId: widget.businessId, investor: opened),
        ));
        return;
      }
      // Fell through: the role badge says they hold it, but no record came
      // back. The list is where the Owner can see why.
    }

    final route = switch (role) {
      'Agent' => '/ow-002',
      'Investor' => '/ow-003',
      'Customer' => '/ow-004',
      _ => null,
    };
    if (route == null) return;
    if (!context.mounted) return;
    Navigator.of(context).pop();
    context.push(route, extra: widget.businessId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(
        title: ref.t('search'),
        // The field sits in the app bar's bottom slot so it stays pinned at
        // the top while the results scroll under it.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.sm),
            child: TextField(
              controller: _query,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              // ACTIONS MATCH AS YOU TYPE, PEOPLE ON SUBMIT, and the split is
              // not a style choice. Matching an action is a list comprehension
              // over twenty-five consts; finding a person is a round trip on a
              // village connection. Running the second one per keystroke would
              // make the field stutter and the search fire five times for one
              // query.
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: ref.t('search_by_phone_mlid_aadhaar_name'),
                filled: true,
                prefixIcon: const Icon(Icons.search),
                // The action lives inside the field rather than beside it.
                // A button in a Row next to an Expanded field is this app's
                // recurring overflow shape, and the translated label for
                // "Search" is what widens.
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        tooltip: ref.t('search'),
                        onPressed: _search,
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      // THE VILLAGE IS OFFERED BEFORE ANYTHING IS TYPED, which is the whole
      // point of it. My first version drew the chooser inside the branch that
      // only renders once three characters have been entered -- a filter you
      // have to discover by typing first reduces nothing, and "select village
      // first" is what the Owner asked for. The layout test caught it.
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_village == null && _villages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(ManaSpacing.lg,
                    ManaSpacing.sm, ManaSpacing.lg, 0),
                child: _villageChooser(),
              ),
            Expanded(child: _searchBody()),
          ],
        ),
      ),
    );
  }

  Widget _searchBody() {
    return _error != null
            ? Padding(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                child: ManaText.raw(_error!,
                    style:
                        ManaType.noteBad),
              )
            : _village != null
                // A VILLAGE IS CHOSEN, so this is its people and the box
                // narrows them. The person search by phone/MLID/Aadhaar is
                // still there on Enter; it is simply not what somebody who
                // has just tapped a village is doing.
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _villageBar(),
                      if (_loadingVillage)
                        const Padding(
                          padding: EdgeInsets.all(ManaSpacing.lg),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_villagePeople.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(ManaSpacing.lg),
                          child: ManaText.raw(ref.t('no_people_in_village'),
                              style: ManaType.secondary),
                        )
                      else
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(ManaSpacing.lg,
                                0, ManaSpacing.lg, ManaSpacing.lg),
                            children: [
                              for (final p in _villageMatches) _villageTile(p),
                              if (_villageMatches.isEmpty)
                                ManaText.raw(ref.t('no_identity_found'),
                                    style: ManaType.secondary),
                            ],
                          ),
                        ),
                    ],
                  )
            : _actions.isNotEmpty && _found.isEmpty
                // WHAT THE APP CAN DO, above what it knows about people.
                //
                // The Owner: "Global search - enable to search options that
                // app offers like add a customer, add an agent, etc.. upon
                // entering 3 show matches and on tap lead to that screen or
                // flow."
                //
                // These sit alone while a person search has not been run,
                // because until Enter is pressed there is nothing else to
                // show and this screen used to answer three typed letters
                // with an instruction to type.
                ? ListView(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    children: [
                      ManaText.raw(ref.t('actions_section'),
                          style: ManaType.strong),
                      const SizedBox(height: ManaSpacing.xs),
                      ..._actions.map(_actionTile),
                      const SizedBox(height: ManaSpacing.md),
                      // The person search is still there and still needs
                      // Enter, so it is said rather than left to be guessed.
                      ManaText.raw(ref.t('press_enter_to_find_people'),
                          style: ManaType.note),
                    ],
                  )
            : _found.isEmpty
                ? Padding(
                    // TOP, not centre. The answer to a search belongs where
                    // the eye already is -- just under the box that was typed
                    // into. Centred, "No identity found." sat half a screen
                    // below the query with nothing in between, which reads as
                    // the page still loading rather than as the answer.
                    padding: const EdgeInsets.fromLTRB(ManaSpacing.xxl,
                        ManaSpacing.lg, ManaSpacing.xxl, ManaSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ManaText.raw(
                          // Before a search has run this is an instruction, not
                          // a result. Saying "no match" to someone who has not
                          // yet typed anything reads as a broken search.
                          _searched && !_searching
                              ? ref.t('no_identity_found')
                              : ref.t('search_by_phone_mlid_aadhaar_name'),
                          textAlign: TextAlign.center,
                          style: ManaType.secondary,
                        ),
                        // "Not here" is the answer to the question, not the end
                        // of the errand. Somebody searching for a person who
                        // turns out not to exist is nearly always about to add
                        // them, and this screen used to stop dead instead.
                        //
                        // The same sheet OW-004 uses, carrying the query across
                        // so the name is not typed twice.
                        // NOT ALWAYS A CUSTOMER. This button used to open the
                        // add-customer sheet whatever screen had opened the
                        // search -- so on Workforce and Investor Management,
                        // searching for somebody who did not exist offered to
                        // make them a Customer. That is the "showing to add
                        // them as customer" the Owner reported, and it was one
                        // tap from filing an agent as a borrower.
                        //
                        // Registering a brand new Agent or Investor is OW-014's
                        // job and always has been: it searches by MLID or name
                        // and registers a new person in that role when there is
                        // no match. Customers keep the sheet, which ends with
                        // the choice OW-014 does not have -- add them, or add
                        // them and go straight to a loan.
                        if (_searched && !_searching) ...[
                          const SizedBox(height: ManaSpacing.lg),
                          FilledButton.tonalIcon(
                            onPressed: _addNewPerson,
                            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                            label: ManaText.raw(ref.t(switch (widget.fixedRole) {
                              ManaMemberKind.agent => 'add_an_agent',
                              ManaMemberKind.investor => 'add_investor',
                              // No role fixed: this is the global search, and
                              // the person being looked for could be any of
                              // the three. It used to say "Add Customer",
                              // which is the app answering a question the
                              // Owner has not been asked yet.
                              _ => 'add_a_user',
                            })),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    itemCount: _found.length,
                    itemBuilder: (context, i) {
                      final match = _found[i];
                      return Card(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              title: ManaText.raw(match.person.fullName),
                              // Village FIRST, after the name it qualifies --
                              // the same order the Add Customer sheet already
                              // uses, and for the same reason: a name search
                              // legitimately returns several people, and the
                              // village is the only line an Owner can tell two
                              // men of the same name apart by. owner_search_person
                              // has returned it all along; this screen was
                              // simply never taught to show it. Omitted when
                              // there is no address on file, so a missing one
                              // never renders as a real place.
                              subtitle: ManaText.raw([
                                if (match.person.village.isNotEmpty)
                                  match.person.village,
                                match.person.mlid,
                                if (match.person.fatherHusbandName.isNotEmpty)
                                  match.person.fatherHusbandName,
                              ].join(' · ')),
                            ),
                            // What was ASKED and not yet answered. Not a
                            // tappable row: there is nothing to open, and a
                            // chevron here is what made a sent request look
                            // like a member.
                            for (final role in match.pendingRoles)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    ManaSpacing.lg,
                                    0,
                                    ManaSpacing.lg,
                                    ManaSpacing.md),
                                child: ManaText.raw(
                                    ref
                                        .t('request_sent_as')
                                        .replaceAll('{role}', ref.t(role.toLowerCase())),
                                    style: TextStyle(
                                        color: ManaColors.statusWarn,
                                        fontSize: 13)),
                              ),
                            if (match.roles.isEmpty && match.pendingRoles.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    ManaSpacing.lg,
                                    0,
                                    ManaSpacing.lg,
                                    ManaSpacing.md),
                                child: Row(
                                  children: [
                                    // Flexible, not bare: the translated
                                    // sentence beside a button is this
                                    // codebase's recurring overflow shape.
                                    Flexible(
                                      child: ManaText.raw(
                                          ref.t('not_a_member_of_business'),
                                          style: TextStyle(
                                              color: ManaColors.textSecondary,
                                              fontSize: 13)),
                                    ),
                                    const SizedBox(width: ManaSpacing.sm),
                                    if (_adding == match.person.personId)
                                      const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                    else
                                      FilledButton.tonal(
                                        onPressed: _adding != null
                                            ? null
                                            : () => _addToBusiness(match.person),
                                        child: ManaText.raw(
                                            ref.t('add_to_this_business')),
                                      ),
                                  ],
                                ),
                              ),
                            // A person can hold more than one role in the
                            // same business (e.g. an Owner who is also an
                            // Agent) — one tappable row per role rather
                            // than guessing.
                            ...match.roles.map((role) {
                                final busy = _opening ==
                                    '${match.person.personId}:$role';
                                return ListTile(
                                  title: ManaText.raw(role),
                                  trailing: busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.chevron_right),
                                  onTap: _opening != null
                                      ? null
                                      : () => _openMatch(context, role,
                                          match.person, match.customerId),
                                );
                              }),
                          ],
                        ),
                      );
                    },
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
            ManaText.raw(ref.t('business_cash'), style: ManaType.sheetTitle),
            const SizedBox(height: ManaSpacing.md),
            _CashHolders(data: data),
            const SizedBox(height: ManaSpacing.xl),
            ManaText.raw(ref.t('todays_business_summary'),
                style: ManaType.sheetTitle),
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
      label: '${ref.t('brought_forward')}, ${manaRupees(data.ownerCash)}. '
          "Opens who is holding the business's cash",
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
              // The Owner's own cash, named as such, with the rest of the
              // business's money accounted for underneath.
              //
              // This row said BF and showed day_ledger.opening_balance -- the
              // whole business's cash, Rs 2,67,320, while the Owner's own pot
              // was Rs 30. Every other screen that says BF means the pot: Add
              // BF is refused against it, Account Review reports it,
              // transfer-to-agent spends it. The figure was not wrong; it was
              // wearing the other one's name, one screen away from the
              // refusal that quotes the real one.
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ManaInfoWord(ref.t('brought_forward'),
                            infoKey: 'bf', style: ManaType.strong),
                        ManaAmount(data.ownerCash),
                      ],
                    ),
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

/// Who is holding the business's cash, by name.
///
/// The row above shows BF -- the Owner's own pot -- and on a good day that is
/// a small number while most of the money is out on the round. "Held by
/// agents, Rs 2,69,190" does not answer the question an Owner opens this to
/// ask, which is WHICH agent. With five of them it is the only useful form.
///
/// Ordered by amount, because the question is usually about where the money
/// is rather than about a particular person.
class _CashHolders extends ConsumerWidget {
  final OwnerDashboardData data;
  const _CashHolders({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(ref.t('owner_cash_in_hand'), data.ownerCash),
        if (data.agentCash.isEmpty)
          _line(ref.t('held_by_agents'), 0)
        else
          for (final a in data.agentCash)
            _line(a.name.isEmpty ? ref.t('agent') : a.name, a.amount),
        const Divider(height: ManaSpacing.xl),
        _line(ref.t('business_cash_total'), data.businessCash, strong: true),
      ],
    );
  }

  /// Name and figure, both flexible. A person's name is not a label of known
  /// width -- "Nagabhushanam Venkata Subba Reddy" is a real one on this book.
  Widget _line(String name, int amount, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ManaText.raw(name,
                  maxLines: 2,
                  style: strong ? ManaType.strong : null),
            ),
            const SizedBox(width: ManaSpacing.sm),
            // ManaAmount already refuses to wrap and ellipsises rather than
            // rewrap, so maxLines/overflow move inside it. The right alignment
            // belongs to the box, since it takes no textAlign.
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: ManaAmount(amount,
                    size: strong
                        ? ManaAmountSize.standard
                        : ManaAmountSize.compact,
                    semanticLabel: name),
              ),
            ),
          ],
        ),
      );
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
                              style: ManaType.small)),
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
                      style: ManaType.strong),
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
            // 'Register Customer' and 'Group Loans' moved into the New Loan
            // header, where they are actually reached for -- mid-loan, with a
            // borrower standing there who is not on the book yet. Same reason
            // the two agent add-paths left this dashboard for Workforce
            // Management's header.
            (Icons.request_quote_outlined, ref.t('new_loan'), '/ow-005', null),
            (Icons.point_of_sale_outlined, ref.t('collections'), '/ow-006', null),
            // 'Search Customers' removed (item 4.1) — the header's Universal
            // Search covers it, and OW-004 has its own search field.
            (Icons.people_outline, ref.t('customer_management'), '/ow-004', null),
            (Icons.inbox_outlined, ref.t('loan_requests'), '/ow-loan-requests', null),
        ],
      ),
      (
        ref.t('agents'),
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
          // Straight to Universal Search, which is the one way anybody is
          // added to a business now. This used to deep-link OW-003 with
          // open=existing to pop that screen's own MLID/name sheet, which
          // has been deleted.
          (
            Icons.person_add_alt_1_outlined,
            ref.t('add_investor'),
            '/ow-search',
            null
          ),
          (
            Icons.inbox_outlined,
            ref.t('investor_requests'),
            '/ow-003',
            'filter=Pending%20Acceptance'
          ),
          (ManaIcons.investor, ref.t('investor_management'), '/ow-003', null),
          // After the investor entries, per the Owner: the whole book's people
          // in one place, sortable by name or by village.
          (Icons.groups_outlined, ref.t('members'), '/ow-012', 'tab=members'),
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
        // SWIPEABLE, as asked -- and a DRAG rather than a PageView.
        //
        // A PageView demands a bounded height, and these groups do not share
        // one: Customers has four actions and Investors six. Worse,
        // ManaActionGrid decides its own column count by device -- 4 up on a
        // phone, 5 or 6 on something larger -- so anything that computed a
        // height here would be a second copy of that rule, wrong on a tablet
        // and wrong again at 2.0x. The first draft of this did exactly that.
        //
        // A horizontal drag costs none of it: the group below stays a plain
        // child that sizes itself, and AnimatedSwitcher sizes to whichever
        // one is showing.
        //
        // The chips stay. A swipe with nothing saying there is somewhere to
        // swipe TO is a gesture nobody finds, and the chips are also what an
        // Owner uses when they already know which group they want.
        GestureDetector(
          // Vertical drags must still reach the ListView behind this, or the
          // dashboard stops scrolling wherever a quick-action panel is under
          // the thumb.
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v == 0) return;
            // Drag left (negative velocity) moves forward, the way a page
            // does. Clamped rather than wrapped: an Owner who swipes past the
            // end of a three-item set should find the end, not the beginning.
            final next = (v < 0 ? index + 1 : index - 1)
                .clamp(0, groups.length - 1);
            if (next != index) setState(() => _selected = next);
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            // Keyed by index, or AnimatedSwitcher sees one _QuickActionGroup
            // and rebuilds it in place with no transition at all.
            child: _QuickActionGroup(
              key: ValueKey(index),
              businessId: businessId,
              actions: groups[index].$2,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActionGroup extends StatelessWidget {
  final String businessId;
  final List<(IconData, String, String, String?)> actions;
  const _QuickActionGroup(
      {super.key, required this.businessId, required this.actions});

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
              style: ManaType.secondary),
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
                      style: ManaType.small),
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
  /// What happened, as a sentence.
  String _attentionTitle(WidgetRef ref, AttentionCard c) => switch (c.type) {
        'Disputed Opening BF' => ref.t('agent_asked_you_to_check_bf'),
        _ => c.type,
      };

  /// What to do about it. Every card on this panel is a thing waiting on the
  /// Owner, so every card says where tapping goes.
  String _attentionAction(WidgetRef ref, AttentionCard c) => switch (c.type) {
        'Disputed Opening BF' => ref.t('tap_to_open_their_record'),
        _ => ref.t('tap_to_open'),
      };

  void _open(BuildContext context, AttentionCard c) {
    final route = switch (c.type) {
      'Pending Customer Approval' => '/ow-004',
      'Pending Loan Approval' => '/ow-loan-requests',
      'Pending Day Closure' => '/ow-011',
      // The agent whose float is disputed, so the Owner lands on the screen
      // with Add BF on it. Falls back to the roster when more than one agent
      // is disputing, where picking one would hide the others.
      'Disputed Opening BF' => c.focusAgentId == null
          ? '/ow-002'
          : '/ow-002?agent=${c.focusAgentId}',
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
              style: ManaType.secondary),
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
                  // The type string is a database value, not a sentence: an
                  // Owner reading "Disputed Opening BF · Updated 22 Aug" was
                  // told what the row is called and when a column last
                  // changed, but not what happened or what to do about it.
                  // The timestamp is worse than useless here — a BF recompute
                  // touches updated_at, so a request from two days ago reads
                  // as if it just arrived.
                  title: ManaText.raw(_attentionTitle(ref, c),
                      style: ManaType.small),
                  subtitle: ManaText.raw(_attentionAction(ref, c),
                      style: ManaType.small),
                  // A count, so bounded by nature and not actually at risk —
                  // converted anyway so the whole codebase has one answer for
                  // "pill in a trailing slot", and so changing this label to a
                  // word later cannot quietly reintroduce the overflow.
                  trailing: ManaTrailingStatus(
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

