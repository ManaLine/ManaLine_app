import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/group_loan_state.dart';


/// OW-015 — Group Loan Management. Bundles existing individual loans
/// under a Group Name for display/reporting convenience only —
/// NOT a shared financial entity, individual liability only.
///
/// Wired against the real `loan_groups`/`loan_group_members` tables
/// (0007_module6_loan_domain.sql) — see group_loan_state.dart's own
/// header for the full resolution note. No UnimplementedError paths
/// remain; this comment previously described a gap that's since closed.
class GroupLoanManagementScreen extends ConsumerStatefulWidget {
  final String businessId;
  const GroupLoanManagementScreen({super.key, required this.businessId});

  @override
  ConsumerState<GroupLoanManagementScreen> createState() => _GroupLoanManagementScreenState();
}

class _GroupLoanManagementScreenState extends ConsumerState<GroupLoanManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(groupLoanListProvider.notifier).load(widget.businessId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupLoanListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/ow-001', extra: widget.businessId)),
        title: ManaText.raw(ref.t('group_loan_management')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateGroup(context),
        icon: const Icon(Icons.add),
        label: ManaText.raw(ref.t('create_group')),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(groupLoanListProvider.notifier).load(widget.businessId),
          child: state.loading && state.groups.isEmpty
              ? const ManaSkeletonList()
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    // The "GAP: no confirmed loan-groups API exists yet"
                    // banner that used to sit here was stale — it
                    // contradicted this file's own header comment, which
                    // records that the screen was wired against the real
                    // loan_groups / loan_group_members tables and that no
                    // UnimplementedError paths remain. It was alarming the
                    // Owner about a gap that had already been closed.
                    if (state.groups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: ManaSpacing.xxl, horizontal: ManaSpacing.md),
                        child: Column(
                          children: [
                            Icon(Icons.groups_2_outlined, size: 40, color: ManaColors.textSecondary),
                            const SizedBox(height: ManaSpacing.md),
                            ManaText.raw(ref.t('no_groups_yet'),
                                textAlign: TextAlign.center,
                                style: ManaType.cardTitle),
                            const SizedBox(height: ManaSpacing.sm),
                            // The dead end: "Create Group" builds a group
                            // out of EXISTING loans, and this business has
                            // none, so the create screen has nothing to
                            // select and cannot be completed. Say that here
                            // rather than letting the Owner discover it two
                            // taps in.
                            ManaText.raw(
                              ref.t('no_groups_yet_detail'),
                              textAlign: TextAlign.center,
                              style: ManaType.note,
                            ),
                          ],
                        ),
                      )
                    else
                      ...state.groups.map((g) => Card(
                            child: ListTile(
                              leading: Icon(Icons.groups_outlined, color: ManaColors.brand),
                              title: ManaText.raw(g.groupName),
                              subtitle: ManaText.raw(
                                  ref.t('members_count_note').replaceAll('{count}', '${g.memberCount}')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => GroupLoanDetailScreen(groupId: g.groupId)),
                              ),
                            ),
                          )),
                  ],
                ),
        ),
      ),
    );
  }

  void _openCreateGroup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _CreateGroupScreen(businessId: widget.businessId)),
    );
  }
}

class _CreateGroupScreen extends ConsumerStatefulWidget {
  final String businessId;
  const _CreateGroupScreen({required this.businessId});

  @override
  ConsumerState<_CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<_CreateGroupScreen> {

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  List<GroupMemberLoan> _results = const [];
  final Set<String> _selectedLoanIds = {};
  bool _searching = false;
  bool _saving = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    final results = await ref
        .read(groupLoanListProvider.notifier)
        .searchEligibleLoans(widget.businessId, query: _searchController.text.trim());
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('create_group')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: ref.t('group_name_field')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(labelText: ref.t('search_existing_loans_field')),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ElevatedButton(onPressed: _searching ? null : _search, child: ManaText.raw(ref.t('search'))),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            if (_results.isEmpty)
              ManaText.raw(ref.t('search_loans_to_add_note'),
                  style: ManaType.secondary)
            else
              // Checkmark-ListTile selection pattern — Radio/RadioListTile
              // is deprecated in this SDK version, per project convention.
              ..._results.map((loan) {
                final selected = _selectedLoanIds.contains(loan.loanId);
                return Card(
                  child: ListTile(
                    leading: Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? ManaColors.statusGood : ManaColors.textSecondary,
                    ),
                    title: ManaText.raw('${loan.customerName} — ${loan.loanNumber}'),
                    subtitle: ManaText.raw(ref
                        .t('balance_status_note')
                        .replaceAll('{balance}', manaRupees(loan.remainingBalance))
                        .replaceAll('{status}', loan.status)),
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedLoanIds.remove(loan.loanId);
                      } else {
                        _selectedLoanIds.add(loan.loanId);
                      }
                    }),
                  ),
                );
              }),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton(
              onPressed: _nameController.text.trim().isEmpty || _selectedLoanIds.isEmpty || _saving
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      setState(() => _saving = true);
                      final ok = await NetworkErrorHandler.run(context, () async {
                        return ref.read(groupLoanListProvider.notifier).createGroup(
                              businessId: widget.businessId,
                              groupName: _nameController.text.trim(),
                              memberLoanIds: _selectedLoanIds.toList(),
                            );
                      });
                      if (!mounted) return;
                      setState(() => _saving = false);
                      if (ok == true) navigator.pop();
                    },
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('confirm_label')),
            ),
          ],
        ),
      ),
    );
  }
}

