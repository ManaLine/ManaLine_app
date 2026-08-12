import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_010_transaction_history.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_017_transaction_history.dart';
import 'package:mana_line/shared/ledger_history_service.dart';
import 'package:mana_line/shared/ledger_history_state.dart';

import 'support/mana_harness.dart';

/// OW-017 and AG-010 share one feed, one row component and one notifier. What
/// they must NOT share is the summary: the agent's feed is an RLS-filtered
/// subset, so a business-wide net or a closing balance on that screen would be
/// a confident number computed from an incomplete set — the same failure the
/// Day Closure opening balance had.
class _SeededLedgerNotifier extends LedgerHistoryNotifier {
  _SeededLedgerNotifier(this._seed);
  final LedgerHistoryState _seed;

  @override
  LedgerHistoryState build(String businessId) => _seed;

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
  'transaction_history': {'English': 'Transaction History'},
  'my_statements': {'English': 'My Statements'},
  'search_transactions': {'English': 'Search Transactions'},
  'day_net': {'English': 'Day Net'},
  'you_collected': {'English': 'You Collected'},
  'your_activity_only_note': {
    'English': 'Your own activity on this business. Not the full business history.'
  },
  'collection_from': {'English': 'Collection From'},
  'loan_to': {'English': 'Loan To'},
  'expense_paid': {'English': 'Expense Paid'},
  'no_transactions_yet': {'English': 'No transactions yet.'},
  'no_transactions_recorded_yet': {'English': 'No transactions recorded yet.'},
  'no_transactions_match_filters': {'English': 'No Transactions Match These Filters'},
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
  Widget agentScreen() => const Ag010TransactionHistoryScreen(
        businessId: 'b1',
        agentMembershipId: 'm1',
      );

  // The minus sign ManaAmount uses is U+2212, not a hyphen — deliberately, so
  // a negative money figure cannot be misread at a glance.
  const minus = '−';

  group('OW-017 owner history', () {
    testWidgets('shows every event type the feed returns', (tester) async {
      await pumpManaScreen(
        tester,
        ownerScreen(),
        translations: _translations,
        surfaceSize: const Size(360, 1400),
        overrides: [
          ledgerHistoryProvider
              .overrideWith(() => _SeededLedgerNotifier(_loaded(summary: _summary))),
        ],
      );

      // The screen this replaced could not show an expense at all.
      expect(find.text('Collection From'), findsOneWidget);
      expect(find.text('Loan To'), findsOneWidget);
      expect(find.text('Expense Paid'), findsOneWidget);
      expect(find.text('Venkat Rao'), findsOneWidget);
    });

    testWidgets('groups by business day with a day net', (tester) async {
      await pumpManaScreen(
        tester,
        ownerScreen(),
        translations: _translations,
        surfaceSize: const Size(360, 1400),
        overrides: [
          ledgerHistoryProvider
              .overrideWith(() => _SeededLedgerNotifier(_loaded(summary: _summary))),
        ],
      );

      expect(find.text('Wed 12 Aug'), findsOneWidget);
      expect(find.text('Tue 11 Aug'), findsOneWidget);
      expect(find.text('Day Net'), findsNWidgets(2));
      // 12 Aug: 4,500 collected less 8,800 lent.
      expect(find.text('$minus₹4,300'), findsOneWidget);
    });

    testWidgets('month figure is the summary, not the sum of visible rows',
        (tester) async {
      await pumpManaScreen(
        tester,
        ownerScreen(),
        translations: _translations,
        surfaceSize: const Size(360, 1400),
        overrides: [
          ledgerHistoryProvider
              .overrideWith(() => _SeededLedgerNotifier(_loaded(summary: _summary))),
        ],
      );

      // The three loaded rows net to -4,600. The band must show day_ledger's
      // +70,053 instead; showing -4,600 would be the old "Net Change" defect
      // wearing a new label.
      expect(find.text('+₹70,053'), findsOneWidget);
      expect(find.text('$minus₹4,600'), findsNothing);
    });
  });

  group('AG-010 agent history', () {
    testWidgets('says the view is the agent own slice', (tester) async {
      await pumpManaScreen(
        tester,
        agentScreen(),
        translations: _translations,
        surfaceSize: const Size(360, 1400),
        overrides: [
          ledgerHistoryProvider.overrideWith(() => _SeededLedgerNotifier(_loaded())),
        ],
      );

      expect(
        find.text('Your own activity on this business. Not the full business history.'),
        findsOneWidget,
      );
    });

    testWidgets('never shows a day net or a business month figure', (tester) async {
      // Seeded WITH a summary on purpose: even if one reaches the state, the
      // agent screen must not render it.
      await pumpManaScreen(
        tester,
        agentScreen(),
        translations: _translations,
        surfaceSize: const Size(360, 1400),
        overrides: [
          ledgerHistoryProvider
              .overrideWith(() => _SeededLedgerNotifier(_loaded(summary: _summary))),
        ],
      );

      expect(find.text('Day Net'), findsNothing);
      expect(find.text('+₹70,053'), findsNothing);
      expect(find.text('$minus₹4,300'), findsNothing);
      // What it shows instead: money in only, unsigned, labelled as the
      // agent's own.
      expect(find.text('You Collected'), findsNWidgets(2));
      expect(find.text('₹4,500'), findsWidgets);
    });
  });

  group('layout holds at every text scale', () {
    for (final scale in kManaTextScales) {
      testWidgets('OW-017 survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          ownerScreen(),
          textScale: scale,
          translations: _translations,
          overrides: [
            ledgerHistoryProvider
                .overrideWith(() => _SeededLedgerNotifier(_loaded(summary: _summary))),
          ],
        );
        expectNoLayoutFault(tester, 'OW-017 at ${scale}x');
      });

      testWidgets('AG-010 survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          agentScreen(),
          textScale: scale,
          translations: _translations,
          overrides: [
            ledgerHistoryProvider.overrideWith(() => _SeededLedgerNotifier(_loaded())),
          ],
        );
        expectNoLayoutFault(tester, 'AG-010 at ${scale}x');
      });
    }
  });
}
