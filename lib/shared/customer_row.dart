import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_amount.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../features/owner_workspace/state/customer_state.dart';
import 'translation_service.dart';

/// One customer in a list, for whoever is looking at the list.
///
/// OW-004 and AG-004 each had one of these, and only OW-004's was correct.
/// The Owner's carries a comment explaining why it is not a ListTile:
///
///   ListTile's trailing slot assumes a bounded width and height, which a
///   two-line trailing column (an amount above a "Due X") does not fit inside
///   once the text scale grows or the figures run long.
///
/// AG-004's was still a ListTile with exactly that trailing column, and it
/// overflowed by 107px at 1.0x -- in English, on the default screen, before
/// any scaling. The fix had been made once and did not reach the second copy,
/// which is the whole argument for this file existing.
///
/// The money goes on its own row beneath the name and village rather than
/// competing with them for width, and every side is bounded.
class ManaCustomerRow extends ConsumerWidget {
  final CustomerSummary customer;
  final VoidCallback onTap;

  /// The Agent's list leads with the father/husband name, the Owner's with
  /// the MLID. Same row, different second line -- a difference in what each
  /// role is scanning for, not in what the row is.
  final bool leadWithFatherHusbandName;

  const ManaCustomerRow({
    super.key,
    required this.customer,
    required this.onTap,
    this.leadWithFatherHusbandName = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagged = customer.membershipStatus != 'Active';
    final second = leadWithFatherHusbandName
        ? '${customer.fatherHusbandName} · ${customer.village} · LRI ${customer.lineRepaymentIndex}'
        : '${customer.village} · ${customer.mlid} · LRI ${customer.lineRepaymentIndex}';

    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ManaVerificationRing(isVerified: true, size: 40),
              const SizedBox(width: ManaSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: ManaText.raw(customer.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.emphasis),
                        ),
                        if (flagged) ...[
                          const SizedBox(width: ManaSpacing.xs),
                          Flexible(
                            child: ManaStatusPill(
                                label: customer.membershipStatus,
                                status: ManaStatus.bad),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    ManaText.raw(second,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ManaType.note),
                    const SizedBox(height: ManaSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: ManaText.raw(
                              manaRupees(customer.outstandingBalance),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.cardTitle),
                        ),
                        if (customer.todaysDue > 0) ...[
                          const SizedBox(width: ManaSpacing.sm),
                          Flexible(
                            // "Today's Due", not "Due" -- and deliberately not
                            // "EMI", which is what the collection round shows.
                            // They look like the same number and are not: the
                            // round shows ONE loan's instalment, this shows
                            // everything this customer owes today, which for
                            // somebody holding two loans is the sum of both.
                            // Reading one as the other is how a customer gets
                            // asked for the wrong money at their door.
                            child: ManaText.raw(
                                '${ref.t('todays_due')} '
                                '${manaRupees(customer.todaysDue)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 16,
                                    color: ManaColors.statusWarn)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
