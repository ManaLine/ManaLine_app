import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../features/owner_workspace/state/customer_state.dart';
import '../design/components/mana_amount.dart';
import '../design/components/mana_text.dart';
import 'translation_service.dart';

/// A customer's collection history — the same list for whoever is reading it.
///
/// OW-004 and AG-004 each carried a copy. Unlike the Summary, Loans and
/// Remarks tabs beside it — which differ by role for real reasons — these two
/// were identical apart from the class name, down to the separator dots. A
/// receipt says what was paid, when, how and by whom; none of that changes
/// with who is looking, and the Agent has no less right to their own round's
/// receipts than the Owner does.
///
/// Read-only for both. Money is never entered here; it is entered in the
/// round.
class CustomerCollectionsTab extends ConsumerWidget {
  final CustomerProfile profile;
  const CustomerCollectionsTab({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profile.collections.isEmpty) {
      return Center(
        child: ManaText.raw(ref.t('no_collections_yet'), style: ManaType.secondary),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: profile.collections
          .map((c) => ListTile(
                leading: Icon(Icons.receipt_long_outlined, color: ManaColors.brand),
                title: ManaText.raw(manaRupees(c.amount)),
                subtitle: ManaText.raw('${c.paymentMode} · ${c.collector} · #${c.receiptNumber}'),
                trailing: ManaText.raw(DateFormat('d MMM').format(c.businessDate),
                    style: TextStyle(fontSize: 16, color: ManaColors.textSecondary)),
              ))
          .toList(),
    );
  }
}
