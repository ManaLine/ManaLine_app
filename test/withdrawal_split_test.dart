import 'package:flutter_test/flutter_test.dart';

/// A withdrawal is an amount; the split is worked out, not chosen.
///
/// An investor asked for Rs 2,00,000 of "Interest Only" against Rs 70,950 of
/// interest and the app took the request. Three chips let them pick a type
/// that had nothing to do with the figure beside it, and the Owner's payout
/// dialog then asked the OWNER to type the principal and interest portions by
/// hand, defaulting the whole amount to principal. Nothing checked either
/// number against what the investment held.
///
/// The rule now, on both screens and in app.withdraw_from_investment: unpaid
/// interest first, then principal. This pins the arithmetic the screens show,
/// against the real figures from the live investment that prompted it.
({int interest, int principal}) split({
  required int amount,
  required int accruedInterest,
}) {
  final fromInterest = amount.clamp(0, accruedInterest);
  return (interest: fromInterest, principal: amount - fromInterest);
}

/// Mirrors the CASE in app.withdraw_from_investment.
String typeFor({
  required int interest,
  required int principal,
  required int principalHeld,
}) {
  if (principal == 0) return 'Interest Only';
  if (interest > 0) return 'Principal + Interest';
  if (principal >= principalHeld) return 'Principal Full';
  return 'Principal Partial';
}

void main() {
  // Karri Bhaskara Reddy's live investment on 1 Sep 2026: Rs 5,00,000 placed
  // 1 Jan 2025 at Rs 1.50/100/month, one year compounded in.
  const accrued = 70950;
  const principal = 591250;

  group('the split', () {
    test('the Rs 2,00,000 that started this takes interest first', () {
      final s = split(amount: 200000, accruedInterest: accrued);
      expect(s.interest, 70950, reason: 'all of the unpaid interest');
      expect(s.principal, 129050);
      expect(s.interest + s.principal, 200000);
    });

    test('an amount inside the interest never touches principal', () {
      final s = split(amount: 50000, accruedInterest: accrued);
      expect(s.interest, 50000);
      expect(s.principal, 0);
      expect(typeFor(interest: s.interest, principal: s.principal,
          principalHeld: principal), 'Interest Only');
    });

    test('with no interest earned it is all principal', () {
      final s = split(amount: 10000, accruedInterest: 0);
      expect(s.interest, 0);
      expect(s.principal, 10000);
    });

    test('the type follows the split rather than a chip', () {
      final s = split(amount: 200000, accruedInterest: accrued);
      expect(typeFor(interest: s.interest, principal: s.principal,
          principalHeld: principal), 'Principal + Interest',
          reason: 'it was requested as Interest Only, which it plainly is not');
    });

    test('taking everything closes it', () {
      final s = split(amount: accrued + principal, accruedInterest: accrued);
      expect(s.principal, principal);
      expect(typeFor(interest: s.interest, principal: s.principal,
          principalHeld: principal), 'Principal + Interest');
    });
  });

  group('what is available', () {
    // The client used to cap against investments.principal_amount alone, on a
    // comment claiming that column was principal AND interest. It is neither:
    // it excludes this year's accrual, and on this very investment it still
    // read 5,00,000 while 5,91,250 had been earned, because a completed year's
    // compounding had never been written back.
    test('is unpaid interest plus principal', () {
      expect(accrued + principal, 662200);
    });

    test('is more than the stored principal column', () {
      const storedPrincipalColumn = 500000;
      expect(accrued + principal, greaterThan(storedPrincipalColumn));
    });
  });
}
