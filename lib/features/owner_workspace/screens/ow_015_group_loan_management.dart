import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/group_loan_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

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
        title: const ManaText('group loan management'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateGroup(context),
        icon: const Icon(Icons.add),
        label: const ManaText('create group'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(groupLoanListProvider.notifier).load(widget.businessId),
          child: state.loading && state.groups.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(ManaSpacing.md),
                      decoration:
                          BoxDecoration(color: ManaColors.statusWarnFaint, borderRadius: BorderRadius.circular(8)),
                      child: const ManaText.raw(
                        'GAP: no confirmed loan-groups API exists yet — this screen is built against '
                        'the implied shape only, pending a dedicated API addendum.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: ManaSpacing.md),
                    if (state.groups.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw('No groups yet.', style: TextStyle(color: ManaColors.textSecondary)),
                        ),
                      )
                    else
                      ...state.groups.map((g) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.groups_outlined, color: ManaColors.brass),
                              title: ManaText.raw(g.groupName),
                              subtitle: ManaText.raw('${g.memberCount} members'),
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
      appBar: AppBar(title: const ManaText('create group')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Group Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(labelText: 'Search existing loans'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ElevatedButton(onPressed: _searching ? null : _search, child: const ManaText('search')),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            if (_results.isEmpty)
              const ManaText.raw('Search for individual loans to add as group members.',
                  style: TextStyle(color: ManaColors.textSecondary))
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
                    subtitle: ManaText.raw('Balance ${_currency.format(loan.remainingBalance)} · ${loan.status}'),
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
                      if (ok == true) Navigator.of(context).pop();
                    },
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const ManaText('confirm'),
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
        title: const ManaText('group detail'),
        actions: [
          asyncDetail.maybeWhen(
            data: (detail) => PopupMenuButton<String>(
              onSelected: (v) => _handleMenu(context, ref, v, detail),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: ManaText('rename')),
                PopupMenuItem(
                  value: 'delete',
                  enabled: detail.eligibleForDeletion,
                  child: ManaText(detail.eligibleForDeletion ? 'delete group' : 'delete (balance > ₹0)'),
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
          error: (e, _) => Center(child: ManaText.raw('Could not load group.\n$e', textAlign: TextAlign.center)),
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
                          const ManaText('group balance'),
                          ManaText.raw(_currency.format(detail.groupBalance),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const ManaText('group emi'),
                          ManaText.raw(_currency.format(detail.groupEmi),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const ManaText.raw(
                        'Computed live from member loans — never stored.',
                        style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
              ManaText('members', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: ManaSpacing.sm),
              ...detail.members.map((m) => Card(
                    child: ListTile(
                      title: ManaText.raw('${m.customerName} — ${m.loanNumber}'),
                      subtitle: ManaText.raw(
                          'Balance ${_currency.format(m.remainingBalance)} · EMI ${_currency.format(m.installmentAmount)}'),
                      trailing: ManaStatusPill(
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
              const ManaText.raw(
                'Membership is fixed permanently at creation — no additions or removals.',
                style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
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
          title: const ManaText('rename group'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const ManaText('cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const ManaText('save'),
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
          title: const ManaText('delete group'),
          content: const ManaText.raw(
              'Member loans revert to ungrouped individual loans. This does not affect their own history.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const ManaText('delete')),
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
