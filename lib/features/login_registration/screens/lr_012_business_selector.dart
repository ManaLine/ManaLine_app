import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';

class _BusinessGroup {
  final String businessId;
  final String businessName;
  final String businessStatus;
  final List<String> roles;
  _BusinessGroup({
    required this.businessId,
    required this.businessName,
    required this.businessStatus,
    required this.roles,
  });
}

/// LR-012 — Phase 4 Business Router. Per spec, the 0/1/>1 collapse rules
/// are applied BEFORE rendering — this screen either never shows (0 or 1
/// distinct Active business) or shows the full card list (>1). Reached
/// from LR-009/LR-008 (first login/daily login) via authFlowProvider's
/// memberships, already in hand from the login response — no separate
/// "list my businesses" call, per spec's DATA SOURCE section.
class BusinessSelectorScreen extends ConsumerStatefulWidget {
  const BusinessSelectorScreen({super.key});

  @override
  ConsumerState<BusinessSelectorScreen> createState() => _BusinessSelectorScreenState();
}

class _BusinessSelectorScreenState extends ConsumerState<BusinessSelectorScreen> {
  String? _profilePhotoUrl;
  String? _fullName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final personId = ref.read(authFlowProvider).personId;
      if (personId != null) {
        try {
          final row = await Supabase.instance.client
              .from('persons')
              .select('profile_photo_url, full_name')
              .eq('person_id', personId)
              .maybeSingle();
          if (mounted) {
            setState(() {
              _profilePhotoUrl = row?['profile_photo_url'] as String?;
              _fullName = row?['full_name'] as String?;
            });
          }
        } catch (_) {
          // Non-fatal — just shows the default icon instead of a photo.
        }
      }
      final auth = ref.read(authFlowProvider);
      // Defensive fallback, not a routine refetch (that's still deliberately
      // not done here, per the locked design below) — only fires if this
      // screen is reached with a real personId but a suspiciously-empty
      // memberships cache, which shouldn't happen via the normal login flow
      // but can if this screen is reached some other way (e.g. direct
      // navigation during testing, bypassing LR-009/LR-007's normal
      // setMemberships call).
      if (auth.personId != null && auth.memberships.isEmpty) {
        final memberships = await ref.read(authApiServiceProvider).fetchMemberships(auth.personId!);
        ref.read(authFlowProvider.notifier).setMemberships(memberships);
      }
      if (mounted) _applyRoutingRule();
    });
  }

  List<_BusinessGroup> _activeBusinessGroups() {
    final memberships = ref.read(authFlowProvider).memberships;
    // Only 'Active' membership rows count toward routing/display (BR-192/203) —
    // Pending/Suspended/Removed are excluded entirely, not shown-then-blocked.
    final active = memberships.where((m) => m.membershipStatus == 'Active');

    final byBusinessId = <String, _BusinessGroup>{};
    for (final m in active) {
      final existing = byBusinessId[m.businessId];
      if (existing == null) {
        byBusinessId[m.businessId] = _BusinessGroup(
          businessId: m.businessId,
          businessName: m.businessName,
          businessStatus: m.businessStatus,
          roles: [m.role],
        );
      } else {
        existing.roles.add(m.role);
      }
    }
    return byBusinessId.values.toList();
  }

  List<Membership> _pendingInvitations() {
    return ref.read(authFlowProvider).memberships.where((m) => m.membershipStatus == 'Pending Invitation').toList();
  }

  /// Re-reads memberships after the person has been to the Notifications
  /// inbox, then re-applies the routing rule.
  ///
  /// This screen used to answer invitations itself, and on accept it
  /// refreshed memberships and re-ran _applyRoutingRule so someone who had
  /// just joined their only business was taken straight into it. The
  /// decision moved to the inbox; that follow-through has to move with it,
  /// or accepting an invitation would leave this list stale and the person
  /// staring at "no business linked" for a business they just joined.
  Future<void> _refreshAfterInbox() async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) return;
    try {
      final memberships =
          await ref.read(authApiServiceProvider).fetchMemberships(personId);
      ref.read(authFlowProvider.notifier).setMemberships(memberships);
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyRoutingRule());
    } catch (_) {
      // Non-fatal: the list simply stays as it was. Pull-to-refresh and the
      // next visit both recover, and a failed refresh must not block the
      // selector.
    }
  }

  void _applyRoutingRule() {
    final groups = _activeBusinessGroups();
    if (groups.length == 1) {
      // "Automatically Open Business" — LR-012 must never appear for a
      // single-business user.
      ref.read(authFlowProvider.notifier).selectBusiness(groups.first.businessId);
      context.go('/lr-013');
    }
    // 0 groups → render S0 below (build() handles this, no navigation).
    // >1 groups → render the card list below (build() handles this too).
  }

  void _selectBusiness(String businessId) {
    ref.read(authFlowProvider.notifier).selectBusiness(businessId);
    context.push('/lr-013');
  }

  @override
  Widget build(BuildContext context) {
    final groups = _activeBusinessGroups();

    if (groups.isEmpty) return _noBusinessLinked(context);
    if (groups.length == 1) {
      // Transient frame before the postFrameCallback above fires — avoid
      // flashing the card list for a single-business user.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: _buildHeader(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            children: [
              if (_pendingInvitations().isNotEmpty) ...[
                _InvitationsPrompt(
                    count: _pendingInvitations().length,
                    onReturn: _refreshAfterInbox),
                const SizedBox(height: ManaSpacing.md),
              ],
              Expanded(
                child: ListView.separated(
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: ManaSpacing.md),
                  itemBuilder: (context, i) => _businessCard(groups[i]),
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _businessCard(_BusinessGroup g) {
    final suspended = g.businessStatus != 'Active';
    return Card(
      child: InkWell(
        onTap: () => _selectBusiness(g.businessId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: ManaColors.inkFaint,
                child: Icon(Icons.storefront, color: ManaColors.textSecondary),
              ),
              const SizedBox(width: ManaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: ManaText.raw(g.businessName,
                              style: ManaType.strong),
                        ),
                        if (suspended) ...[
                          const SizedBox(width: ManaSpacing.sm),
                          ManaStatusPill(label: g.businessStatus, status: ManaStatus.bad),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    ManaText.raw(g.roles.join(', '),
                        style: ManaType.note),
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

  PreferredSizeWidget _buildHeader(BuildContext context) {
    return AppBar(
      // Two lines, not "Welcome, <name>" on one.
      //
      // WHY: a single line put a fixed six-character greeting in front of the
      // part that matters, so the name — which is user data and routinely
      // three words in this region — was the half that got ellipsed. Names
      // here really do reach "Karri Siri Manikanta Reddy". Stacking a small
      // greeting over the name gives the name the full width.
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ManaText.raw(
            ref.t('welcome'),
            style: TextStyle(
              fontSize: 12,
              color: ManaColors.textSecondary,
              height: 1.1,
            ),
          ),
          if (_fullName != null)
            ManaText.raw(
              _fullName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
        ],
      ),
      leading: Padding(
        padding: const EdgeInsets.all(6),
        child: Semantics(
          button: true,
          label: 'Profile',
          child: InkWell(
            customBorder: const CircleBorder(),
            // Settings is where Profile lives. It is reached from here with
            // no workspace chosen, so Settings resolves the Profile row from
            // the last role this device used — see SettingsScreen's own
            // _profileRoute note.
            onTap: () => context.push('/settings'),
            child: CircleAvatar(
              backgroundColor: ManaColors.surfaceSunken,
              backgroundImage:
                  _profilePhotoUrl != null ? NetworkImage(_profilePhotoUrl!) : null,
              child: _profilePhotoUrl == null ? const Icon(Icons.person, size: 18) : null,
            ),
          ),
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case 'settings':
                context.push('/settings');
              case 'request_join':
                _openRequestJoinFlow(context);
              case 'logout':
                ref.read(authFlowProvider.notifier).reset();
                context.go('/lr-009');
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'settings', child: ManaText.raw(ref.t('settings'))),
            PopupMenuItem(value: 'request_join', child: ManaText.raw(ref.t('request_to_join_a_business'))),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'logout', child: ManaText.raw(ref.t('logout'))),
          ],
        ),
      ],
    );
  }

  void _openRequestJoinFlow(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RequestJoinBusinessSheet(),
    );
  }

  Widget _noBusinessLinked(BuildContext context) {
    final pending = _pendingInvitations();
    return Scaffold(
      appBar: _buildHeader(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The stranding case: no active business at all. If the only
              // membership is a pending invitation, this prompt is the only
              // way forward — there is no dashboard here, so no notification
              // bell. Removing the invitation UI without leaving a route to
              // the inbox would lock these people out of the app entirely.
              if (pending.isNotEmpty) ...[
                _InvitationsPrompt(count: pending.length, onReturn: _refreshAfterInbox),
                const SizedBox(height: ManaSpacing.xl),
              ],
              Icon(Icons.storefront_outlined, size: 48, color: ManaColors.textSecondary),
              const SizedBox(height: ManaSpacing.md),
              ManaText.raw(ref.t('no_business_linked'), style: ManaType.strong),
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(
                ref.t('no_business_linked_note'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ManaSpacing.xl),
              ElevatedButton(
                // OW-000 First Business Setup — reached with
                // isAdditionalBusiness=false since this is the 0-business
                // path (per OW-000's own ENTRY POINT: "0 Businesses Linked").
                onPressed: () => context.push('/ow-000', extra: false),
                child: ManaText.raw(ref.t('create_new_business')),
              ),
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton(
                // RESOLVED per spec: deep-links to the Pending membership's
                // business contact info if one exists; static fallback
                // otherwise. No Pending-membership signal available in
                // this stub (only Active rows are modeled), so this
                // always shows the static fallback for now.
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: ManaText.raw(ref.t('support_email_note'))),
                  );
                },
                child: ManaText.raw(ref.t('contact_owner')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Points at the shared Notifications inbox rather than answering the
/// invitation here.
///
/// This screen used to carry its own Accept/Decline UI — one of several
/// copies scattered across the app. The decision now happens in one place,
/// but it still has to be REACHABLE from here: LR-012 is pre-workspace, so
/// there is no dashboard and no notification bell, and someone whose only
/// membership is a pending invitation would otherwise have no way into the
/// app at all.
class _InvitationsPrompt extends ConsumerWidget {
  final int count;

  /// Runs when the person comes back from the inbox — see
  /// _BusinessSelectorScreenState._refreshAfterInbox.
  final Future<void> Function() onReturn;

  const _InvitationsPrompt({required this.count, required this.onReturn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: ManaColors.brandFaint,
      child: ListTile(
        leading: Icon(Icons.mark_email_unread_outlined, color: ManaColors.brand),
        title: ManaText.raw(
          ref.t('invitations_to_you'),
          style: ManaType.emphasis,
        ),
        subtitle: ManaText.raw(
          ref.t('pending_invitations_count_note').replaceAll('{count}', '$count'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/notifications').then((_) => onReturn()),
      ),
    );
  }
}
/// "Request to Join a Business" — self-service reverse-direction flow.
/// Flow order: role first, then search (by business name, partial match —
/// or an exact MLBI, same field), pick from live suggestions, confirm the
/// full business details, then apply.
///
/// CHANGED (this batch): step 2 used to be an exact-MLBI-only text field
/// (0046's search_business_by_mlbi) — unusable for someone who only knows
/// the business by name, and typing a name into it just produced "No
/// business found." Replaced with search_businesses_by_name (0051),
/// partial/ILIKE match on name OR MLBI-prefix, live suggestions as you
/// type (debounced), and a full confirm card (name, MLBI, owner, address)
/// before sending the request — not just a name+MLBI chip like before.
class _RequestJoinBusinessSheet extends ConsumerStatefulWidget {
  const _RequestJoinBusinessSheet();

  @override
  ConsumerState<_RequestJoinBusinessSheet> createState() => _RequestJoinBusinessSheetState();
}

class _RequestJoinBusinessSheetState extends ConsumerState<_RequestJoinBusinessSheet> {
  String? _role; // 'Agent' | 'Investor' | 'Customer'
  final _queryController = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  Map<String, dynamic>? _foundBusiness; // set once a suggestion is tapped — confirm-card state
  bool _applying = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _foundBusiness = null; // typing again after picking one clears the confirm card
      _error = null;
    });
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final rows = await Supabase.instance.client
          .schema('app')
          .rpc('search_businesses_by_name', params: {'p_query': query});
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _suggestions = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _suggestions = [];
        _error = 'Search failed — please try again.';
      });
    }
  }

  void _pickSuggestion(Map<String, dynamic> business) {
    setState(() {
      _foundBusiness = business;
      _suggestions = [];
      _queryController.text = business['business_name'] as String? ?? '';
      _error = null;
    });
  }

  Future<void> _apply() async {
    if (_foundBusiness == null || _role == null) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.schema('app').rpc('request_join_business', params: {
        'p_business_id': _foundBusiness!['business_id'],
        'p_role': _role,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: ManaText.raw(ref
                .t('request_sent_to_note')
                .replaceAll('{name}', "${_foundBusiness!['mlbi']} as $_role"))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        // The real message, not a guess. This said "you may already have
        // one pending" for EVERY failure, which was actively misleading
        // while the RPC itself was throwing 42883 on every call and no
        // request had ever been created.
        _error = e is PostgrestException
            ? e.message
            : 'Could not send request. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // SCROLLS. Padding alone accounted for the keyboard but the content
    // could not move, so once the role chips + search field + confirm card +
    // button were taller than what the keyboard left behind, it overflowed —
    // 24px on a real handset. Same class of bug as LR-002's Spacers.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: ManaSpacing.lg,
        right: ManaSpacing.lg,
        top: ManaSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + ManaSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(ref.t('request_to_join_a_business'), style: ManaType.cardTitle),
          const SizedBox(height: ManaSpacing.md),

          ManaText.raw(ref.t('step_1_select_role'), style: ManaType.note),
          const SizedBox(height: ManaSpacing.xs),
          Wrap(
            spacing: ManaSpacing.sm,
            children: ['Agent', 'Investor', 'Customer'].map((r) {
              final selected = _role == r;
              return ChoiceChip(
                label: Text(r),
                selected: selected,
                onSelected: (_) => setState(() => _role = r),
              );
            }).toList(),
          ),
          const SizedBox(height: ManaSpacing.md),

          ManaText.raw(ref.t('step_2_find_the_business'), style: ManaType.note),
          const SizedBox(height: ManaSpacing.xs),
          TextField(
            controller: _queryController,
            enabled: _role != null,
            decoration: InputDecoration(
              labelText: ref.t('business_name_or_mlbi_field'),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
            onChanged: _onQueryChanged,
          ),

          // Live suggestions — shown while typing, before a business is picked.
          if (_suggestions.isNotEmpty && _foundBusiness == null) ...[
            const SizedBox(height: ManaSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final b = _suggestions[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundImage: b['logo_url'] != null ? NetworkImage(b['logo_url'] as String) : null,
                        child: b['logo_url'] == null ? const Icon(Icons.storefront_outlined, size: 16) : null,
                      ),
                      title: ManaText.raw(b['business_name'] as String? ?? '', style: const TextStyle(fontSize: 14)),
                      subtitle: ManaText.raw(b['mlbi'] as String? ?? '', style: ManaType.small),
                      onTap: () => _pickSuggestion(b),
                    );
                  },
                ),
              ),
            ),
          ],

          if (_queryController.text.trim().length >= 2 &&
              !_searching &&
              _suggestions.isEmpty &&
              _foundBusiness == null) ...[
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(ref.t('no_matching_business_note'),
                style: ManaType.note),
          ],

          // Confirm card — full details, shown only once a suggestion is
          // tapped. This is the actual gap being closed: previously only
          // name + MLBI were shown before applying; now owner name and
          // registered address are shown too, so the person can confirm
          // it's genuinely the business they mean before sending a request.
          if (_foundBusiness != null) ...[
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('step_3_confirm_business'), style: ManaType.note),
            const SizedBox(height: ManaSpacing.xs),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(ManaSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: _foundBusiness!['logo_url'] != null
                              ? NetworkImage(_foundBusiness!['logo_url'] as String)
                              : null,
                          child: _foundBusiness!['logo_url'] == null ? const Icon(Icons.storefront_outlined) : null,
                        ),
                        const SizedBox(width: ManaSpacing.sm),
                        Expanded(
                          child: ManaText.raw(_foundBusiness!['business_name'] as String? ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ],
                    ),
                    const SizedBox(height: ManaSpacing.sm),
                    _confirmRow('MLBI', _foundBusiness!['mlbi'] as String? ?? '—'),
                    _confirmRow('Owner', _foundBusiness!['owner_name'] as String? ?? '—'),
                    _confirmRow('Registered Address', _foundBusiness!['business_address'] as String? ?? '—'),
                  ],
                ),
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(_error!, style: ManaType.noteBad),
          ],

          const SizedBox(height: ManaSpacing.lg),
          ElevatedButton(
            onPressed: (_foundBusiness != null && _role != null && !_applying) ? _apply : null,
            child: _applying
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : ManaText.raw(ref.t('step_4_send_request')),
          ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: ManaText.raw(label, style: ManaType.note),
          ),
          Expanded(
            child: ManaText.raw(value, style: ManaType.small),
          ),
        ],
      ),
    );
  }
}
