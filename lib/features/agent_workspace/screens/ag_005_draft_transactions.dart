import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/draft_transactions_state.dart';
import 'ag_002_collection_mode.dart';
import 'ag_004_customer_management.dart';
import 'ag_007_loan_distribution.dart';

final _dateTimeFmt = DateFormat('dd-MM-yyyy, hh:mm a');

/// AG-005 — Draft Transactions.
///
/// Entry: AG-001 Quick Action "Draft Transactions", OR Collection
/// Interrupted (mid-entry in AG-002) → Save Draft (AG-002 hands the Agent
/// back here once the interrupted entry is stashed).
///
/// Permission-gated per agent_permissions: Create (can_create_drafts),
/// Continue/Edit (can_edit_own_drafts), Discard (can_cancel_own_drafts).
/// This screen only ever lists the calling Agent's own drafts — the
/// underlying `created_by_membership_id` filter is always applied, never
/// left open to show other Agents' drafts.
class DraftTransactionsScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String membershipId;
  final bool canEditOwnDrafts;
  final bool canCancelOwnDrafts;

  const DraftTransactionsScreen({
    super.key,
    required this.businessId,
    required this.membershipId,
    this.canEditOwnDrafts = true,
    this.canCancelOwnDrafts = true,
  });

  @override
  ConsumerState<DraftTransactionsScreen> createState() => _DraftTransactionsScreenState();
}

class _DraftTransactionsScreenState extends ConsumerState<DraftTransactionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(draftTransactionsProvider.notifier).load(
            businessId: widget.businessId,
            membershipId: widget.membershipId,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(draftTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const ManaText('draft transactions')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(draftTransactionsProvider.notifier).load(
                businessId: widget.businessId,
                membershipId: widget.membershipId,
              ),
          child: state.loading && state.drafts.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    if (state.openDrafts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw(
                            'No open drafts. Interrupted entries you Save Draft on will show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: ManaColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      ...state.openDrafts.map((d) => _DraftCard(
                            businessId: widget.businessId,
                            membershipId: widget.membershipId,
                            draft: d,
                            canEdit: widget.canEditOwnDrafts,
                            canDiscard: widget.canCancelOwnDrafts,
                          )),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DraftCard extends ConsumerWidget {
  final String businessId;
  final String membershipId;
  final DraftTransaction draft;
  final bool canEdit;
  final bool canDiscard;

  const _DraftCard({
    required this.businessId,
    required this.membershipId,
    required this.draft,
    required this.canEdit,
    required this.canDiscard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ManaStatusPill(label: draft.draftType.schemaValue, status: ManaStatus.neutral),
                ManaText.raw(_dateTimeFmt.format(draft.updatedAt),
                    style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              draft.customerName ?? 'Untitled Draft',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (draft.loanNumber != null) ...[
              const SizedBox(height: 2),
              ManaText.raw('Loan ${draft.loanNumber}',
                  style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            ],
            const SizedBox(height: 2),
            ManaText.raw('Created ${_dateTimeFmt.format(draft.createdAt)}',
                style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.md),
            Wrap(
              spacing: ManaSpacing.sm,
              children: [
                if (canEdit)
                  ElevatedButton(
                    onPressed: () => _continueDraft(context),
                    child: const ManaText('continue draft'),
                  ),
                OutlinedButton(
                  onPressed: () => _submit(context, ref),
                  child: const ManaText('submit'),
                ),
                if (canDiscard)
                  OutlinedButton(
                    onPressed: () => _confirmDiscard(context, ref),
                    style: OutlinedButton.styleFrom(foregroundColor: ManaColors.statusBad),
                    child: const ManaText('discard'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Continue Draft routes by draft_type — not to one generic screen.
  // Collection → AG-002, Loan Distribution → AG-007 (not built — TODO
  // route), Customer Remark/Document Upload → AG-004 (not built by this
  // chat — reference by route name only, per master brief).
  void _continueDraft(BuildContext context) {
    switch (draft.draftType) {
      case DraftType.collection:
        // Hands off into AG-002's own screen/provider — resume mechanics for
        // a pre-filled Collection Entry live there, not reimplemented here.
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AgentCollectionModeScreen(businessId: businessId)),
        );
        break;
      case DraftType.loanDistribution:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Ag007LoanDistributionScreen(agentId: membershipId, businessId: businessId),
          ),
        );
        break;
      case DraftType.customerRemark:
      case DraftType.documentUpload:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AgentCustomerManagementScreen(businessId: businessId, agentMembershipId: membershipId),
          ),
        );
        break;
    }
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(draftTransactionsProvider.notifier).submit(
            businessId: businessId,
            membershipId: membershipId,
            draftId: draft.draftId,
          );
    });
    // null covers both "network call failed" (handler already showed a
    // SnackBar) and "submitted but server-side validation rejected it"
    // (draft stays 'Draft', error surfaced via state.error) — either way,
    // stay put rather than assume success.
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Draft submitted.')),
    );
  }

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ManaText('discard draft'),
        content: const ManaText.raw('This draft will be permanently removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const ManaText('discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(draftTransactionsProvider.notifier).discard(
            businessId: businessId,
            membershipId: membershipId,
            draftId: draft.draftId,
          );
    });
  }
}
