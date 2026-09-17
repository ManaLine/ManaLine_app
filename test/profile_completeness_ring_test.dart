import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_text.dart';

import 'support/mana_harness.dart';

/// The ring closing as a profile fills in, and the rules that keep it honest.
void main() {
  String sqlOf(String file) => File('supabase/migrations/$file')
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  group('the sweep is a third channel, not a third colour', () {
    testWidgets('a whole ring still draws as a border', (tester) async {
      // Twenty-two screens' worth of established pixels. A partial ring is
      // painted; a whole one keeps the BoxDecoration it always had, so nothing
      // that does not ask for completeness changes at all.
      await pumpManaScreen(
        tester,
        const Scaffold(body: ManaVerificationRing(isVerified: true)),
      );
      final box = tester.widget<Container>(
          find.byType(Container).first);
      expect((box.decoration as BoxDecoration).border, isNotNull);
      expect(box.foregroundDecoration, isNull);
    });

    testWidgets('a partial ring paints instead', (tester) async {
      await pumpManaScreen(
        tester,
        const Scaffold(
          body: ManaVerificationRing(isVerified: true, completeness: 0.4),
        ),
      );
      final box = tester.widget<Container>(find.byType(Container).first);
      expect(box.foregroundDecoration, isNotNull);
      // And the border is gone, or the ring would be drawn twice -- once whole
      // and once partial, which reads as a full ring with a bright patch.
      expect((box.decoration as BoxDecoration).border, isNull);
    });

    testWidgets('colour and sweep are independent', (tester) async {
      // A half-drawn green ring still says verified; it also says half-known.
      // If completeness ever became a colour, this is the pairing that would
      // stop making sense.
      await pumpManaScreen(
        tester,
        const Scaffold(
          body: Row(children: [
            ManaVerificationRing(isVerified: true, completeness: 0.2),
            ManaVerificationRing(isVerified: false, completeness: 1.0),
          ]),
        ),
      );
      expectNoLayoutFault(tester, 'two rings, two meanings');
    });

    for (final f in [0.0, 0.2, 0.4, 1.0]) {
      testWidgets('it lays out at $f', (tester) async {
        await pumpManaScreen(
          tester,
          Scaffold(
            body: ManaVerificationRing(isVerified: true, completeness: f),
          ),
        );
        expectNoLayoutFault(tester, 'ring at $f');
      });
    }
  });

  group('what counts as a complete profile', () {
    final sql =
        sqlOf('20260917234417_how_complete_a_customers_profile_actually_is.sql');

    test('five things, and they are the five', () {
      // If somebody adds a sixth without changing the denominator, every ring
      // in the app quietly overstates how much is known about a customer.
      expect(sql, contains("(p.mlid_type = 'MLPI')::int"));
      expect(sql, contains("(COALESCE(p.mobile_number, '') <> '')::int"));
      expect(sql, contains('(p.dob IS NOT NULL)::int'));
      expect(sql, contains('(p.live_photo_url IS NOT NULL)::int'));
      expect(sql, contains('pa.is_current'));
      expect(sql, contains('5'));
    });

    test('it is authorized like everything else on a book', () {
      expect(sql, contains('app.is_owner(p_business_id)'));
      expect(sql, contains('app.is_active_agent(p_business_id)'));
      expect(sql, contains("ERRCODE = '42501'"));
    });
  });
}
