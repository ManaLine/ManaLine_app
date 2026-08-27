/// The shared ledger model behind both history screens.
///
/// WHY ONE MODEL: OW-017 previously built its own `_Txn` from three
/// hand-written queries and AG-010 built a different shape from a fourth.
/// Both called the result "history" and neither was the whole of it —
/// expenses, investor deposits and withdrawals, and cheti movements were
/// missing entirely. `day_ledger` names eight categories; this model carries
/// all of them, from one server-side feed, so the two screens cannot drift
/// apart again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mana_time.dart';

/// Which way the cash went. Derived server-side, never inferred from sign.
/// Which way money moved — or, for [transfer], that it did not.
///
/// `transfer` exists because a BF grant hands cash from the Owner's till to an
/// Agent's pocket INSIDE one business. Nothing enters or leaves, so it must
/// never reach a day or month net: marking it moneyIn made a day of handing
/// out float read as +11,000 of income while day_ledger — which is the
/// business's actual book — correctly showed the month flat at zero. Two
/// sources disagreeing about money on the same screen is the failure this app
/// cannot have.
enum LedgerDirection { moneyIn, moneyOut, transfer }

/// The eight things that move money, matching `day_ledger`'s columns.
enum LedgerEventType {
  // The float a round is funded by. Shown at the head of its day so an Agent
  // can see their cash arrive, but a TRANSFER: it moves between two pockets of
  // the same business and changes no total.
  bfGrant('bf_grant', LedgerDirection.transfer),
  collection('collection', LedgerDirection.moneyIn),
  loanDistribution('loan_distribution', LedgerDirection.moneyOut),
  expense('expense', LedgerDirection.moneyOut),
  investorDeposit('investor_deposit', LedgerDirection.moneyIn),
  investorWithdrawal('investor_withdrawal', LedgerDirection.moneyOut),
  chetiPaid('cheti_paid', LedgerDirection.moneyOut),
  chetiReceived('cheti_received', LedgerDirection.moneyIn),
  adjustmentShort('adjustment_short', LedgerDirection.moneyOut),
  adjustmentExcess('adjustment_excess', LedgerDirection.moneyIn);

  const LedgerEventType(this.wire, this.direction);

  /// The `event_type` string `app.ledger_history` returns.
  final String wire;
  final LedgerDirection direction;

  static LedgerEventType fromWire(String value) =>
      LedgerEventType.values.firstWhere(
        (t) => t.wire == value,
        // A type the server knows and this build does not must not be
        // silently dropped from a money list, and must not be guessed into
        // the wrong direction either.
        orElse: () => throw ArgumentError('Unknown ledger event type: $value'),
      );
}

class LedgerEvent {
  /// Stable across pages — '<type>:<uuid>' from the server.
  final String id;
  final LedgerEventType type;

  /// The Indian business day this belongs to. THE grouping key: a collection
  /// taken at 00:30 IST belongs to that Indian day, which is why grouping
  /// must never be derived from [occurredAt]'s local date.
  final String businessDate;

  /// Ordering within the day. Falls back to midnight on [businessDate] for
  /// rows that only carry a date (investments, adjustments).
  final DateTime occurredAt;

  /// Whole rupees. Every money column in this schema is numeric(_,0).
  final int amount;

  /// Customer, investor or cheti name. Null where the event has no other
  /// party — an expense is paid by the business to nobody in particular.
  final String? counterparty;

  /// Loan number, expense category, or adjustment type.
  final String? reference;

  /// How it happened: collection result, withdrawal type, interest type,
  /// expense remark.
  final String? method;

  const LedgerEvent({
    required this.id,
    required this.type,
    required this.businessDate,
    required this.occurredAt,
    required this.amount,
    this.counterparty,
    this.reference,
    this.method,
  });

  bool get isMoneyIn => type.direction == LedgerDirection.moneyIn;

  /// Moves cash between two pockets of the same business without changing what
  /// the business holds. Counted in no total.
  bool get isTransfer => type.direction == LedgerDirection.transfer;

  /// Signed value, for arithmetic only. Never render this directly — the UI
  /// shows direction through position and tone, not a minus sign on a debit.
  int get signedAmount => isTransfer
      ? 0
      : isMoneyIn
          ? amount
          : -amount;