class GroupLoanDetailScreen extends ConsumerWidget {
  final String groupId;
  const GroupLoanDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDetail = ref.watch(groupLoanDetailProvider(groupId));

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('group_detail')),
        actions: [
          asyncDetail.maybeWhen(
            data: (detail) => PopupMenuButton<String>(
              onSelected: (v) => _handleMenu(context, ref, v, detail),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: ManaText.raw(ref.t('rename'))),
                PopupMenuItem(
                  value: 'delete',
                  enabled: detail.eligibleForDeletion,
                  child: ManaText.raw(
                      ref.t(detail.eligibleForDeletion ? 'delete_group' : 'delete_balance_positive')),
                ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: asyncDetail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
              child: ManaText.raw(ref.t('could_not_load_group_note').replaceAll('{error}', '$e'),
                  textAlign: TextAlign.center)),
          data: (detail) => ListView(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            children: [
              ManaText.raw(detail.summary.groupName,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: ManaSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: ManaText.raw(ref.t('group_balance'),
                                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: ManaSpacing.xs),
                          ManaText.raw(manaRupees(detail.groupBalance),
                              style: ManaType.strong),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: ManaText.raw(ref.t('group_emi'),
                                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: ManaSpacing.xs),
                          ManaText.raw(manaRupees(detail.groupEmi),
                              style: ManaType.strong),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ManaText.raw(
                        ref.t('computed_live_note'),
                        style: ManaType.note,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
              ManaText.raw(ref.t('members'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: ManaSpacing.sm),
              ...detail.members.map((m) => Card(
                    child: ListTile(
                      title: ManaText.raw('${m.customerName} — ${m.loanNumber}'),
                      subtitle: ManaText.raw(ref
                          .t('balance_emi_note')
                          .replaceAll('{balance}', manaRupees(m.remainingBalance))
                          .replaceAll('{emi}', manaRupees(m.installmentAmount))),
                      trailing: ManaTrailingStatus(
                        label: m.status,
                        status: m.status == 'Closed'
                            ? ManaStatus.good
                            : (m.status == 'Defaulted' ? ManaStatus.bad : ManaStatus.neutral),
                      ),
                      // Stale comment fixed: OW-007 has been built for a
                      // while now — this just never got wired to it.
                      onTap: () => context.push('/ow-007', extra: m.loanId),
                    ),
                  )),
              const SizedBox(height: ManaSpacing.md),
              ManaText.raw(
                ref.t('membership_fixed_note'),
                style: ManaType.note,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    String action,
    GroupLoanDetail detail,
  ) async {
    if (action == 'rename') {
      final controller = TextEditingController(text: detail.summary.groupName);
      final newName = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: ManaText.raw(ref.t('rename_group')),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: ManaText.raw(ref.t('cancel'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: ManaText.raw(ref.t('save')),
            ),
          ],
        ),
      );
      if (newName == null || newName.isEmpty || !context.mounted) return;
      await NetworkErrorHandler.run(context, () async {
        return ref.read(groupLoanDetailProvider(groupId).notifier).rename(newName);
      });
    } else if (action == 'delete') {
      if (!detail.eligibleForDeletion) return; // gated on Group Balance = ₹0
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: ManaText.raw(ref.t('delete_group')),
          content: ManaText.raw(ref.t('delete_group_note')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: ManaText.raw(ref.t('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: ManaText.raw(ref.t('delete'))),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      final ok = await NetworkErrorHandler.run(context, () async {
        return ref.read(groupLoanDetailProvider(groupId).notifier).deleteGroup();
      });
      if (ok == true && context.mounted) Navigator.of(context).pop();
    }
  }
}
