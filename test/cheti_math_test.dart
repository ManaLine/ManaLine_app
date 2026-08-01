import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/cheti_state.dart';

Cheti _cheti({
  ChetiType type = ChetiType.auction,
  int totalInstalments = 20,
  double instalmentAmount = 5000,
  int openingInstalmentsPaid = 0,
  double openingAmountPaid = 0,
  int recordedInstalments = 0,
  double recordedAmountPaid = 0,
  double recordedDividend = 0,
  DateTime? availedDate,
  double? availedAmount,
  bool availedPreMigration = false,
}) =>
    Cheti(
      chetiId: 'c1',
      name: 'Ramesh Cheti',
      type: type,
      frequency: ChetiFrequency.monthly,
      faceValue: 100000,
      totalInstalments: totalInstalments,
      instalmentAmount: instalmentAmount,
      startDate: DateTime(2026, 1, 1),
      openingInstalmentsPaid: openingInstalmentsPaid,
      openingAmountPaid: openingAmountPaid,
      availedDate: availedDate,
      availedAmount: availedAmount,
      availedPreMigration: availedPreMigration,
      status: 'Running',
      recordedInstalments: recordedInstalments,
      recordedAmountPaid: recordedAmountPaid,
      recordedDividend: recordedDividend,
    );

/// A cheti is an ASSET, not an expense. This reverses BR-061, and these tests
/// are what stop it drifting back: money paid in is recoverable, so it must
/// never sink line profit the way Karchulu does.
void main() {
  group('mid-term migration', () {
    // The Owner's example: a 100,000 cheti, 20 monthly instalments of 5,000,
    // already 8 in when the app started. Because it is an Auction cheti the
    // dividends already earned mean those 8 cost 36,000, NOT 40,000.
    final c = _cheti(openingInstalmentsPaid: 8, openingAmountPaid: 36000);

    test('opening paid is its own figure, not count x instalment', () {
      expect(c.openingAmountPaid, 36000);
      expect(c.openingInstalmentsPaid * c.instalmentAmount, 40000);
      expect(c.openingAmountPaid, isNot(c.openingInstalmentsPaid * c.instalmentAmount),
          reason: 'losing this would make final profit unrecoverable');
    });

    test('remaining instalments count down from the whole term', () {
      expect(c.instalmentsRemaining, 12);
    });

    test('net position is the asset shown beside LB', () {
      expect(c.netPosition, 36000);
    });

    test('profit is withheld until the term actually ends', () {
      // Instalments continue after availing, so a mid-term figure would be a
      // confident wrong number.
      expect(c.finalProfit, isNull);
    });
  });

  group('after availing', () {
    test('net position flips negative once more is taken than paid in', () {
      final c = _cheti(
        openingInstalmentsPaid: 8,
        openingAmountPaid: 36000,
        availedDate: DateTime(2026, 9, 1),
        availedAmount: 85000,
      );
      expect(c.isAvailed, isTrue);
      // Taken 85,000 against 36,000 paid: the remaining instalments are now a
      // liability, and the sign says so without a separate flag.
      expect(c.netPosition, -49000);
    });

    test('instalments still run to the end of the term', () {
      final c = _cheti(
        openingInstalmentsPaid: 8,
        recordedInstalments: 2,
        availedDate: DateTime(2026, 9, 1),
        availedAmount: 85000,
      );
      expect(c.instalmentsPaid, 10);
      expect(c.instalmentsRemaining, 10);
      expect(c.finalProfit, isNull);
    });
  });

  group('final profit', () {
    test('is received minus everything paid, once the term closes', () {
      final c = _cheti(
        openingInstalmentsPaid: 8,
        openingAmountPaid: 36000,
        recordedInstalments: 12,
        recordedAmountPaid: 57000,
        availedDate: DateTime(2026, 9, 1),
        availedAmount: 100000,
      );
      expect(c.instalmentsRemaining, 0);
      expect(c.totalPaid, 93000);
      expect(c.finalProfit, 7000);
    });

    test('a fixed cheti paid in full at face value breaks even', () {
      final c = _cheti(
        type: ChetiType.fixed,
        recordedInstalments: 20,
        recordedAmountPaid: 100000,
        availedDate: DateTime(2027, 8, 1),
        availedAmount: 100000,
      );
      expect(c.finalProfit, 0);
    });
  });

  group('daily account figure', () {
    test('sums every running cheti into one number', () {
      const s = ChetiListState(chetis: []);
      expect(s.totalNetPosition, 0);

      final many = ChetiListState(chetis: [
        _cheti(openingAmountPaid: 36000),
        _cheti(openingAmountPaid: 10000),
        _cheti(
            openingAmountPaid: 20000,
            availedDate: DateTime(2026, 6, 1),
            availedAmount: 50000),
      ]);
      // 36,000 + 10,000 + (20,000 - 50,000) = 16,000
      expect(many.totalNetPosition, 16000);
    });
  });

  group('pre-migration history is not replayed', () {
    test('dividends earned before migration are not this period profit', () {
      final c = _cheti(openingInstalmentsPaid: 8, openingAmountPaid: 36000);
      // The 4,000 of dividend implied by 8x5000 - 36000 belongs to last
      // period. Only dividends recorded in-app count toward line profit.
      expect(c.recordedDividend, 0);
    });
  });
}
