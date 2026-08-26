import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ledger_history_view.dart';

/// AG-010 — Transaction History, Agent view.
///
/// Same widget as OW-017. The membershipId is what makes it the AGENT's
/// ledger: the opening and carried-forward lines then describe this Agent's
/// own float rather than the business's cash, and the month band -- which is
/// read from day_ledger, the business's position -- is not shown at all.
///
/// Showing an Agent the business's closing balance would read as cash they
/// are holding.
class Ag010TransactionHistoryScreen extends ConsumerWidget {
  final String businessId;
  final String agentMembershipId;
  const Ag010TransactionHistoryScreen({
    super.key,
    required this.businessId,
    required this.agentMembershipId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaLedgerHistoryView(
      businessId: businessId,
      membershipId: agentMembershipId,
      homeRoute: '/ag-001',
    );
  }
}
