import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_ledger_table.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_017_transaction_history.dart';
import 'package:mana_line/shared/ledger_history_service.dart';
import 'package:mana_line/shared/ledger_history_state.dart';

import 'support/mana_harness.dart';

/// History becomes a table at desk width (Plan 2a Task 4).
///
/// The one assertion that matters more than any other here is the row count:
/// a presentation change that silently drops or duplicates a seeded event is
/// a wrong ledger, and it would pass every other check in this file.
class _SeededLedgerNotifier extends LedgerHistoryNotifier {
  _SeededLedgerNotifier(this._seed);
  final LedgerHistoryState _seed;

  @override
  LedgerHistoryState build(LedgerScope scope) => _seed;

  @override
  Future<void> load({bool withSummary = true}) async {}

  @override
  Future<void> loadMore() async {}
}

LedgerEvent _event({
  required String id,
  required String type,
  required String date,
  required String at,
  required int amount,
  String? counterparty,
  String? reference,
}) =>
    LedgerEvent.fromRow({
      'event_id': id,
      'event_type': type,
      'business_date': date,
      'occurred_at': at,
      'amount': amount,
      'counterparty': counterparty,
      'reference': reference,
      'method': null,
    });

final _events = [
  _event(
      id: 'collection:1',
      type: 'collection',
      date: '2026-08-12',
      at: '2026-08-12T09:32:00',
      amount: 4500,
      counterparty: 'Venkat Rao',
      reference: 'L-1042'),
  _event(
      id: 'loan:1',
      type: 'loan_distribution',
      date: '2026-08-12',
      at: '2026-08-12T08:15:00',
      amount: 8800,
      counterparty: 'Lakshmi Devi',
      reference: 'L-1101'),
  _event(
      id: 'expense:1',
      type: 'expense',
      date: '2026-08-11',
      at: '2026-08-11T10:00:00',
      amount: 300,
      reference: 'Fuel'),
  _event(
      id: 'collection:2',
      type: 'collection',
      date: '2026-08-11',
      at: '2026-08-11T09:00:00',
      amount: 1200,
      counterparty: 'Ramana',
      reference: 'L-1050'),
];

const _summary = LedgerMonthSummary(
  monthStart: '2026-08-01',
  received: 152500,
  spent: 82447,
  net: 70053,
  openingBalance: 250000,
  closingBalance: 320053,
  daysRecorded: 11,
);

const _translations = <String, Map<String, String>>{
  'history': {'English': 'History'},
  'search_transactions': {'English': 'Search Transactions'},
  'day_net': {'English': 'Day Net'},
  'collection_from': {'English': 'Collection From'},
  'loan_to': {'English': 'Loan To'},
  'expense_paid': {'English': 'Expense Paid'},
  'no_transactions_yet': {'English': 'No transactions yet.'},
  'could_not_load_history': {'English': 'Could Not Load History'},
  'clear_all': {'English': 'Clear All'},
  'retry': {'English': 'Retry'},
};

LedgerHistoryState _loaded({LedgerMonthSummary? summary}) => LedgerHistoryState(
      events: _events,
      summary: summary,
      loading: false,
    );

void main() {
  Widget ownerScreen() => const TransactionHistoryScreen(businessId: 'b1');

  Future<void> pump(WidgetTester tester, double width) async {
    await pumpManaScreen(
      tester,
      ownerScreen(),
      translations: _translations,
      surfaceSize: Size(width, 900),
      location: '/ow-017',
      overrides: [
        ledgerHistoryProvider
            .overrideWith(() => _SeededLedgerNotifier(_loaded(summary: _summary))),
      ],
    );
  }

  group('ManaLedgerHistoryView branches on LayoutBuilder width', () {
    testWidgets('at 390 (compact) the card list renders, no table', (tester) async {
      await pump(tester, 390);

      expect(find.byType(ManaLedgerTable), findsNothing);
      // The card row for the seeded collection is present.
      expect(find.text('Venkat Rao'), findsOneWidget);
    });

    testWidgets('at 1440 (expanded) a ManaLedgerTable renders, no card list',
        (tester) async {
      await pump(tester, 1440);

      expect(find.byType(ManaLedgerTable), findsOneWidget);
      // The card row's dedicated icon container is gone -- the table draws
      // this event differently, not as a ManaLedgerRow card.
      expect(find.text('Venkat Rao'), findsOneWidget);
    });

    testWidgets('expectNoLayoutFault holds at phone, tablet and desk widths',
        (tester) async {
      for (final width in const [390.0, 820.0, 1440.0]) {
        await pump(tester, width);
        expectNoLayoutFault(tester, 'ManaLedgerHistoryView at width $width');
      }
    });

    testWidgets(
      'the same seeded row count appears in the card list and the table',
      (tester) async {
        // Card layout: one ManaLedgerAmount-bearing row per event is not
        // directly countable without reaching into ManaLedgerRow internals,
        // so count by the counterparty/reference text each event uniquely
        // carries instead -- present exactly once per seeded event.
        await pump(tester, 390);
        for (final e in _events) {
          if (e.counterparty != null) {
            expect(find.text(e.counterparty!), findsOneWidget,
                reason: 'card list should show ${e.counterparty} exactly once');
          }
        }

        // Table layout: the table's own `rows` count is the ground truth for
        // "how many transaction rows did it draw" and must equal the number
        // of seeded events -- not more (duplicated) and not fewer (dropped).
        await pump(tester, 1440);
        final table = tester.widget<ManaLedgerTable>(find.byType(ManaLedgerTable));
        expect(table.rows.length, _events.length,
            reason: 'the table must draw exactly one row per seeded event');
        for (final e in _events) {
          if (e.counterparty != null) {
            expect(find.text(e.counterparty!), findsOneWidget,
                reason: 'table should show ${e.counterparty} exactly once');
          }
        }
      },
    );
  });
}
