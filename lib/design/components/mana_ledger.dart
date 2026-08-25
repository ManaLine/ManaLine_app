/// Ledger presentation: the row, the day header, and the month summary.
///
/// Shared by OW-017 (Owner, whole business) and AG-010 (Agent, the subset RLS
/// permits). One set of components so the two screens cannot drift into
/// showing the same money two different ways.
library;

import 'package:flutter/material.dart';

import '../../shared/ledger_history_service.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import 'mana_amount.dart';
import 'mana_text.dart';

/// Colour and glyph per direction.
///
/// Money out is NOT red. Red in this app means something is wrong — a short,
/// an overdue, a failure. A disbursed loan or a paid expense is the business
/// working as intended, so it takes ordinary text colour and only the arrow
/// and the missing `+` mark it as outgoing. Using red for every debit would
/// make a normal day look like a bad one.
({Color tint, IconData icon, ManaAmountTone tone}) ledgerVisual(
  bool isMoneyIn, {
  bool isTransfer = false,
}) =>
    isTransfer
        // Neither in nor out: cash moved between two pockets of the same
        // business. A sideways arrow and no green, because reading a BF grant
        // as income is exactly the mistake this direction exists to prevent.
        ? (
            tint: ManaColors.textSecondary,
            icon: Icons.swap_horiz,
            tone: ManaAmountTone.neutral,
          )
        : isMoneyIn
            ? (
                tint: ManaColors.statusGood,
                icon: Icons.south_west,
                tone: ManaAmountTone.positive,
              )
            : (
                tint: ManaColors.textSecondary,
                icon: Icons.north_east,
                tone: ManaAmountTone.neutral,
              );

/// An event's amount, toned and signed by its own direction.
///
/// Exists so the sign/tone rule lives in one place: every other call site
/// would otherwise have to remember that credits get a `+` and debits do not.
class ManaLedgerAmount extends StatelessWidget {
  final LedgerEvent event;
  final ManaAmountSize size;

  const ManaLedgerAmount({
    super.key,
    required this.event,
    this.size = ManaAmountSize.standard,
  });

  @override
  Widget build(BuildContext context) => ManaAmount(
        event.amount,
        size: size,
        tone: ledgerVisual(event.isMoneyIn, isTransfer: event.isTransfer).tone,
        // No sign on a transfer: a leading + would read as income.
        showSign: event.isMoneyIn && !event.isTransfer,
      );
}

/// One money movement.
///
/// Layout mirrors the shape people already read in payment apps: direction
/// glyph, what happened and with whom, amount hard right. The second line
/// carries the three things a lender actually checks — when, against what,
/// and how.
class ManaLedgerRow extends StatelessWidget {
  final LedgerEvent event;

  /// Already-translated action label, e.g. "Collection from" / "Loan to".
  /// Passed in rather than derived here so this widget stays free of the
  /// translation service and can be tested without one.
  final String actionLabel;

  /// Already-formatted clock time, e.g. "9:32 AM".
  final String timeLabel;

  final VoidCallback? onTap;

  const ManaLedgerRow({
    super.key,
    required this.event,
    required this.actionLabel,
    required this.timeLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final v = ledgerVisual(event.isMoneyIn, isTransfer: event.isTransfer);
    // Time is usually present; the other two often are not, and a row reading
    // "9:32 AM · · " would look broken. It is dropped entirely for a
    // backdated entry, where the ledger knows the day and not the hour —
    // callers pass an empty label for those.
    final detail = [
      if (timeLabel.isNotEmpty) timeLabel,
      if (event.reference != null && event.reference!.isNotEmpty) event.reference!,
      if (event.method != null && event.method!.isNotEmpty) event.method!,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ManaSpacing.lg,
          vertical: ManaSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: v.tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(v.icon, size: 18, color: v.tint),
            ),
            const SizedBox(width: ManaSpacing.md),
            // Expanded beside a non-flexible amount: the recurring overflow
            // bug in this codebase is exactly a bare child next to a
            // flexible one, and long Telugu names at 2.0x text scale are
            // where it bites.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText.raw(
                    actionLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                  ),
                  if (event.counterparty != null && event.counterparty!.isNotEmpty)
                    ManaText.raw(
                      event.counterparty!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 2),
                  ManaText.raw(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            ManaAmount(
              event.amount,
              tone: v.tone,
              showSign: event.isMoneyIn && !event.isTransfer,
              semanticLabel: actionLabel,
            ),
          ],
        ),
      ),
    );
  }
}

/// The day header — the one thing a generic transaction list would not have.
///
/// A business day here is a real accounting object: `day_ledger` gives it an
/// opening balance, a closing balance and a closure state, and Day Closure
/// reconciles against it. Surfacing that turns a flat feed into the ledger
/// the business actually runs on.
///
/// [trailingLabel] and [trailingAmount] are supplied by the caller precisely
/// because the honest trailing figure differs by role. For the Owner it is
/// the day's net. For an Agent — whose feed is an RLS-filtered subset — a net
/// would be a confident number computed from an incomplete set, so AG-010
/// passes its own activity total instead and never a closing balance.
/// The cash a day opened on, drawn as the day's first line.
///
/// A day does not begin at zero. Reading the movements without it made every
/// lending day look like a loss — the Owner asked how a day could be negative
/// when the cash box never is, and the answer was that the box was missing
/// from the screen.
class ManaLedgerOpeningRow extends StatelessWidget {
  final int amount;
  final String label;

