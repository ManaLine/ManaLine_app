import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../features/owner_workspace/state/owner_api_service.dart';
import '../features/owner_workspace/state/owner_workspace_state.dart';
import 'network_error_handler.dart';
import 'translation_service.dart';

/// Pick an agent from the ones this business actually has.
///
/// What this replaces sent the literal string 'stub-agent-id' into a real
/// UPDATE on loans.collection_agent_membership_id, with a comment promising a
/// "real build" later. It never came. Worse, the screen showed "Agent
/// transferred" without looking at the result, so a transfer that could never
/// have worked reported success -- and PostgREST returns 200 for an UPDATE
/// that matches zero rows, so nothing anywhere would have said otherwise.
///
/// Returns the chosen membership_id, or null if the sheet was dismissed.
Future<String?> showAgentPickerSheet(
  BuildContext context,
  WidgetRef ref, {
  required String businessId,

  /// Shown as the current holder and excluded from the list -- transferring a
  /// loan to the agent who already has it is not a transfer.
  String? currentMembershipId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AgentPickerBody(
      businessId: businessId,
      currentMembershipId: currentMembershipId,
    ),
  );
}

class _AgentPickerBody extends ConsumerStatefulWidget {
  final String businessId;
  final String? currentMembershipId;
  const _AgentPickerBody({required this.businessId, this.currentMembershipId});

  @override
  ConsumerState<_AgentPickerBody> createState() => _AgentPickerBodyState();
}

class _AgentPickerBodyState extends ConsumerState<_AgentPickerBody> {
  List<AgentSummary>? _agents;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final agents = await NetworkErrorHandler.run(context, () async {
      return ref
          .read(ownerApiServiceProvider)
          .fetchAgents(businessId: widget.businessId);
    });
    if (!mounted) return;
    setState(() {
      _agents = agents
              ?.where((a) =>
                  a.membershipId != null &&
                  a.membershipId != widget.currentMembershipId &&
                  a.status == 'Active')
              .toList() ??
          const [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final agents = _agents ?? const <AgentSummary>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(ref.t('transfer_to_agent'), style: ManaType.cardTitle),
          const SizedBox(height: ManaSpacing.sm),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(ManaSpacing.lg),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (agents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.lg),
              child: ManaText.raw(ref.t('no_other_active_agent_note'),
                  style: ManaType.secondary),
            )
          else
            // Bounded: a business with thirty agents must not push the sheet
            // past the screen and take its own list with it.
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: agents.length,
                itemBuilder: (context, i) {
                  final a = agents[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: ManaText.raw(a.fullName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: ManaText.raw(
                      [a.mlid, a.phoneNumber]
                          .where((x) => x.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ManaType.note,
                    ),
                    trailing: Icon(Icons.chevron_right,
                        color: ManaColors.textSecondary),
                    onTap: () => Navigator.of(context).pop(a.membershipId),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
