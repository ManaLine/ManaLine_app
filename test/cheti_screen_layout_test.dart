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
  double openingAmountPaid = 36000,
  DateTime? availedDate,
  double? availedAmount,
  int recordedInstalments = 0,
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
    );

/// Deliberately wide, deliberately awkward: a long name, a negative net
/// position (which renders in red with a minus sign), and an availed cheti
/// carrying the extra subtitle line.
final _seed = ChetiListState(chetis: [
  _cheti(name: 'Sri Venkateswara Monthly Cheti'),
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
  });
}