  /// The closing line sits at the FOOT of the day and carries a rule above it,
  /// so a day reads as a small account: what was carried in, what moved, what
  /// was left.
  final bool isClosing;

  const ManaLedgerOpeningRow({
    super.key,
    required this.amount,
    required this.label,
    this.isClosing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ManaColors.surfaceMuted,
        border: isClosing
            ? Border(top: BorderSide(color: ManaColors.divider))
            : null,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ManaSpacing.lg,
        vertical: ManaSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
              isClosing
                  ? Icons.account_balance_wallet
                  : Icons.account_balance_wallet_outlined,
              size: 18,
              color: ManaColors.textSecondary),
          const SizedBox(width: ManaSpacing.sm),
          Expanded(
            child: ManaText.raw(
              label,
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ),
          const SizedBox(width: ManaSpacing.xs),
          Flexible(
            child: ManaAmount(amount, size: ManaAmountSize.compact),
          ),
        ],
      ),
    );
  }
}

class ManaLedgerDayHeader extends StatelessWidget {
  final String dateLabel;
  final String? statusLabel;
  final ManaStatus statusKind;
  final String trailingLabel;
  final int? trailingAmount;

  /// Sign and colour the trailing figure as a net. False for a one-directional
  /// total such as "collected", where a `+` would imply a net that it is not.
  final bool trailingIsNet;

  const ManaLedgerDayHeader({
    super.key,
    required this.dateLabel,
    required this.trailingLabel,
    this.trailingAmount,
    this.statusLabel,
    this.statusKind = ManaStatus.neutral,
    this.trailingIsNet = true,
  });

  @override
  Widget build(BuildContext context) {
    final amount = trailingAmount;
    return Container(
      width: double.infinity,
      color: ManaColors.surfaceSunken,
      padding: const EdgeInsets.symmetric(
        horizontal: ManaSpacing.lg,
        vertical: ManaSpacing.sm,
      ),
      child: Row(
        children: [
          Flexible(
            child: ManaText.raw(
              dateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          if (statusLabel != null) ...[
            const SizedBox(width: ManaSpacing.sm),
            Flexible(child: ManaStatusPill(label: statusLabel!, status: statusKind)),
          ],
          const Spacer(),
          const SizedBox(width: ManaSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                ManaText.raw(
                  trailingLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
                ),
                if (amount != null)
                  ManaAmount.compact(
                    amount,
                    showSign: trailingIsNet,
                    tone: !trailingIsNet
                        ? ManaAmountTone.neutral
                        : amount >= 0
                            ? ManaAmountTone.positive
                            : ManaAmountTone.neutral,
                    semanticLabel: trailingLabel,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The month band above the feed, and the card inside the month sheet.
///
/// The figures come from `day_ledger` via `app.ledger_month_summary`, never
/// from summing the visible rows. A page of rows is not a month, and a
/// filtered page certainly is not — that is precisely how the screen this
/// replaces produced a "Net Change" that was not any real quantity.
class ManaLedgerMonthBand extends StatelessWidget {
  final String monthLabel;
  final LedgerMonthSummary? summary;

  /// Shown instead of the net when the caller's view is a partial slice, so
  /// an Agent is never handed a business-wide figure.
  final bool showNet;

  final VoidCallback? onTap;

  const ManaLedgerMonthBand({
    super.key,
    required this.monthLabel,
    required this.summary,
    this.showNet = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: ManaColors.surface,
        padding: const EdgeInsets.symmetric(
          horizontal: ManaSpacing.lg,
          vertical: ManaSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: ManaText.raw(
                monthLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            // Flexible, not bare: at 2.0x text scale a long month name beside
            // a six-figure net overflows this Row by ~35px. A bare
            // unflexible child next to a flexible one is the overflow bug
            // this codebase has shipped repeatedly — caught here by
            // expectNoLayoutFault before it left the branch.
            if (s != null && showNet && !s.isEmpty)
              Flexible(
                child: ManaAmount(
                  s.net,
                  showSign: true,
                  tone: s.net >= 0 ? ManaAmountTone.positive : ManaAmountTone.neutral,
                  semanticLabel: monthLabel,
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 20, color: ManaColors.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Spent / Received / Net breakdown for the month sheet.
class ManaLedgerMonthBreakdown extends StatelessWidget {
  final LedgerMonthSummary summary;
  final String spentLabel;
  final String receivedLabel;
  final String openingLabel;
  final String closingLabel;

  const ManaLedgerMonthBreakdown({
    super.key,
    required this.summary,
    required this.spentLabel,
    required this.receivedLabel,
    required this.openingLabel,
    required this.closingLabel,
  });

  Widget _line(String label, int value, {ManaAmountTone tone = ManaAmountTone.neutral}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: ManaText.raw(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ),
          const SizedBox(width: ManaSpacing.sm),
          ManaAmount.compact(value, tone: tone, semanticLabel: label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(receivedLabel, summary.received, tone: ManaAmountTone.positive),
        _line(spentLabel, summary.spent),
        // Opening and closing only when day_ledger actually carried them.
        // A ₹0 opening that means "unknown" is the exact defect this pass
        // fixed on the Day Closure screen; it will not be reintroduced here.
        if (summary.openingBalance != null) ...[
          const Divider(height: ManaSpacing.lg),
          _line(openingLabel, summary.openingBalance!),
        ],
        if (summary.closingBalance != null) _line(closingLabel, summary.closingBalance!),
      ],
    );
  }
}
