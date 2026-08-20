import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_amount.dart';
import 'package:mana_line/design/tokens/colors.dart';
import 'package:mana_line/design/tokens/typography.dart';

/// The two consolidations: one name per recurring text role, one string form
/// of a rupee amount. Both replace hundreds of hand-written literals, so what
/// they produce is pinned here rather than trusted.
void main() {
  group('manaRupees', () {
    test('formats with lakh grouping and no decimals', () {
      expect(manaRupees(123456), '₹1,23,456');
      expect(manaRupees(0), '₹0');
    });

    test('a negative amount leads with a real minus, outside the ₹', () {
      // NumberFormat's own form is "₹-1,06,600" — the sign buried after the
      // currency mark, easy to miss on the exact figures where missing it
      // costs money. Seen live on an agent profile.
      expect(manaRupees(-106600), '−₹1,06,600');
      expect(manaRupees(-106600), isNot(contains('₹-')));
    });
  });

  group('ManaType', () {
    test('note is the 13sp legibility floor in the secondary colour', () {
      expect(ManaType.note.fontSize, 13);
      expect(ManaType.note.color, ManaColors.textSecondary);
    });

    test('fine at 12sp is the absolute floor — nothing defines smaller', () {
      final sizes = [
        ManaType.note.fontSize,
        ManaType.noteBad.fontSize,
        ManaType.noteWarn.fontSize,
        ManaType.fine.fontSize,
        ManaType.small.fontSize,
        ManaType.smallStrong.fontSize,
        ManaType.cardTitle.fontSize,
        ManaType.sheetTitle.fontSize,
      ];
      for (final s in sizes) {
        expect(s, greaterThanOrEqualTo(12));
      }
    });

    test('palette-coloured styles are getters that follow the palette', () {
      // ManaColors is switched at theme time; a const style would freeze the
      // load-time palette and paint light grey onto dark surfaces.
      final light = ManaType.note.color;
      ManaColors.use(ManaPalette.dark);
      addTearDown(() => ManaColors.use(ManaPalette.light));
      expect(ManaType.note.color, isNot(light));
    });
  });
}
