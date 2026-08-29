import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/ledger_history_service.dart';
import 'package:mana_line/shared/ledger_history_state.dart';

/// The Owner's ledger and an Agent's ledger are two ledgers.
///
/// They were one. ledgerHistoryProvider was keyed on businessId alone, so
/// OW-017 (business feed) and OW-002's View Transactions (one agent's feed)
/// shared a single state object: whichever loaded last won, and a History
/// screen already built lower in the navigator stack never re-ran initState to
/// correct itself. The Owner went on reading the agent's rows as their own.
class _Recording extends LedgerHistoryNotifier {
  static final seen = <LedgerScope>[];

  @override
  LedgerHistoryState build(LedgerScope scope) {
    seen.add(scope);
    return const LedgerHistoryState();
  }
}

void main() {
  const business = 'b1';
  const agent = 'm-agent';

  setUp(_Recording.seen.clear);

  test('business and membership scopes are separate provider instances', () {
    final container = ProviderContainer(
      overrides: [ledgerHistoryProvider.overrideWith(_Recording.new)],
    );
    addTearDown(container.dispose);

    container.read(
        ledgerHistoryProvider((businessId: business, membershipId: null)));
    container.read(
        ledgerHistoryProvider((businessId: business, membershipId: agent)));

    expect(_Recording.seen, hasLength(2),
        reason: 'one key per ledger, not one key per business');
    expect(_Recording.seen.map((s) => s.membershipId), [null, agent]);
  });

  test('the same scope is one instance', () {
    final container = ProviderContainer(
      overrides: [ledgerHistoryProvider.overrideWith(_Recording.new)],
    );
    addTearDown(container.dispose);

    container.read(
        ledgerHistoryProvider((businessId: business, membershipId: agent)));
    container.read(
        ledgerHistoryProvider((businessId: business, membershipId: agent)));

    expect(_Recording.seen, hasLength(1));
  });

  test('two agents in one business do not share a ledger', () {
    final container = ProviderContainer(
      overrides: [ledgerHistoryProvider.overrideWith(_Recording.new)],
    );
    addTearDown(container.dispose);

    container.read(
        ledgerHistoryProvider((businessId: business, membershipId: 'm-a')));
    container.read(
        ledgerHistoryProvider((businessId: business, membershipId: 'm-b')));

    expect(_Recording.seen, hasLength(2));
  });

  test('a filter change keeps the month band off an agent feed', () async {
    // monthSummary reads day_ledger, which is the whole business. applyFilter
    // used to default withSummary to true and the screen never overrode it, so
    // touching the filter sheet on AG-010 pulled a business-wide band over one
    // person's rows. The scope decides it now, so there is no argument to
    // forget.
    final container = ProviderContainer(
      overrides: [
        ledgerHistoryServiceProvider.overrideWithValue(_ExplodingService()),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(ledgerHistoryProvider(
            (businessId: business, membershipId: agent))
        .notifier);
    await notifier.applyFilter(const LedgerFilter());

    expect(_ExplodingService.summaryCalls, 0,
        reason: 'an agent feed must never ask for the business month summary');
  });
}

/// Records what was asked for and fails the page fetch, which applyFilter
/// tolerates -- the point of the test is the summary call, not the rows.
class _ExplodingService implements LedgerHistoryService {
  static int summaryCalls = 0;

  @override
  Future<LedgerMonthSummary> monthSummary(
      {required String businessId, DateTime? month}) async {
    summaryCalls++;
    throw UnimplementedError();
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
