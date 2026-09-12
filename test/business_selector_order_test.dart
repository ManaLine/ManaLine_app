import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/screens/lr_012_business_selector.dart';

/// Somebody with more than one business had them listed in no order at all.
///
/// The selector returned its map's values, so businesses appeared in whatever
/// order the memberships happened to arrive in from the server. Somebody who
/// OWNS one business and BORROWS from another could find either on top, and
/// the order could change between logins with nothing having changed.
void main() {
  group('rank, widening from "I run this" to "I borrow from this"', () {
    test('an Owner who also works the round comes first', () {
      // The case the Owner named first: the business they are in every day.
      expect(manaBusinessRank(['Owner', 'Agent']), 0);
      expect(manaBusinessRank(['Agent', 'Owner']), 0,
          reason: 'the roles arrive in no particular order, so the rank must '
              'not depend on which was seen first');
    });

    test('the four remaining standings are in the stated order', () {
      expect(manaBusinessRank(['Owner']), 1);
      expect(manaBusinessRank(['Agent']), 2);
      expect(manaBusinessRank(['Investor']), 3);
      expect(manaBusinessRank(['Customer']), 4);
    });

    test('every rank is distinct, so nothing ties by accident', () {
      final ranks = [
        manaBusinessRank(['Owner', 'Agent']),
        manaBusinessRank(['Owner']),
        manaBusinessRank(['Agent']),
        manaBusinessRank(['Investor']),
        manaBusinessRank(['Customer']),
      ];
      expect(ranks.toSet().length, ranks.length,
          reason: 'two standings sharing a rank would let them swap places '
              'between logins, which is what this replaces');
    });

    test('the strongest role wins when somebody holds several', () {
      // A person can hold more than one role in one business -- the UNIQUE
      // constraint is on (person_id, business_id, role), not on the pair.
      expect(manaBusinessRank(['Customer', 'Investor']), 3);
      expect(manaBusinessRank(['Customer', 'Investor', 'Agent']), 2);
      expect(manaBusinessRank(['Customer', 'Investor', 'Agent', 'Owner']), 0);
    });

    test('an unknown or empty role list sorts last rather than crashing', () {
      // A fifth role added server-side must not throw here; it lands at the
      // bottom until this function is taught about it.
      expect(manaBusinessRank(const []), 4);
      expect(manaBusinessRank(['Auditor']), 4);
    });
  });

  group('the order is stable', () {
    test('sorting twice gives the same answer', () {
      // Rank alone leaves equal businesses free to swap, which looks exactly
      // like a bug to the person watching it. The screen breaks ties on name;
      // this pins that rank itself is deterministic.
      final roles = [
        ['Customer'],
        ['Owner', 'Agent'],
        ['Investor'],
        ['Owner'],
        ['Agent'],
      ];
      final first = roles.map(manaBusinessRank).toList();
      final second = roles.map(manaBusinessRank).toList();
      expect(first, second);
      expect(first, [4, 0, 3, 1, 2]);
    });
  });

  group('ties break on where the person was last', () {
    // Rank alone leaves businesses of equal standing free to swap places.
    // Name is stable but arbitrary -- three businesses somebody invests in are
    // not meaningfully alphabetical -- so the one they were last in wins.
    const older = '2026-09-01T10:00:00';
    const newer = '2026-09-12T10:00:00';

    test('the most recently opened comes first', () {
      expect(manaCompareLastOpened(newer, older), lessThan(0));
      expect(manaCompareLastOpened(older, newer), greaterThan(0));
    });

    test('a business never opened sorts after one that was', () {
      // "Never" is not recent. The list is ordered by where the person has
      // actually been.
      expect(manaCompareLastOpened(null, older), greaterThan(0));
      expect(manaCompareLastOpened(older, null), lessThan(0));
    });

    test('two never-opened businesses do not tie-break here', () {
      // 0 means "I cannot separate these", so the caller falls through to its
      // next rule -- name. Returning anything else would silently override it.
      expect(manaCompareLastOpened(null, null), 0);
    });

    test('a corrupt timestamp counts as never, and does not throw', () {
      // This is an ordering preference read out of device storage. A bad value
      // must cost somebody a nice-to-have, not their business list.
      expect(manaCompareLastOpened('not-a-date', null), 0);
      expect(manaCompareLastOpened('not-a-date', older), greaterThan(0));
      expect(manaCompareLastOpened(older, 'not-a-date'), lessThan(0));
    });

    test('rank still outranks recency', () {
      // Opening an investor business yesterday must not lift it above the
      // business you own. Recency only separates equals.
      expect(manaBusinessRank(['Investor']),
          greaterThan(manaBusinessRank(['Owner', 'Agent'])),
          reason: 'recency is a tie-break, not a re-ranking');
    });
  });
}
