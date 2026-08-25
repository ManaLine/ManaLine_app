import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/collection_round_view.dart';
import '../../owner_workspace/screens/ow_006_collection_mode.dart' show CollectionEntryScreen;

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
  const AgentCollectionModeScreen({super.key, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaCollectionRound(
      businessId: businessId,
      onBack: () => context.go('/ag-001', extra: businessId),
      onOpenRow: (context, row) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CollectionEntryScreen(row: row, businessId: businessId),
        ),
      ),
    );
  }
}