  factory LedgerEvent.fromRow(Map<String, dynamic> row) => LedgerEvent(
        id: row['event_id'] as String,
        type: LedgerEventType.fromWire(row['event_type'] as String),
        businessDate: row['business_date'] as String,
        occurredAt: DateTime.parse(row['occurred_at'] as String),
        amount: (row['amount'] as num).round(),
        counterparty: row['counterparty'] as String?,
        reference: row['reference'] as String?,
        method: row['method'] as String?,
      );
}

/// Month totals, read from `day_ledger` rather than summed from the feed.
///
/// This distinction is the whole point. The old screen added up whichever
/// rows it had loaded and labelled the result "Net Change" — a number that
/// was not the month, not the balance, and not anything the business could
/// check. These figures come from the same derived ledger Day Closure
/// reconciles against.
class LedgerMonthSummary {
  final String monthStart;
  final int received;
  final int spent;
  final int net;
  final int? openingBalance;
  final int? closingBalance;

  /// How many days in this month have a ledger row at all. Zero means the
  /// month is empty, which is different from a month that netted zero.
  final int daysRecorded;

  const LedgerMonthSummary({
    required this.monthStart,
    required this.received,
    required this.spent,
    required this.net,
    required this.daysRecorded,
    this.openingBalance,
    this.closingBalance,
  });

  bool get isEmpty => daysRecorded == 0;

  factory LedgerMonthSummary.fromRow(Map<String, dynamic> row) => LedgerMonthSummary(
        monthStart: row['month_start'] as String,
        received: (row['received'] as num?)?.round() ?? 0,
        spent: (row['spent'] as num?)?.round() ?? 0,
        net: (row['net'] as num?)?.round() ?? 0,
        openingBalance: (row['opening_balance'] as num?)?.round(),
        closingBalance: (row['closing_balance'] as num?)?.round(),
        daysRecorded: (row['days_recorded'] as num?)?.toInt() ?? 0,
      );
}

/// A business day's worth of events, as the list renders them.
class LedgerDay {
  final String businessDate;
  final List<LedgerEvent> events;

  /// The cash carried into this day, and what it ended on.
  ///
  /// Both come from `app.ledger_day_balances`, not from adding up the rows
  /// above — for the Owner they are the recomputed day ledger, for an Agent
  /// their float derived to that date. That matters twice over: a day still
  /// paging in would otherwise show a balance built from half its events, and
  /// an Agent's feed is an RLS-filtered subset that can never be summed into
  /// a position.
  ///
  /// Null when the day is outside the range that was fetched.
  final int? openingBf;
  final int? closingBf;

  const LedgerDay({
    required this.businessDate,
    required this.events,
    this.openingBf,
    this.closingBf,
  });

  /// Net across THIS DAY'S LOADED EVENTS only.
  ///
  /// Correct for an Owner, who sees every event. NOT the business position
  /// for an Agent, whose feed is an RLS-filtered subset — AG-010 must present
  /// this as the agent's own activity and must never show it as a closing
  /// balance. Also incomplete for anyone while the day is still paging in.
  int get netOfLoadedEvents =>
      events.fold(0, (sum, e) => sum + e.signedAmount);

  int get moneyIn => events
      .where((e) => e.isMoneyIn && !e.isTransfer)
      .fold(0, (s, e) => s + e.amount);

  int get moneyOut => events
      .where((e) => !e.isMoneyIn && !e.isTransfer)
      .fold(0, (s, e) => s + e.amount);
}

