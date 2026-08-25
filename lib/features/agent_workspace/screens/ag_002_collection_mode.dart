import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/collection_round_view.dart';

/// AG-002 — Collection Mode (Agent).
///
/// This file used to carry its own 210-line copy of the round, and its own
/// comment admitted the due row was "a near-verbatim duplicate" of OW-006's.
/// The duplicate is why the Agent -- the person who actually walks the round
/// -- was still looking at the old list days after the Owner's was rebuilt.
///
/// What differs by role is only where Back goes. What gets WRITTEN is decided
/// server-side: record_collection checks `own_active_agent_membership_permits`
/// and `can_collect_payments`, so an Agent can only ever record a collection
/// as themselves. Sharing the widget cannot merge the entries.
class AgentCollectionModeScreen extends ConsumerWidget {
  final String businessId;

  /// A loan to open the row for on arrival. AG-004 sends the Agent here from a
  /// customer's own loan, and landing on the plain round would make them find
  /// it again in a list of everyone due today.
  final String? focusLoanId;

  const AgentCollectionModeScreen(
      {super.key, required this.businessId, this.focusLoanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaCollectionRound(
      businessId: businessId,
      focusLoanId: focusLoanId,
      onBack: () => context.go('/ag-001', extra: businessId),
    );
  }
}
