import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_member_roster.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_stat_strip.dart';
import '../../../design/components/mana_amount.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/person_search_service.dart';
import '../../../shared/text_utils.dart';
import '../../../shared/translation_service.dart';
import '../state/investor_state.dart';
import '../../../design/components/mana_info_hint.dart';
import '../../../design/components/mana_call_button.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// OW-003 — Investor Management. Register New Investor is
/// Investor-initiated (LOCKED CORRECTION in spec) — this screen's C4 is
/// therefore an Approve/Reject queue over incoming requests, not a create
/// form; C5 Add Existing mirrors OW-002's MLID search pattern.
class InvestorManagementScreen extends ConsumerStatefulWidget {
  final String businessId;
  // Set by OW-001's "Add Existing Investor" Quick Action tile ('existing').
  final String? initialAction;
  // Set by the "Investor Requests" Quick Action tile to pre-filter the
  // list to a given membership status (e.g. 'Pending Acceptance').
  final String? initialFilter;
  const InvestorManagementScreen({
    super.key,
    required this.businessId,
    this.initialAction,
    this.initialFilter,
  });

  @override
  ConsumerState<InvestorManagementScreen> createState() => _InvestorManagementScreenState();
}

class _InvestorManagementScreenState extends ConsumerState<InvestorManagementScreen> {
  // Search field belongs to ManaMemberRoster now.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Setting the filter here rather than synchronously in initState —
      // a provider write during any widget's build phase (including
      // initState) throws Riverpod's "tried to modify a provider while the
      // widget tree was building" (hit this for real in the sibling
      // OW-012 tab case — see that file's fix note).
      if (widget.initialFilter != null) {
        ref.read(investorWorkforceProvider.notifier).setStatusFilter(widget.initialFilter);
      }
      ref.read(investorWorkforceProvider.notifier).load(widget.businessId);
      if (widget.initialAction == 'existing') {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _AddExistingInvestorSheet(businessId: widget.businessId),
        ).then((_) => ref.read(investorWorkforceProvider.notifier).load(widget.businessId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(investorWorkforceProvider);

    return Scaffold(
      appBar: AppBar(
        // The two add-paths moved into the roster's single Add FAB.
        title: ManaText.raw(ref.t('investor_management')),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(investorWorkforceProvider.notifier).load(widget.businessId),
          child: state.loading && state.investors.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ManaMemberRoster(
                  heading: ref.t('investors'),
                  header: _DashboardStrip(state: state),
                  members: [
                    // Pending Acceptance rows are excluded because they are
                    // not real members yet: no investor_id, so a row tap into
                    // InvestorProfileScreen would have nothing to load. They
                    // are actioned from Notifications.
                    for (final i in state.filtered
                        .where((i) => i.membershipStatus != 'Pending Acceptance'))
                      MemberEntry(
                        id: i.investorId,
                        name: i.fullName,
                        subtitle: i.mlid,
                        status: i.membershipStatus,
                      ),
                  ],
                  filterLabels: [
                    ref.t('all'),
                    ref.t('active'),
                    ref.t('pending_invitation_status'),
                    ref.t('pending_acceptance_status'),
                    ref.t('temporarily_disabled'),
                    ref.t('suspended'),
                  ],
                  statusValues: const [
                    'Active',
                    'Pending Invitation',
                    'Pending Acceptance',
                    'Temporarily Disabled',
                    'Suspended',
                  ],
                  statusValue: state.statusFilter,
                  onStatusChanged: (v) =>
                      ref.read(investorWorkforceProvider.notifier).setStatusFilter(v),
                  onSearchChanged: (v) =>
                      ref.read(investorWorkforceProvider.notifier).setSearchQuery(v),
                  searchHint: ref.t('search_by_name_or_mlid'),
                  // A failed load must not read as "no investors" — the error
                  // was captured but never shown before, making an RLS/query
                  // failure indistinguishable from a business that has none.
                  emptyLabel: state.error != null
                      ? ref
                          .t('could_not_load_investors')
                          .replaceAll('{error}', '${state.error}')
                      : ref.t('no_investors_match_view'),
                  addLabel: ref.t('add_investor'),
                  addActions: [
                    MemberAction(
                      label: ref.t('add_existing_investor'),
                      icon: Icons.person_add_alt_1_outlined,
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) =>
                            _AddExistingInvestorSheet(businessId: widget.businessId),
                      ).then((_) => ref
                          .read(investorWorkforceProvider.notifier)
                          .load(widget.businessId)),
                    ),
                    // An investor whose money predates this business joining
                    // MANA LINE.
                    MemberAction(
                      label: ref.t('pre_existing_investor'),
                      icon: Icons.history_edu_outlined,
                      onTap: () => context
                          .push('/ow-014?type=investor', extra: widget.businessId)
                          .then((_) => ref
                              .read(investorWorkforceProvider.notifier)
                              .load(widget.businessId)),
                    ),
                  ],
                  rowBuilder: (entry, _) {
                    final i =
                        state.filtered.firstWhere((x) => x.investorId == entry.id);
                    return _InvestorRow(
                      investor: i,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => InvestorProfileScreen(
                              businessId: widget.businessId, investor: i),
                        ),
                      ),
                    );
                  },
                  onOpen: (_) {},
                ),
        ),
      ),
    );
  }
}

