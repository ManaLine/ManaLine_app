import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_019_cheti_management.dart';
import 'package:mana_line/features/owner_workspace/state/cheti_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// OW-019 is a brand-new screen, and new screens are exactly where the
/// overflow bug keeps appearing -- LR-007, LR-003 and LR-013 all shipped with
/// one. The harness exists so that stops happening by default rather than by
/// somebody squinting at a handset.
///
/// The Cheti card is the risky part: six figures in a Wrap, several carrying
/// full rupee amounts, above a Row of two text buttons whose labels come from
/// ui_translations. That is the same shape as the LR-013 header that
/// overflowed 277px at 2.0x in every language.

/// The screen loads from Supabase in initState. Left alone the test would
/// open a real socket, so the list is seeded instead -- which also means the
/// CARDS get laid out, rather than an empty state that proves nothing.
class _SeededChetiNotifier extends ChetiListNotifier {
  _SeededChetiNotifier(super.ref, ChetiListState seed) {
    state = seed;
  }

  @override
  Future<void> load(String businessId) async {}
}

Cheti _cheti({
  required String name,
  ChetiType type = ChetiType.auction,
  int openingAmountPaid = 36000,
  DateTime? availedDate,
  int? availedAmount,
  int recordedInstalments = 0,
  List<ChetiPaymentRow> payments = const [],
}) =>
    Cheti(
      chetiId: name,
      name: name,
      type: type,
      frequency: ChetiFrequency.monthly,
      faceValue: 100000,
      totalInstalments: 20,
      instalmentAmount: 5000,
      startDate: DateTime(2026, 1, 1),
      openingInstalmentsPaid: 8,
      openingAmountPaid: openingAmountPaid,
      availedDate: availedDate,
      availedAmount: availedAmount,
      availedPreMigration: false,
      status: 'Running',
      recordedInstalments: recordedInstalments,
      recordedAmountPaid: 0,
      recordedDividend: 0,
      payments: payments,
    );

/// Recorded instalments, so the expandable payments list and its per-row
/// delete button actually get laid out. Seeded with a five-figure amount:
/// the row puts a currency string beside a date and a delete icon, which is
/// the shape that overflows once translated.
List<ChetiPaymentRow> _payments() => [
      ChetiPaymentRow(
        paymentId: 'p1',
        businessDate: DateTime(2026, 7, 1),
        grossInstalment: 5000,
        netPaid: 4750,
      ),
      ChetiPaymentRow(
        paymentId: 'p2',
        businessDate: DateTime(2026, 8, 1),
        grossInstalment: 5000,
        netPaid: 4820,
      ),
    ];

/// Deliberately wide, deliberately awkward: a long name, a negative net
/// position (which renders in red with a minus sign), and an availed cheti
/// carrying the extra subtitle line.
final _seed = ChetiListState(chetis: [
  _cheti(
    name: 'Sri Venkateswara Monthly Cheti',
    recordedInstalments: 2,
    payments: _payments(),
  ),
  _cheti(
    name: 'Ramesh Cheti',
    availedDate: DateTime(2026, 6, 1),
    availedAmount: 85000,
  ),
  _cheti(name: 'Fixed Draw Cheti', type: ChetiType.fixed),
]);

void main() {
  List<Override> overrides() => [
        chetiListProvider.overrideWith((ref) => _SeededChetiNotifier(ref, _seed)),
      ];

  group('OW-019 Cheti Management', () {
    for (final scale in kManaTextScales) {
      testWidgets('survives text scale ${scale}x on a 360x640 phone',
          (tester) async {
        await pumpManaScreen(
          tester,
          const ChetiManagementScreen(businessId: 'test-business'),
          textScale: scale,
          overrides: overrides(),
        );

        expectNoLayoutFault(tester, 'OW-019 at ${scale}x');
      });
    }

    // Translated width is DATA. The figure labels and the two action buttons
    // are the widest strings on the card.
    for (final language in ManaLanguage.values) {
      testWidgets('survives ${language.name} at 1.6x', (tester) async {
        await pumpManaScreen(
          tester,
          const ChetiManagementScreen(businessId: 'test-business'),
          language: language,
          textScale: 1.6,
          overrides: overrides(),
        );

        expectNoLayoutFault(tester, 'OW-019 in ${language.name} at 1.6x');
      });
    }

    testWidgets('lays out the empty state without overflowing', (tester) async {
      await pumpManaScreen(
        tester,
        const ChetiManagementScreen(businessId: 'test-business'),
        textScale: 2.0,
        overrides: [
          chetiListProvider.overrideWith(
              (ref) => _SeededChetiNotifier(ref, const ChetiListState())),
        ],
      );

      expectNoLayoutFault(tester, 'OW-019 empty at 2.0x');
    });

    // The instalment rows live in a collapsed ExpansionTile, so every test
    // above lays out the header and nothing else. Expanding is the only way
    // to measure the row that actually carries the delete button.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the expanded instalment list survives ${scale}x',
          (tester) async {
        // One cheti, not three: at 2.0x three cards push the expander past
        // the sliver's build range, so the finder sees nothing and the test
        // would pass by measuring an unbuilt widget.
        await pumpManaScreen(
          tester,
          const ChetiManagementScreen(businessId: 'test-business'),
          textScale: scale,
          overrides: [
            chetiListProvider.overrideWith((ref) => _SeededChetiNotifier(
                ref,
                ChetiListState(chetis: [
                  _cheti(
                    name: 'Sri Venkateswara Monthly Cheti',
                    recordedInstalments: 2,
                    payments: _payments(),
                  ),
                ]))),
          ],
        );

        // scrollUntilVisible only brings the tile partly into view, so at
        // 2.0x its centre — where tap aims — was still off-screen and the
        // tap silently missed. ensureVisible puts the whole tile on screen.
        final expander = find.textContaining('recorded instalment');
        await tester.scrollUntilVisible(expander, 200,
            scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(expander.first);
        await tester.pump();
        await tester.tap(expander.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300)); // expansion

        expectNoLayoutFault(tester, 'OW-019 instalment list at ${scale}x');
        // Asserted on the payment AMOUNT, not on the delete icon: the card
        // itself carries a delete button, so an icon finder would pass even
        // if the list never expanded and nothing new was ever laid out.
        expect(find.textContaining('4,750'), findsOneWidget);
        expect(find.textContaining('4,820'), findsOneWidget);
      });
    }
  });
}
