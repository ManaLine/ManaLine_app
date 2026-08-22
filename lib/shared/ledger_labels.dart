/// Turning a ledger event into words.
///
/// Kept out of the widgets so `ManaLedgerRow` stays free of the translation
/// service and can be laid out in tests without one, and so OW-017 and AG-010
/// cannot end up calling the same movement two different things.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'ledger_history_service.dart';
import 'translation_service.dart';

final _dayFmt = DateFormat('EEE d MMM');
final _timeFmt = DateFormat('h:mm a');

/// "Collection from", "Loan to", "Expense" — the action, not the noun.
///
/// Phrased as the business's own action so a row reads as a sentence with the
/// counterparty: "Collection from Venkat Rao". Events with no other party
/// (an expense, a settlement short) get a standalone label instead.
String ledgerActionLabel(WidgetRef ref, LedgerEvent e) => switch (e.type) {
      LedgerEventType.bfGrant => ref.t('bf_given_to'),
      LedgerEventType.collection => ref.t('collection_from'),
      LedgerEventType.loanDistribution => ref.t('loan_to'),
      LedgerEventType.expense => ref.t('expense_paid'),
      LedgerEventType.investorDeposit => ref.t('deposit_from'),
      LedgerEventType.investorWithdrawal => ref.t('withdrawal_to'),
      LedgerEventType.chetiPaid => ref.t('cheti_instalment_paid'),
      LedgerEventType.chetiReceived => ref.t('cheti_amount_availed'),
      LedgerEventType.adjustmentShort => ref.t('settlement_short'),
      LedgerEventType.adjustmentExcess => ref.t('settlement_excess'),
    };

/// Filter-sheet name for a type — the category, not the action.
String ledgerTypeLabel(WidgetRef ref, LedgerEventType t) => switch (t) {
      LedgerEventType.bfGrant => ref.t('bf_given'),
      LedgerEventType.collection => ref.t('collections'),
      LedgerEventType.loanDistribution => ref.t('loans_issued'),
      LedgerEventType.expense => ref.t('expenses'),
      LedgerEventType.investorDeposit => ref.t('deposits_investor'),
      LedgerEventType.investorWithdrawal => ref.t('withdrawals_investor'),
      LedgerEventType.chetiPaid => ref.t('cheti_paid_label'),
      LedgerEventType.chetiReceived => ref.t('cheti_received_label'),
      LedgerEventType.adjustmentShort => ref.t('settlement_short'),
      LedgerEventType.adjustmentExcess => ref.t('settlement_excess'),
    };

/// "Tue 12 Aug" for a `yyyy-MM-dd` business date.
///
/// Formats the business date directly and never converts it through a
/// timezone: it is already the Indian calendar day the money belongs to.
String ledgerDayLabel(String businessDate) =>
    _dayFmt.format(DateTime.parse(businessDate));

String ledgerTimeLabel(LedgerEvent e) => _timeFmt.format(e.occurredAt);

/// What a collection's outcome means, in words.
///
/// `LedgerEvent.method` carries the raw `result_type` — Full, Partial, Excess
/// — and it is the only thing that column ever holds. Shown as-is it told the
/// Owner nothing: "Details: Excess" beside a collection reads as a warning
/// when it only means the customer paid more than one instalment. It is also
/// the commonest outcome on a migrated book, where 44 of this business's 250
/// replayed instalments are someone paying two weeks at once.
///
/// Anything unrecognised is passed through rather than swallowed: a new
/// result_type should show up as itself, not disappear.
String? ledgerOutcomeLabel(WidgetRef ref, LedgerEvent e) {
  if (e.method == null) return null;
  if (e.type != LedgerEventType.collection) return e.method;
  return switch (e.method) {
    'Full' => ref.t('paid_the_full_instalment'),
    'Partial' => ref.t('less_than_the_instalment'),
    'Excess' => ref.t('more_than_the_instalment'),
    'No Collection' => ref.t('nothing_collected'),
    _ => e.method,
  };
}