class _DashboardStrip extends ConsumerWidget {
  final InvestorWorkforceState state;
  const _DashboardStrip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = <(String, String, ManaStatus)>[
      (ref.t('total'), '${state.total}', ManaStatus.neutral),
      (ref.t('active'), '${state.active}', ManaStatus.good),
      (ref.t('pending_invitation_status'), '${state.pendingInvitations}', ManaStatus.warn),
      (ref.t('pending_acceptance_status'), '${state.pendingAcceptance}', ManaStatus.warn),
      (ref.t('suspended'), '${state.suspended}', ManaStatus.bad),
      (ref.t('total_investment_balance'), _currency.format(state.totalInvestment), ManaStatus.neutral),
      (ref.t('interest_payable'), _currency.format(state.interestPayable), ManaStatus.neutral),
    ];
    return ManaStatStrip(
      valueFontSize: 16,
      stats: [
        for (final (label, value, status) in stats)
          ManaStat(value: value, label: label, status: status),
      ],
    );
  }
}

class _InvestorRow extends StatelessWidget {
  final InvestorSummary investor;
  final VoidCallback onTap;
  const _InvestorRow({required this.investor, required this.onTap});

  ManaStatus get _statusKind => switch (investor.membershipStatus) {
        'Active' => ManaStatus.good,
        'Pending Invitation' || 'Pending Acceptance' => ManaStatus.warn,
        'Suspended' => ManaStatus.bad,
        _ => ManaStatus.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        leading: const ManaVerificationRing(isVerified: true, size: 40),
        title: ManaText.raw(investor.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: ManaText.raw(
          '${investor.mlid} · ${_currency.format(investor.investmentBalance)} @ ${roiLabel(investor.roi)}',
          style: TextStyle(fontSize: 16, color: ManaColors.textSecondary),
        ),
        trailing: ManaTrailingStatus(
            label: investor.membershipStatus, status: _statusKind),
        onTap: onTap,
      ),
    );
  }
}

class _AddExistingInvestorSheet extends ConsumerStatefulWidget {
  final String businessId;
  const _AddExistingInvestorSheet({required this.businessId});

  @override
  ConsumerState<_AddExistingInvestorSheet> createState() => _AddExistingInvestorSheetState();
}

class _AddExistingInvestorSheetState extends ConsumerState<_AddExistingInvestorSheet> {
  // One free-text box plus two optional narrowers. It used to be MLID only,
  // which meant the Owner had to already know a 13-character code for someone
  // they were trying to look up by name.
  final _query = TextEditingController();
  final _pin = TextEditingController();
  final _village = TextEditingController();
  bool _filtersOpen = false;

  List<PersonSearchResult> _results = const [];
  bool _searched = false;
  bool _searching = false;
  String? _addingPersonId;

  @override
  void dispose() {
    _query.dispose();
    _pin.dispose();
    _village.dispose();
    super.dispose();
  }

  bool get _canSearch =>
      _query.text.trim().isNotEmpty ||
      _pin.text.trim().isNotEmpty ||
      _village.text.trim().isNotEmpty;