/// Groups a flat, newest-first feed into business days, preserving order, and
/// gives every day an opening and a carried-forward.
///
/// THE BOOK IS WEEKLY. It is closed on an account date -- a Friday here -- and
/// that is the only day the book itself states a figure for. The migration
/// imported exactly what the book holds: one row per WEEK, an opening_bf and a
/// closing_bf, with no day-level breakdown, because none was ever written
/// down. Individual loans and collections were imported where the Owner had
/// per-customer detail, which is a PARTIAL reconstruction -- across the
/// migrated span the declared weekly figures are Rs 22.8L larger on the way in
/// and Rs 20.9L larger on the way out than the events add up to.
///
/// So the two can never be reconciled by summing, and deriving a day's balance
/// from the events alone would state a number the book disagrees with. What is
/// true:
///
///   * The week's opening belongs to the week's FIRST day.
///   * Each day thereafter opens on the previous day's carried-forward.
///   * The ACCOUNT DATE carries the book's declared closing, not the
///     accumulated one. The gap between them is the part of the week the
///     individual rows do not capture, and the book is what is right.
///
/// After migrated_through_date every day has its own day_ledger row, derived
/// from real rows by app.recompute_day_ledger, so each day is a "week" of one
/// and this collapses to the obvious thing: opening, movements, carried
/// forward.
///
/// This is what makes the carried-forward on 2 Jan read 4,91,380 -- the book's
/// figure -- while 1 Jan, which the book never closed, reads -68,600 from its
/// own movements. A negative there is not an error: the deposit that covers it
/// is dated to the account date, which is how the book was kept.
List<LedgerDay> groupByBusinessDate(
  List<LedgerEvent> events, {
  Map<String, LedgerDayBalance> balances = const {},
}) {
  final days = <String, List<LedgerEvent>>{};
  for (final e in events) {
    (days[e.businessDate] ??= <LedgerEvent>[]).add(e);
  }

  // Every date that needs a line, oldest first. Account dates with no events
  // still count: a week the Owner closed on zero movement is a real line in
  // the book.
  final dates = <String>{...days.keys, ...balances.keys}.toList()..sort();
  final accountDates = balances.keys.toList()..sort();

  final opening = <String, int>{};
  final closing = <String, int>{};

  // The account date each day belongs to: the first closed day on or after it.
  String? accountDateFor(String date) {
    for (final a in accountDates) {
      if (a.compareTo(date) >= 0) return a;
    }
    return null;
  }

  int? running;
  String? currentAccountDate;

  for (final date in dates) {
    final account = accountDateFor(date);

    // A new week begins on the book's own declared opening, not on whatever
    // the previous week's events happened to accumulate to.
    if (account != currentAccountDate) {
      currentAccountDate = account;
      running = account == null ? running : balances[account]!.opening;
    }

    final dayEvents = days[date] ?? const <LedgerEvent>[];
    final net = dayEvents.fold(0, (sum, e) => sum + e.signedAmount);

    // Nothing to open from at all: the feed starts mid-history with no closed
    // week around it. Say nothing rather than invent a zero.
    if (running == null) continue;

    opening[date] = running;
    closing[date] =
        date == account ? balances[account]!.closing : running + net;
    running = closing[date];
  }

  return [
    for (final entry in days.entries)
      LedgerDay(
        businessDate: entry.key,
        events: entry.value,
        openingBf: opening[entry.key],
        closingBf: closing[entry.key],
      ),
  ];
}

/// What one business day opened and closed on.
class LedgerDayBalance {
  final int opening;
  final int closing;
  const LedgerDayBalance({required this.opening, required this.closing});
}

/// What the user narrowed the feed to.
///
/// Applied server-side. Filtering the loaded page in Dart would filter only
/// the newest 50 events and present that as the whole answer — "Expenses
/// only" would quietly mean "expenses among the most recent fifty things".
class LedgerFilter {
  final Set<LedgerEventType> types;
  final DateTime? from;
  final DateTime? to;
  final String search;

  const LedgerFilter({
    this.types = const {},
    this.from,
    this.to,
    this.search = '',
  });

  bool get isActive =>
      types.isNotEmpty || from != null || to != null || search.trim().isNotEmpty;

  /// How many things the user has actually ticked, for the filter button's
  /// badge.
  ///
  /// Each chosen category counts. It used to collapse every category into a
  /// single 1, so ticking Collections, Loans and Deposits showed "1" — the
  /// badge disagreed with the sheet the person had just closed, which reads
  /// as the filter not having taken.
  int get activeCount =>
      types.length +
      ((from != null || to != null) ? 1 : 0) +
      (search.trim().isNotEmpty ? 1 : 0);

  LedgerFilter copyWith({
    Set<LedgerEventType>? types,
    DateTime? from,
    DateTime? to,
    String? search,
    bool clearDates = false,
  }) =>
      LedgerFilter(
        types: types ?? this.types,
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        search: search ?? this.search,
      );
}

class LedgerHistoryService {
  LedgerHistoryService(this._db);
  final SupabaseClient _db;

