import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ledger_history_view.dart';
import '../../../shared/widgets/workspace_nav.dart';

/// OW-017 — Transaction History, Owner view.
///
/// The screen is ManaLedgerHistoryView, shared with AG-010. The two carried
/// the same feed, rows and notifier through 327 differing lines of
/// duplication; what actually differs by role is whose balances are shown,
/// whether the business's month band appears, and one label.
///
/// A null membershipId is the business ledger.
class TransactionHistoryScreen extends ConsumerWidget {
  final String businessId;
  const TransactionHistoryScreen({super.key, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManaLedgerHistoryView(
      businessId: businessId,
      homeRoute: '/ow-001',
      statementRoute: '/ow-017-statement',
      // Index 3 is History, which is this screen.
      bottomNavigationBar: ManaWorkspaceNav(
          workspace: ManaWorkspace.owner,
          businessId: businessId,
          currentIndex: 3),
    );
  }
}