  Future<void> _search() async {
    if (!_canSearch) return;
    setState(() => _searching = true);
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(personSearchServiceProvider).search(
            query: _query.text,
            pinCode: _pin.text,
            village: _village.text,
          );
    });
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = result ?? const [];
      // Only true once a search actually came back, so "nobody found" is
      // never shown before one has run.
      _searched = result != null;
    });
  }

  Future<void> _add(PersonSearchResult person) async {
    setState(() => _addingPersonId = person.personId);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(investorWorkforceProvider.notifier).addExisting(widget.businessId, person.personId);
    });
    if (!mounted) return;
    setState(() => _addingPersonId = null);
    if (ok == true && mounted) Navigator.of(context).pop();
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
            ManaText.raw(ref.t('add_existing_investor'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: ref.t('search_by_name_or_mlid'),
                      suffixIcon: const ManaInfoHint('Name, MLID, phone, Aadhaar or PIN'),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ElevatedButton(
                  onPressed: (_canSearch && !_searching) ? _search : null,
                  child: _searching
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(ref.t('search')),
                ),
              ],
            ),
            // Narrowers, folded away until wanted. Two people of the same name
            // in one village is the case these exist for.
            TextButton.icon(
              onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
              icon: Icon(_filtersOpen ? Icons.expand_less : Icons.expand_more, size: 18),
              label: const ManaText.raw('Narrow By Village Or PIN'),
            ),
            if (_filtersOpen)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _village,
                      decoration: const InputDecoration(labelText: 'Village'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _pin,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'PIN Code', counterText: ''),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: ManaSpacing.md),
            if (_searched && _results.isEmpty)
              ManaText.raw(
                'Nobody matches that. Try fewer details, or add them as a new investor.',
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
              ),
            if (_results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final person = _results[i];
                    final place = person.placeLabel;
                    return Card(
                      child: ListTile(
                        leading: const ManaVerificationRing(isVerified: true, size: 40),
                        title: ManaText.raw(person.fullName),
                        subtitle: ManaText.raw(
                          place.isEmpty ? person.mlid : '${person.mlid} · $place',
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: ElevatedButton(
                          onPressed: _addingPersonId == null ? () => _add(person) : null,
                          child: _addingPersonId == person.personId
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : ManaText.raw(ref.t('add')),
                        ),
                      ),
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

// --- C6 Investor Profile ---------------------------------------------

class InvestorProfileScreen extends ConsumerWidget {
  final String businessId;
  final InvestorSummary investor;
  const InvestorProfileScreen({super.key, required this.businessId, required this.investor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(investorProfileProvider(investor.investorId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(investor.fullName),
          bottom: TabBar(tabs: [Tab(text: ref.t('overview')), Tab(text: ref.t('investments'))]),
          actions: [
            PopupMenuButton<String>(
              onSelected: (status) => _changeStatus(context, ref, status),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'Active', child: ManaText.raw(ref.t('reactivate'))),
                PopupMenuItem(value: 'Temporarily Disabled', child: ManaText.raw(ref.t('disable'))),
                PopupMenuItem(value: 'Suspended', child: ManaText.raw(ref.t('suspend'))),
                PopupMenuItem(value: 'Removed', child: ManaText.raw(ref.t('remove'))),
              ],
            ),
          ],
        ),
        body: asyncProfile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
              child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: ManaText.raw('Could not load profile.\n$e', textAlign: TextAlign.center),
          )),
          data: (profile) => TabBarView(
            children: [
              _OverviewTab(investor: investor),
              _InvestmentsTab(investorId: investor.investorId, profile: profile),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatus(BuildContext context, WidgetRef ref, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('confirm_status_change_title').replaceAll('{status}', status)),
        content: ManaText.raw(ref
            .t('change_status_note')
            .replaceAll('{name}', investor.fullName)
            .replaceAll('{status}', status)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: ManaText.raw(ref.t('confirm'))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(investorWorkforceProvider.notifier).updateStatus(businessId, investor.investorId, status);
    });
  }
}

class _OverviewTab extends ConsumerWidget {
  final InvestorSummary investor;
  const _OverviewTab({required this.investor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const Center(child: ManaVerificationRing(isVerified: true, size: 72)),
        const SizedBox(height: ManaSpacing.md),
        Center(
            child:
                ManaText.raw(investor.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
        Center(child: ManaText.raw(investor.mlid, style: TextStyle(color: ManaColors.textSecondary))),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(child: _row(ref.t('phone_number'), investor.phoneNumber)),
            // Opens the dialer with the number in it; the Owner presses call.
            ManaCallButton(investor.phoneNumber),
          ],
        ),
        _row(ref.t('investment_balance'), _currency.format(investor.investmentBalance)),
        _row(ref.t('roi'), roiLabel(investor.roi)),
        _row(ref.t('roi_yearly_equivalent'), roiAnnualEquivalent(investor.roi)),
        _row(ref.t('interest_due'), _currency.format(investor.interestDue)),
        _row(ref.t('membership_status'), investor.membershipStatus),
        _row(ref.t('last_transaction'),
            investor.lastTransaction == null ? '—' : DateFormat('d MMM yyyy').format(investor.lastTransaction!)),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: ManaText.raw(label, style: TextStyle(color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );
}

class _InvestmentsTab extends ConsumerWidget {
  final String investorId;
  final InvestorProfile profile;
  const _InvestmentsTab({required this.investorId, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A Removed/Suspended/Pending investor should never be able to have
    // a NEW investment recorded against them — that produced exactly the
    // wrong-info case reported: recording an investment for a Removed
    // investor makes them show an active-looking balance while still
    // carrying Removed status everywhere else (Investor Management's
    // list, the dashboard's active-investor count, etc.).
    final isActive = profile.summary.membershipStatus == 'Active';
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ElevatedButton.icon(
          onPressed: isActive ? () => _showInvestDialog(context, ref) : null,
          icon: const Icon(Icons.add),
          label: ManaText.raw(ref.t('record_investment')),
        ),
        if (!isActive)
          Padding(
            padding: const EdgeInsets.only(top: ManaSpacing.xs),
            child: ManaText.raw(
              ref.t('only_active_investors_note').replaceAll('{status}', profile.summary.membershipStatus),
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ),
        const SizedBox(height: ManaSpacing.lg),
        if (profile.investments.isEmpty)
          ManaText.raw(ref.t('no_investments_recorded_yet'), style: TextStyle(color: ManaColors.textSecondary))
        else
          ...profile.investments.map((inv) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ManaText.raw(_currency.format(inv.principalAmount),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          ManaStatusPill(
                            label: inv.status,
                            status: inv.status == 'Active' ? ManaStatus.good : ManaStatus.neutral,
                          ),
                          // Correcting a mis-typed investment. Edit keeps
                          // the old values in audit_log (BR-169's pattern
                          // for loans); Delete refuses once any interest
                          // payment or withdrawal exists, because that is
                          // money movement and BR-002 makes it permanent.
                          PopupMenuButton<String>(
                            tooltip: ref.t('investment_options'),
                            onSelected: (v) => v == 'edit'
                                ? _showInvestDialog(context, ref, existing: inv)
                                : _confirmDeleteInvestment(context, ref, inv),
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'edit', child: ManaText.raw(ref.t('edit_investment'))),
                              PopupMenuItem(
                                value: 'delete',
                                child: ManaText.raw(ref.t('delete_investment'),
                                    style: TextStyle(color: ManaColors.statusBad)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      ManaText.raw(
                        '${roiLabel(inv.roiRate)} · ${inv.interestMethod} · since ${DateFormat('d MMM yyyy').format(inv.effectiveDate)}',
                        style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      Row(
                        children: [
                          // "Accrued" resets at each anniversary on a
                          // compound investment, because the prior year
                          // became principal (BR-052). Saying so in the
                          // label stops the figure reading as too small.
                          Expanded(
                            child: _small(
                              ref.t(inv.isCompound ? 'accrued_this_year' : 'accrued'),
                              _currency.format(inv.interestAccrued),
                            ),
                          ),
                          Expanded(child: _small(ref.t('paid'), _currency.format(inv.interestPaid))),
                        ],
                      ),
                      // Where the compounded years went. Without this the
                      // principal silently grows and the earlier interest
                      // looks like it vanished.
                      if (inv.hasCompounded) ...[
                        const SizedBox(height: ManaSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                                child: _small(ref.t('invested'), _currency.format(inv.originalPrincipal))),
                            Expanded(
                                child: _small(ref.t('added_to_principal'),
                                    _currency.format(inv.principalAmount - inv.originalPrincipal))),
                          ],
                        ),
                      ],
                      const SizedBox(height: ManaSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: ManaSpacing.sm, vertical: ManaSpacing.xs),
                        decoration: BoxDecoration(
                          color: ManaColors.brandFaint,
                          borderRadius: BorderRadius.circular(ManaRadius.sm),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: ManaText.raw(ref.t('total_interest_earned'),
                                  style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                            ),
                            ManaAmount(inv.totalInterestEarned, size: ManaAmountSize.compact),
                          ],
                        ),
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              // S7/S8 — enabled only when balance >= ₹1.00
                              onPressed: inv.principalAmount >= 1
                                  ? () => _showWithdrawDialog(context, ref, inv)
                                  : null,
                              child: ManaText.raw(ref.t('withdraw')),
                            ),
                          ),
                          // BUG FIXED this pass: declareProfitShare/
                          // payProfitShare were fully implemented in
                          // investor_state.dart but never surfaced here —
                          // only shown when this investment actually has
                          // a profit-share agreement (percent > 0).
                          if ((inv.profitSharePercent ?? 0) > 0) ...[
                            const SizedBox(width: ManaSpacing.sm),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => _ProfitShareSheet(investment: inv),
                                ),
                                child: ManaText.raw(ref.t('profit_share')),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  Widget _small(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(label, style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
          ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );

  Future<void> _confirmDeleteInvestment(
      BuildContext context, WidgetRef ref, InvestmentRecord inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('delete_investment_confirm_title')),
        content: ManaText.raw(
          ref
              .t('delete_investment_confirm_note')
              .replaceAll('{amount}', _currency.format(inv.principalAmount))
              .replaceAll('{roi}', roiLabel(inv.roiRate))
              .replaceAll('{date}', DateFormat('d MMM yyyy').format(inv.effectiveDate)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.of(context).pop(true),
            child: ManaText.raw(ref.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(investorProfileProvider(investorId).notifier)
          .deleteInvestment(investmentId: inv.investmentId);
    });
  }

  /// Records a new investment, or corrects an existing one when `existing`
  /// is supplied — same fields either way, so they share one dialog.
  Future<void> _showInvestDialog(BuildContext context, WidgetRef ref,
      {InvestmentRecord? existing}) async {
    final amount = TextEditingController(
        text: existing == null ? '' : existing.principalAmount.toStringAsFixed(0));
    final roi =
        TextEditingController(text: existing == null ? '' : existing.roiRate.toString());
    String method = existing?.interestMethod ?? 'Simple';
    // Defaults to today, but backdateable — a business onboarding onto
    // this app after already running for years needs to record
    // investments that started well before "today" (e.g. this investor's
    // original entry date), not just brand-new ones.
    // IST, not the handset clock — this is written as the investment's
    // effective_date. See lib/shared/mana_time.dart.
    DateTime effectiveDate = existing?.effectiveDate ?? manaNowIst();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: ManaText.raw(ref.t(existing == null ? 'record_investment' : 'edit_investment')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '${ref.t('amount')} *'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: roi,
                // decimal:true — the plain number keyboard on Android has
                // no decimal point, and this field is routinely a fraction
                // (₹1.50 per 100).
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${ref.t('roi_per_100_label')} *',
                  suffixIcon: ManaInfoHint(ref.t('roi_per_100_helper')),
                ),
                onChanged: (_) => setState(() {}),
              ),
              // The yearly number is the one most people sanity-check
              // against, so show it live rather than making the Owner do
              // x12 in their head while deciding whether they typed it
              // right.
              if (double.tryParse(roi.text.trim()) != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ManaText.raw(
                      '= ${roiAnnualEquivalent(double.parse(roi.text.trim()))}',
                      style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                    ),
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: InputDecoration(labelText: ref.t('interest_method')),
                items: [
                  DropdownMenuItem(value: 'Simple', child: ManaText.raw(ref.t('simple'))),
                  DropdownMenuItem(value: 'Yearly Compound', child: ManaText.raw(ref.t('yearly_compound'))),
                ],
                onChanged: (v) => setState(() => method = v ?? 'Simple'),
              ),
              const SizedBox(height: ManaSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: ManaText.raw(ref.t('effective_date')),
                subtitle: ManaText.raw(DateFormat('d MMM yyyy').format(effectiveDate)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: effectiveDate,
                    firstDate: DateTime(2000),
                    // "Today" here is the IST business day, so an owner
                    // recording after 18:30 UTC can still pick it.
                    lastDate: manaNowIst(),
                  );
                  if (picked != null) setState(() => effectiveDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: ManaText.raw(ref.t('cancel'))),
            // Was always enabled, and the parse failure afterwards just
            // `return`ed — a second silent no-op on top of the schema one.
            // Gate the button on the values actually parsing instead.
            ElevatedButton(
              onPressed: (double.tryParse(amount.text.trim()) != null &&
                      double.tryParse(roi.text.trim()) != null)
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: ManaText.raw(ref.t('save')),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    final amt = int.tryParse(amount.text.trim());
    final r = double.tryParse(roi.text.trim());
    if (amt == null || r == null) return;
    if (!context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      final notifier = ref.read(investorProfileProvider(investorId).notifier);
      return existing == null
          ? notifier.recordInvestment(
              amount: amt, // whole rupees (M8)
              roiRate: r,
              interestMethod: method,
              effectiveDate: effectiveDate.toIso8601String(),
            )
          : notifier.editInvestment(
              investmentId: existing.investmentId,
              amount: amt, // whole rupees (M8)
              roiRate: r,
              interestMethod: method,
              effectiveDate: effectiveDate.toIso8601String(),
            );
    });
  }

  Future<void> _showWithdrawDialog(BuildContext context, WidgetRef ref, InvestmentRecord inv) async {
    final amount = TextEditingController();
    String type = 'Interest Only';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: ManaText.raw(ref.t('request_withdrawal')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: ref.t('amount_cannot_exceed_balance')),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: ref.t('withdrawal_type')),
                items: [
                  DropdownMenuItem(value: 'Interest Only', child: ManaText.raw(ref.t('interest_only'))),
                  DropdownMenuItem(value: 'Principal Partial', child: ManaText.raw(ref.t('principal_partial'))),
                  DropdownMenuItem(value: 'Principal Full', child: ManaText.raw(ref.t('principal_full'))),
                  DropdownMenuItem(value: 'Principal + Interest', child: ManaText.raw(ref.t('principal_plus_interest'))),
                ],
                onChanged: (v) => setState(() => type = v ?? 'Interest Only'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: ManaText.raw(ref.t('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: ManaText.raw(ref.t('submit'))),
          ],
        ),
      ),
    );
    if (result != true) return;
    final amt = int.tryParse(amount.text.trim());
    if (amt == null || amt > inv.principalAmount) return; // BR-252: withdrawals cannot exceed available balance
    if (!context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(investorProfileProvider(investorId).notifier)
          .requestWithdrawal(investmentId: inv.investmentId, amount: amt, withdrawalType: type); // whole rupees (M8)
    });
  }
}

class _ProfitShareSheet extends ConsumerStatefulWidget {
  final InvestmentRecord investment;
  const _ProfitShareSheet({required this.investment});

  @override
  ConsumerState<_ProfitShareSheet> createState() => _ProfitShareSheetState();
}

class _ProfitShareSheetState extends ConsumerState<_ProfitShareSheet> {
  late Future<List<ProfitShareDeclaration>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ProfitShareDeclaration>> _load() {
    return ref.read(investorApiServiceProvider).fetchProfitShareDeclarations(investmentId: widget.investment.investmentId);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _declare() async {
    final amountController = TextEditingController();
    final remarksController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: ManaText.raw(ref.t('declare_profit_share')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ManaText.raw(
                ref
                    .t('percent_of_total_profit_note')
                    .replaceAll('{percent}', '${widget.investment.profitSharePercent}'),
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: '${ref.t('total_profit_amount')} *'),
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(controller: remarksController, decoration: InputDecoration(labelText: ref.t('remarks'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: ManaText.raw(ref.t('cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: ManaText.raw(ref.t('declare'))),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final amt = int.tryParse(amountController.text.trim());
    if (amt == null) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(investorApiServiceProvider).declareProfitShare(
            investmentId: widget.investment.investmentId,
            totalProfitAmount: amt, // whole rupees (M8)
            remarks: remarksController.text.trim().isEmpty ? null : remarksController.text.trim(),
          );
      return true;
    });
    if (ok == true) _reload();
  }

  Future<void> _pay(ProfitShareDeclaration decl) async {
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(investorApiServiceProvider).payProfitShare(declarationId: decl.declarationId);
      return true;
    });
    if (ok == true) _reload();
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
            Row(
              children: [
                Expanded(child: ManaText.raw(ref.t('profit_share'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                FilledButton.tonalIcon(onPressed: _declare, icon: const Icon(Icons.add, size: 18), label: ManaText.raw(ref.t('declare'))),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            Expanded(
              child: FutureBuilder<List<ProfitShareDeclaration>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final declarations = snapshot.data ?? const [];
                  if (declarations.isEmpty) {
                    return Center(
                      child: ManaText.raw(ref.t('no_profit_share_declarations_yet'), style: TextStyle(color: ManaColors.textSecondary)),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: declarations.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final d = declarations[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: ManaText.raw(_currency.format(d.declaredAmount)),
                        subtitle: ManaText.raw(
                            '${DateFormat('d MMM yyyy').format(d.businessDate)} · of ${_currency.format(d.totalProfitAmount)} total'),
                        trailing: d.status == 'Declared'
                            ? FilledButton(onPressed: () => _pay(d), child: ManaText.raw(ref.t('mark_paid')))
                            : ManaStatusPill(label: ref.t('paid'), status: ManaStatus.good),
                      );
                    },
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
