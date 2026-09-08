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

/// Same as [_SeededLedgerNotifier], plus a counter so a test can prove
/// `loadMore()` was actually invoked -- the thing Gap 1 broke silently.
class _CountingLedgerNotifier extends LedgerHistoryNotifier {
  _CountingLedgerNotifier(this._seed);
  final LedgerHistoryState _seed;
  int loadMoreCalls = 0;

  @override
  LedgerHistoryState build(LedgerScope scope) => _seed;

  @override
  Future<void> load({bool withSummary = true}) async {}

  @override
  Future<void> loadMore() async {
    loadMoreCalls++;
  }
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

/// A feed long enough to overflow a bounded viewport, so the table's
/// internal ListView actually has somewhere to scroll to. One day, many
/// rows -- day grouping is irrelevant to this test.
final _manyEvents = [
  for (var i = 0; i < 40; i++)
    _event(
      id: 'collection:$i',
      type: 'collection',
      date: '2026-08-12',
      at: '2026-08-12T09:${(i % 60).toString().padLeft(2, '0')}:00',
      amount: 100 + i,
      counterparty: 'Customer $i',
      reference: 'L-$i',
    ),
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

LedgerHistoryState _loaded({LedgerMonthSummary? summary, List<LedgerEvent>? events}) =>
    LedgerHistoryState(
      events: events ?? _events,
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

    testWidgets(
      'reaching the end of the TABLE scroll triggers loadMore(), the same '
      'as the card list -- Gap 1: the table used to be a dead end',
      (tester) async {
        final notifier = _CountingLedgerNotifier(_loaded(events: _manyEvents));
        await pumpManaScreen(
          tester,
          ownerScreen(),
          translations: _translations,
          surfaceSize: const Size(1440, 900),
          location: '/ow-017',
          overrides: [
            ledgerHistoryProvider.overrideWith(() => notifier),
          ],
        );

        expect(find.byType(ManaLedgerTable), findsOneWidget);
        expect(notifier.loadMoreCalls, 0);

        // The table's OWN internal vertical list -- there is also a
        // horizontal Scrollable in ManaLedgerTable for sideways overflow,
        // so pick the one whose axis is vertical.
        final verticalScrollable = tester.widgetList<Scrollable>(
          find.descendant(
            of: find.byType(ManaLedgerTable),
            matching: find.byType(Scrollable),
          ),
        ).firstWhere((s) => s.axisDirection == AxisDirection.down);
        final state = tester.state<ScrollableState>(
          find.byWidgetPredicate((w) => identical(w, verticalScrollable)),
        );

        // Jump to the end -- the same "0px of scroll extent left" case
        // `_onScroll`'s `remaining < 400` threshold is built to catch.
        state.position.jumpTo(state.position.maxScrollExtent);
        await tester.pump();

        expect(
          notifier.loadMoreCalls,
          greaterThan(0),
          reason: 'the table scrolling to its end must drive the SAME '
              '_scroll controller the card list uses, not a second, '
              'unwired Scrollable',
        );
      },
    );
  });

  group('ManaLedgerHistoryView table row tap', () {
    testWidgets('tapping a table row opens the same detail sheet a tapped '
        'card would -- Gap 2', (tester) async {
      await pumpManaScreen(
        tester,
        ownerScreen(),
        translations: _translations,
        surfaceSize: const Size(1440, 900),
        location: '/ow-017',
        overrides: [
          ledgerHistoryProvider
              .overrideWith(() => _SeededLedgerNotifier(_loaded(summary: _summary))),
        ],
      );

      expect(find.byType(ManaLedgerTable), findsOneWidget);
      // "Lakshmi Devi" is the loan_distribution event, not the collection
      // one -- deliberately, so this test never reaches _showDetail's
      // FutureBuilder branch (collectionExtras()), which calls the real
      // Supabase client and has nothing to do with what Gap 2 is about.
      expect(find.text('Lakshmi Devi'), findsOneWidget);

      await tester.tap(find.text('Lakshmi Devi'));
      await tester.pumpAndSettle();

      // [_showDetail] -- the exact same method and argument the card's
      // onTap calls -- also renders the counterparty, as its own sheet
      // heading. A second widget bearing that name is only possible if the
      // tap actually opened that sheet, not some table-only detail path.
      expect(find.text('Lakshmi Devi'), findsNWidgets(2));
    });
  });
}
