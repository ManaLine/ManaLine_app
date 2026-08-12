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