  /// What each day in a range opened and closed on.
  ///
  /// Asked for the whole visible span in one call rather than per day, and
  /// authoritative rather than summed from the rows on screen — see
  /// [LedgerDay.openingBf]. Pass [membershipId] for an Agent's own float; omit
  /// it for the business ledger.
  Future<Map<String, LedgerDayBalance>> dayBalances({
    required String businessId,
    DateTime? from,
    DateTime? to,
    String? membershipId,
  }) async {
    final rows = await _db.schema('app').rpc('ledger_day_balances', params: {
      'p_business_id': businessId,
      'p_from': from == null ? null : manaDateOf(from),
      'p_to': to == null ? null : manaDateOf(to),
      'p_membership_id': membershipId,
    });
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['business_date'] as String: LedgerDayBalance(
          opening: ((r['opening'] as num?) ?? 0).round(),
          closing: ((r['closing'] as num?) ?? 0).round(),
        ),
    };
  }

  /// One page of history, newest first.
  ///
  /// Keyset-paginated on `occurred_at` rather than OFFSET: the old screen
  /// fetched a business's entire history with no limit at all, which its own
  /// `PERF:` comment admitted was unbounded over the life of the business.
  ///
  /// The extra facts a collection carries that the ledger feed does not:
  /// where it was taken, and who handed the money over.
  ///
  /// Fetched on demand rather than widened into ledger_history. That function
  /// returns a fixed TABLE, so adding two columns means dropping and
  /// recreating it -- and it is one of the four this codebase has already
  /// broken once by changing a signature. A collection detail is opened one
  /// at a time; the feed is read constantly.
  ///
  /// Returns null when there is nothing extra to say, which is the normal
  /// case for a collection taken before locations were recorded.
  Future<ManaCollectionExtras?> collectionExtras(String collectionId) async {
    final rows = await _db
        .from('collections')
        .select('location_name, payer_type, payer_name')
        .eq('collection_id', collectionId)
        .limit(1);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    final r = list.first;
    final extras = ManaCollectionExtras(
      locationName: (r['location_name'] as String?)?.trim(),
      payerType: (r['payer_type'] as String?)?.trim(),
      payerName: (r['payer_name'] as String?)?.trim(),
    );
    return extras.isEmpty ? null : extras;
  }

  /// `.schema('app')` is required — a bare `.rpc()` targets `public` and 404s.
  Future<List<LedgerEvent>> page({
    required String businessId,
    DateTime? before,
    int limit = 50,
    LedgerFilter filter = const LedgerFilter(),
  }) async {
    final rows = await _db.schema('app').rpc('ledger_history', params: {
      'p_business_id': businessId,
      'p_before': before?.toIso8601String(),
      'p_limit': limit,
      // Null, not an empty list: the SQL treats NULL as "no constraint", and
      // an empty array would match nothing at all.
      'p_types': filter.types.isEmpty ? null : filter.types.map((t) => t.wire).toList(),
      'p_from': filter.from == null ? null : manaDateOf(filter.from!),
      'p_to': filter.to == null ? null : manaDateOf(filter.to!),
      'p_search': filter.search.trim().isEmpty ? null : filter.search.trim(),
    });
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(LedgerEvent.fromRow)
        .toList();
  }

  /// [month] may be any date inside the month; the server truncates.
  Future<LedgerMonthSummary> monthSummary({
    required String businessId,
    DateTime? month,
  }) async {
    final target = month ?? manaNowIst();
    final rows = await _db.schema('app').rpc('ledger_month_summary', params: {
      'p_business_id': businessId,
      'p_month': manaDateOf(target),
    });
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) {
      return LedgerMonthSummary(
        monthStart: manaDateOf(DateTime(target.year, target.month, 1)),
        received: 0,
        spent: 0,
        net: 0,
        daysRecorded: 0,
      );
    }
    return LedgerMonthSummary.fromRow(list.first);
  }
}

final ledgerHistoryServiceProvider = Provider<LedgerHistoryService>(
  (ref) => LedgerHistoryService(Supabase.instance.client),
);

/// What a collection knows beyond its amount.
class ManaCollectionExtras {
  /// The village the pin fell in, or null. Never a guess -- the server leaves
  /// it empty rather than naming the nearest village when nothing is close.
  final String? locationName;

  /// 'Customer' when the customer paid themselves, which is not worth saying.
  final String? payerType;
  final String? payerName;

  const ManaCollectionExtras({
    this.locationName,
    this.payerType,
    this.payerName,
  });

  /// Somebody other than the customer handed the money over.
  bool get someoneElsePaid =>
      payerType != null && payerType!.isNotEmpty && payerType != 'Customer';

  bool get isEmpty =>
      (locationName == null || locationName!.isEmpty) && !someoneElsePaid;
}
