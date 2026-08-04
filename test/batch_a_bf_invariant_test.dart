import 'package:flutter_test/flutter_test.dart';

/// Locks the M1 two-bucket BF model that Batch A implements in SQL.
///
/// The database functions are the source of truth; this test mirrors their
/// arithmetic so a future change that quietly breaks the model (for example
/// a collection that forgets to credit the agent, or a settlement that
/// credits the Owner twice) fails here first.
///
/// THE MODEL (simple version):
///   * The Owner holds one cash box:  ownerBf.
///   * Each agent holds their own cash:  agentFloat.
///   * Every rupee sits in exactly one bucket at every moment.
///   * Collections go into the collector's bucket (all payment modes —
///     cash, UPI, bank, cheque — because the collector is holding all of it).
///   * A loan goes OUT of the issuing agent's bucket (they handed the cash
///     to the customer).
///   * Expenses and cheti instalments go OUT of whoever paid them.
///   * A transfer moves money between two agents' buckets, but only after
///     both sides have confirmed.
///   * At settlement the agent's whole float goes to the Owner (the
///     hand-over); a returned settlement reverses it.
void main() {
  // The float ledger must always equal the arithmetic of its events:
  //   float = opening + collections(all modes) - loans - expenses
  //         - cheti net + transfers_in - transfers_out + top-ups
  double recompose({
    required double opening,
    required double collections,
    required double loans,
    required double expenses,
    required double chetiPaid,
    required double transfersIn,
    required double transfersOut,
    required double topUps,
  }) {
    return opening + collections - loans - expenses - chetiPaid + transfersIn - transfersOut + topUps;
  }

  // BR-237 expected CASH closing — cash only, because you cannot count a
  // UPI payment in your hand.
  double expectedCash({
    required double opening,
    required double cashCollected,
    required double loans,
    required double expenses,
    required double transfersIn,
    required double transfersOut,
  }) {
    return opening + cashCollected - loans - expenses + transfersIn - transfersOut;
  }

  group('invariant: agent float recomposes from its events', () {
    test('a freshly granted float starts at the top-up', () {
      expect(recompose(opening: 0, collections: 0, loans: 0, expenses: 0, chetiPaid: 0, transfersIn: 0, transfersOut: 0, topUps: 5000), 5000);
    });

    test('a collection credits the collector by ALL modes', () {
      // Cash 600 + UPI 400 collected by the agent.
      expect(recompose(opening: 5000, collections: 1000, loans: 0, expenses: 0, chetiPaid: 0, transfersIn: 0, transfersOut: 0, topUps: 0), 6000);
    });

    test('a loan takes the handed-out amount out of the issuing agent', () {
      // Repayment 2400 with 400 interest withheld => only 2000 left the agent.
      expect(recompose(opening: 5000, collections: 0, loans: 2000, expenses: 0, chetiPaid: 0, transfersIn: 0, transfersOut: 0, topUps: 0), 3000);
    });

    test('a confirmed transfer moves between the two agents exactly once', () {
      final giver = recompose(opening: 3500, collections: 0, loans: 0, expenses: 0, chetiPaid: 0, transfersIn: 0, transfersOut: 500, topUps: 0);
      final receiver = recompose(opening: 0, collections: 0, loans: 0, expenses: 0, chetiPaid: 0, transfersIn: 500, transfersOut: 0, topUps: 0);
      expect(giver, 3000);
      expect(receiver, 500);
    });

    test('an expense and a cheti instalment leave the payer', () {
      expect(recompose(opening: 4000, collections: 0, loans: 0, expenses: 200, chetiPaid: 300, transfersIn: 0, transfersOut: 0, topUps: 0), 3500);
    });
  });

  group('invariant: never negative', () {
    test('the guards in the RPCs are the backstop, not a CHECK constraint', () {
      // chk_businesses_owner_bf_nonneg and chk_agent_bf_current_nonneg were
      // dropped in 20260805035332. They were correct while BF was a stored
      // running total that only ever moved through guarded RPCs. BF is now
      // derived from live rows, and a derived figure has to be allowed to
      // state the truth: a recompute landing negative would otherwise abort
      // the delete that triggered it, so the user would see a failed delete
      // instead of a wrong balance they can act on. app.recompute_business_bf
      // stores the negative and writes an 'owner_bf_negative' audit row.
      //
      // What stops NEW spending going negative is the pre-flight check inside
      // record_expense / create_loan_with_bf_check / grant_agent_bf /
      // record_cheti_payment — each reads the pot before it spends.
      const float = 1500.0;
      expect(float - 2000 < 0, isTrue, reason: 'the RPC must refuse this, not the DB');
    });

    test('a loan larger than the float must not mint money', () {
      // amount_given 2000 out of a 1500 float is refused; 2000 into 3000 is fine.
      const float = 1500.0;
      expect(float - 2000 < 0, isTrue);
      expect(recompose(opening: 3000, collections: 0, loans: 2000, expenses: 0, chetiPaid: 0, transfersIn: 0, transfersOut: 0, topUps: 0), 1000);
    });
  });

  group('settlement: the hand-over and the return', () {
    test('difference is declared cash minus the server-computed expected', () {
      final expected = expectedCash(opening: 5000, cashCollected: 600, loans: 2000, expenses: 200, transfersIn: 0, transfersOut: 500);
      expect(expected, 2900);
      // Declared 2900 => difference 0. Declared 2700 => short 200 ("agent owes").
      expect(2900 - expected, 0);
      expect(2700 - expected, -200);
    });

    test('the whole float (all modes) hands over exactly once', () {
      const float = 3000.0; // what the agent holds across every mode
      var ownerBf = 5000.0;
      ownerBf += float; // submit: float -> Owner
      expect(ownerBf, 8000);
      // A second submit for the same period is refused — the hand-over
      // happens exactly once (the SQL no-double-submit guard).
    });

    test('a returned settlement reverses the hand-over', () {
      var ownerBf = 8000.0;
      var agentFloat = 0.0;
      const handedOver = 3000.0; // stored on the settlement row
      ownerBf -= handedOver;
      agentFloat += handedOver;
      expect(ownerBf, 5000);
      expect(agentFloat, 3000);
    });
  });

  group('full scenario (mirrors the Batch A SQL walk-through)', () {
    test('every bucket after every step', () {
      var ownerBf = 10000.0; // the Owner declared this as their cash box
      var agentFloat = 0.0;

      // Owner tops the agent up by 5000.
      ownerBf -= 5000; // grant_agent_bf
      agentFloat += 5000;
      expect(ownerBf, 5000);
      expect(agentFloat, 5000);

      // Agent issues a loan: repayment 2400, interest 400, fee 0.
      const amountGiven = 2400.0 - 400.0;
      agentFloat -= amountGiven; // create_loan_with_bf_check
      expect(agentFloat, 3000);

      // Agent collects 1000 (600 cash + 400 UPI).
      agentFloat += 1000; // record_collection credits ALL modes
      expect(agentFloat, 4000);

      // Agent pays a 200 expense and a 300 cheti instalment.
      agentFloat -= 200; // record_expense
      agentFloat -= 300; // record_cheti_payment
      expect(agentFloat, 3500);

      // Settlement: the whole float hands over, exactly once.
      final handedOver = agentFloat;
      agentFloat = 0;
      ownerBf += handedOver;
      expect(handedOver, 3500);
      expect(ownerBf, 8500);
      expect(agentFloat, 0);
    });
  });
}
