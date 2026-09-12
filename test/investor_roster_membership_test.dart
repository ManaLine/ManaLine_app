import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/investor_state.dart';

/// An Investor the Owner had just added was missing from the roster he had
/// just been added to.
///
/// tadi srinivasa reddy, Active Investor of Sri Vigneswara Finance, with an
/// investors row and zero investments. The Owner saw "Request sent", he
/// accepted, and the list stayed empty -- with no error anywhere, because
/// nothing had failed. RLS was verified to pass at every level first: the
/// Owner's own inner join across investors, business_members and persons
/// returned him.
///
/// The filter was "an investor is in this business while they have money in
/// it", written when the ONLY way to become an investor was to invest.
/// Approving a membership_request created the investors row and the first
/// investment together, so zero live money could only mean "withdrew
/// everything". Adding an investor directly -- new -- produces the one state
/// that rule was never asked about.
Map<String, dynamic> _investment({
  String status = 'Active',
  num principal = 50000,
  String? deletedAt,
}) =>
    {
      'investment_id': 'i1',
      'status': status,
      'principal_amount': principal,
      'deleted_at': deletedAt,
    };

void main() {
  group('added but not invested yet', () {
    test('an investor with no investments is in the roster', () {
      // THE DEFECT. This returned false, and the person vanished.
      expect(manaInvestorBelongsInRoster(const []), isTrue,
          reason: 'somebody the Owner just added holds nothing yet, and must '
              'still appear in the list they were added to');
    });

    test('their only investment being soft-deleted returns them to that state',
        () {
      // Deleting somebody's one investment should put them back to "added,
      // nothing yet" rather than hide them from the Owner who added them.
      expect(
          manaInvestorBelongsInRoster([_investment(deletedAt: '2026-09-01')]),
          isTrue);
    });
  });

  group('fully withdrawn still drops out', () {
    test('an investment closed to zero hides them, as before', () {
      // The original rule, unchanged: a name with a zero beside it forever is
      // what this filter exists to prevent.
      expect(
          manaInvestorBelongsInRoster(
              [_investment(status: 'Closed', principal: 0)]),
          isFalse);
    });

    test('an Active investment of zero is not live money', () {
      expect(manaInvestorBelongsInRoster([_investment(principal: 0)]), isFalse);
    });

    test('one live investment among closed ones keeps them', () {
      expect(
          manaInvestorBelongsInRoster([
            _investment(status: 'Closed', principal: 0),
            _investment(principal: 25000),
          ]),
          isTrue);
    });
  });

  group('the two zero-balance states are told apart', () {
    test('never invested and fully withdrawn share a balance, not a verdict',
        () {
      // Both hold nothing. Only one of them has ever held anything, and that
      // is the whole distinction -- the balance cannot carry it.
      final neverInvested = manaInvestorBelongsInRoster(const []);
      final fullyWithdrawn = manaInvestorBelongsInRoster(
          [_investment(status: 'Closed', principal: 0)]);
      expect(neverInvested, isNot(fullyWithdrawn),
          reason: 'if these ever agree, one of the two situations is being '
              'handled wrongly: a new member is invisible, or a withdrawn one '
              'sits in the list forever');
    });
  });
}
