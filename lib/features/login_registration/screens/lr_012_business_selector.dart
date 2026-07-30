import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/widgets/language_selector.dart';
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

  Future<void> _respondToRequest(Membership m, bool accept) async {
    try {
      await Supabase.instance.client.schema('app').rpc('respond_to_membership_request', params: {
        'p_membership_id': m.membershipId,
        'p_accept': accept,
      });
      final memberships = await ref.read(authApiServiceProvider).fetchMemberships(ref.read(authFlowProvider).personId!);
      ref.read(authFlowProvider.notifier).setMemberships(memberships);
      if (!mounted) return;
      setState(() {});
      if (accept) {
        // Was the actual dead end — accepting a request refreshed the
        // membership list but never re-checked whether the person should
        // now be auto-routed into their new workspace (e.g. if this was
        // their only business). WidgetsBinding defer, same reasoning as
        // initState's own call.
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyRoutingRule());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? 'Could not accept — please try again.' : 'Could not decline — please try again.')),
      );
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
    final lang = ref.watch(authFlowProvider).language;

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
                _PendingRequestsSection(pending: _pendingInvitations(), onRespond: _respondToRequest),
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
              ManaLanguageSelector(
                current: lang,
                onChanged: (l) => ref.read(authFlowProvider.notifier).setLanguage(l),
              ),
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
              const CircleAvatar(
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
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        if (suspended) ...[
                          const SizedBox(width: ManaSpacing.sm),
                          ManaStatusPill(label: g.businessStatus, status: ManaStatus.bad),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    ManaText.raw(g.roles.join(', '),
                        style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
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

  PreferredSizeWidget _buildHeader(BuildContext context) {
    return AppBar(
      title: ManaText.raw(_fullName != null ? 'Welcome, $_fullName' : 'Welcome'),
      leading: Padding(
        padding: const EdgeInsets.all(6),
        child: CircleAvatar(
          backgroundColor: ManaColors.surfaceSunken,
          backgroundImage: _profilePhotoUrl != null ? NetworkImage(_profilePhotoUrl!) : null,
          child: _profilePhotoUrl == null ? const Icon(Icons.person, size: 18) : null,
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case 'request_join':
                _openRequestJoinFlow(context);
              case 'logout':
                ref.read(authFlowProvider.notifier).reset();
                context.go('/lr-003');
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'request_join', child: ManaText('request to join a business')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'logout', child: ManaText('logout')),
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
              if (pending.isNotEmpty) ...[
                _PendingRequestsSection(pending: pending, onRespond: _respondToRequest),
                const SizedBox(height: ManaSpacing.xl),
              ],
              const Icon(Icons.storefront_outlined, size: 48, color: ManaColors.textSecondary),
              const SizedBox(height: ManaSpacing.md),
              const ManaText('no business linked', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: ManaSpacing.sm),
              const ManaText.raw(
                'You\'re not yet linked to a business. Create a new one, or '
                'contact the Owner if you\'re expecting an existing invitation.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ManaSpacing.xl),
              ElevatedButton(
                // OW-000 First Business Setup — reached with
                // isAdditionalBusiness=false since this is the 0-business
                // path (per OW-000's own ENTRY POINT: "0 Businesses Linked").
                onPressed: () => context.push('/ow-000', extra: false),
                child: const ManaText('create new business'),
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
                    const SnackBar(content: Text('Support: support@manaline.app')),
                  );
                },
                child: const ManaText('contact owner'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows pending business membership requests (business_members.
/// membership_status = 'Pending Invitation') with real Accept/Decline
/// actions. Deliberately separate from the main business list above —
/// that list's "Active only" rule is a locked decision (never shown-
/// then-blocked); this is a different, additive concept: a real request
/// awaiting the recipient's own response, not a business option they
/// can select into yet.
class _PendingRequestsSection extends StatefulWidget {
  final List<Membership> pending;
  final Future<void> Function(Membership, bool accept) onRespond;
  const _PendingRequestsSection({required this.pending, required this.onRespond});

  @override
  State<_PendingRequestsSection> createState() => _PendingRequestsSectionState();
}

class _PendingRequestsSectionState extends State<_PendingRequestsSection> {
  String? _respondingTo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText('pending requests', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: ManaSpacing.sm),
        ...widget.pending.map((m) {
          final busy = _respondingTo == m.membershipId;
          return Card(
            color: ManaColors.statusWarnFaint,
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText.raw('${m.businessName} — as ${m.role}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const ManaText.raw('Waiting for your response.', style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                  const SizedBox(height: ManaSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() => _respondingTo = m.membershipId);
                                  await widget.onRespond(m, false);
                                  if (mounted) setState(() => _respondingTo = null);
                                },
                          child: const ManaText('decline'),
                        ),
                      ),
                      const SizedBox(width: ManaSpacing.sm),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() => _respondingTo = m.membershipId);
                                  await widget.onRespond(m, true);
                                  if (mounted) setState(() => _respondingTo = null);
                                },
                          child: busy
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const ManaText('accept'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
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
        SnackBar(content: Text('Request sent to ${_foundBusiness!['mlbi']} as $_role. Waiting for the Owner to accept.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = 'Could not send request — you may already have one pending for this role/business.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          const ManaText('request to join a business', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: ManaSpacing.md),

          const ManaText('1. select role', style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
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

          const ManaText('2. find the business', style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
          const SizedBox(height: ManaSpacing.xs),
          TextField(
            controller: _queryController,
            enabled: _role != null,
            decoration: InputDecoration(
              labelText: 'Business name or MLBI',
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
                      subtitle: ManaText.raw(b['mlbi'] as String? ?? '', style: const TextStyle(fontSize: 13)),
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
            const ManaText.raw('No matching business found. Check the name/MLBI and try again.',
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
          ],

          // Confirm card — full details, shown only once a suggestion is
          // tapped. This is the actual gap being closed: previously only
          // name + MLBI were shown before applying; now owner name and
          // registered address are shown too, so the person can confirm
          // it's genuinely the business they mean before sending a request.
          if (_foundBusiness != null) ...[
            const SizedBox(height: ManaSpacing.md),
            const ManaText('3. confirm business details', style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
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
            ManaText.raw(_error!, style: const TextStyle(color: ManaColors.statusBad, fontSize: 13)),
          ],

          const SizedBox(height: ManaSpacing.lg),
          ElevatedButton(
            onPressed: (_foundBusiness != null && _role != null && !_applying) ? _apply : null,
            child: _applying
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const ManaText('4. send request'),
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
            child: ManaText.raw(label, style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
          ),
          Expanded(
            child: ManaText.raw(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
