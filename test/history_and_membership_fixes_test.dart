import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/customer_workspace/state/customer_profile_state.dart';
import 'package:mana_line/shared/ledger_history_service.dart';

CustomerBusinessMembership _m(String id, String name, MembershipRole role,
        [String status = 'Active']) =>
    CustomerBusinessMembership(
      businessId: id,
      businessName: name,
      role: role,
      membershipStatus: status,
    );

void main() {
  group('filter badge', () {
    test('counts every ticked category, not just "some categories"', () {
      // Seen live: Collections, Loans Issued and Deposits ticked, badge said 1.
      // A badge that disagrees with the sheet just closed reads as the filter
      // not having applied.
      const f = LedgerFilter(types: {
        LedgerEventType.collection,
        LedgerEventType.loanDistribution,
        LedgerEventType.investorDeposit,
      });

      expect(f.activeCount, 3);
    });

    test('dates and search still count once each, alongside categories', () {
      final f = LedgerFilter(
        types: const {LedgerEventType.collection, LedgerEventType.expense},
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
        search: 'venkat',
      );

      // 2 categories + 1 date range + 1 search.
      expect(f.activeCount, 4);
    });

    test('nothing chosen shows no badge', () {
      expect(const LedgerFilter().activeCount, 0);
      expect(const LedgerFilter().isActive, isFalse);
    });
  });

  group('BF is a ledger event', () {
    test('the wire name the server sends resolves', () {
      // app.ledger_history emits 'bf_grant'; an unknown wire value would be
      // silently dropped from the feed.
      expect(LedgerEventType.fromWire('bf_grant'), LedgerEventType.bfGrant);
    });

    test('BF is a transfer, not income', () {
      // Corrected: it was first written as moneyIn, which made a day of
      // handing out float read as +11,000 of income while day_ledger — the
      // business's actual book — showed the month flat at zero. Cash moved
      // between two pockets of one business; nothing entered or left.
      expect(LedgerEventType.bfGrant.direction, LedgerDirection.transfer);
    });
  });

  group('memberships grouped by business', () {
    test('one card per business, every role kept', () {
      // Seen live: this person is Owner, Agent and Customer of the same shop
      // and got three separate cards with identical headings.
      final grouped = manaGroupMemberships([
        _m('b1', 'sri tirumala finance', MembershipRole.owner),
        _m('b1', 'sri tirumala finance', MembershipRole.agent),
        _m('b1', 'sri tirumala finance', MembershipRole.customer, 'Removed'),
        _m('b2', 'sri satyanarayana business', MembershipRole.owner),
        _m('b2', 'sri satyanarayana business', MembershipRole.agent),
      ]);

      expect(grouped, hasLength(2));
      expect(grouped.first.businessName, 'sri tirumala finance');
      expect(grouped.first.roles, hasLength(3));
      expect(grouped.last.roles, hasLength(2));
    });

    test('per-role status survives grouping', () {
      // Removed as a Customer while Active as Owner is a real state, and
      // collapsing to one status per business would hide it.
      final grouped = manaGroupMemberships([
        _m('b1', 'sri tirumala finance', MembershipRole.owner),
        _m('b1', 'sri tirumala finance', MembershipRole.customer, 'Removed'),
      ]);

      final statuses = {for (final r in grouped.single.roles) r.membershipStatus};
      expect(statuses, {'Active', 'Removed'});
    });

    test('order is stable — businesses and roles keep the order they arrived',
        () {
      final grouped = manaGroupMemberships([
        _m('b2', 'second', MembershipRole.owner),
        _m('b1', 'first', MembershipRole.owner),
        _m('b2', 'second', MembershipRole.agent),
      ]);

      expect(grouped.map((g) => g.businessId), ['b2', 'b1']);
      expect(grouped.first.roles.map((r) => r.role),
          [MembershipRole.owner, MembershipRole.agent]);
    });

    test('no memberships means no cards', () {
      expect(manaGroupMemberships(const []), isEmpty);
    });
  });
}
