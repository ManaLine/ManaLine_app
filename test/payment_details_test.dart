import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/payment_details_sheet.dart';
import 'package:mana_line/shared/payment_details_state.dart';
import 'package:mana_line/shared/photo_compression.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// Showing a customer where to pay — design document 2.2.1,
/// "Insert QR & UPI Id's to display ( In jpg < 1mb)".
///
/// The other half of 2.2.2: the app could record that money arrived by GPay,
/// PhonePe or Paytm from 2026-09-17, and had no way for anybody to actually
/// pay that way.
void main() {
  group('what counts as a UPI ID', () {
    test('a real handle is accepted', () {
      for (final good in [
        'siri@okhdfcbank',
        '9493509919@ybl',
        'a.b-c_1@paytm',
        'name@some-new-bank',
      ]) {
        expect(manaLooksLikeUpiId(good), isTrue, reason: good);
      }
    });

    test('anything that is not one is refused', () {
      for (final bad in [
        '',
        'no-at-sign',
        'has space@bank',
        'two@at@signs',
        '@nobody',
        'nobody@',
      ]) {
        expect(manaLooksLikeUpiId(bad), isFalse, reason: '"$bad"');
      }
    });

    test('surrounding whitespace is forgiven, inner whitespace is not', () {
      // An Owner pasting a handle brings a trailing space with it; that is
      // not a reason to refuse their own ID.
      expect(manaLooksLikeUpiId('  siri@okhdfcbank  '), isTrue);
      expect(manaLooksLikeUpiId('siri @okhdfcbank'), isFalse);
    });

    test('the Dart rule and the database rule are the same rule', () {
      // app.upi_ids_are_valid uses '^[^@[:space:]]+@[^@[:space:]]+$'. If these
      // two ever disagree, the client refuses what the server would take or
      // -- worse -- accepts what the server throws back as a constraint name.
      final sql = File('supabase/migrations/'
              '20260918083013_a_business_can_show_its_qr_and_upi_at_the_door.sql')
          .readAsStringSync();
      expect(sql, contains(r"h !~ '^[^@[:space:]]+@[^@[:space:]]+$'"));
    });
  });

  group('the QR is treated as something a machine must read', () {
    test('it is the highest-quality preset in the app', () {
      // A face at quality 70 is still that face. A QR whose modules blur does
      // not degrade — it stops scanning, silently, at somebody's door.
      expect(ManaPhotoPreset.qr.quality,
          greaterThan(ManaPhotoPreset.document.quality));
      expect(ManaPhotoPreset.qr.quality,
          greaterThan(ManaPhotoPreset.loan.quality));
      // Not the largest EDGE, though — `document` is 1600 because an Aadhaar
      // number is small text, while a QR's modules are coarse. Quality is
      // what a QR needs, not pixels: this asserts it is generous rather than
      // biggest, because biggest would be the wrong thing to hold it to.
      expect(ManaPhotoPreset.qr.maxEdge, greaterThanOrEqualTo(1024));
    });

    test('its ceiling is the document\'s own "< 1mb"', () {
      expect(ManaPhotoPreset.qr.hardLimitBytes, 1024 * 1024);
    });

    test('the bucket accepts PNG, and that is deliberate', () {
      // Every other image bucket in this app is image/jpeg only. This one is
      // not, because re-encoding a lossless QR to JPEG is the one compression
      // in the app that can break what it stores.
      final sql = File('supabase/migrations/'
              '20260918083013_a_business_can_show_its_qr_and_upi_at_the_door.sql')
          .readAsStringSync();
      expect(sql, contains("ARRAY['image/jpeg', 'image/png']"));
    });
  });

  group('what an agent is shown', () {
    testWidgets('nothing set says so, and says who can fix it', (tester) async {
      // An agent cannot add a QR themselves. An empty screen that only said
      // "nothing here" would leave them with no next step at a door.
      //
      // The provider is overridden rather than left to reach Supabase: with
      // no backend a test would render the error branch and this would pass
      // or fail for a reason that has nothing to do with emptiness.
      await pumpManaScreen(
        tester,
        const Scaffold(body: PaymentDetailsSheet(businessId: 'b1')),
        overrides: [
          paymentDetailsProvider('b1')
              .overrideWith((ref) async => const PaymentDetails()),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ask the Owner'), findsOneWidget);
    });

    for (final scale in kManaTextScales) {
      for (final lang in ManaLanguage.values) {
        testWidgets('payment details at ${scale}x in ${lang.name}',
            (tester) async {
          await pumpManaScreen(
            tester,
            const Scaffold(body: PaymentDetailsSheet(businessId: 'b1')),
            textScale: scale,
            language: lang,
            overrides: [
              // Two UPI IDs and no QR: the QR needs a signed URL and a
              // network, and what this measures is whether the words fit.
              paymentDetailsProvider('b1').overrideWith((ref) async =>
                  const PaymentDetails(
                      upiIds: ['siri@okhdfcbank', '9493509919@ybl'])),
            ],
          );
          await tester.pumpAndSettle();
          expectNoLayoutFault(
              tester, 'payment details at ${scale}x in ${lang.name}');
        });
      }
    }
  });

  test('the owner writes and the agent reads, with no new RLS', () {
    // Both live on `businesses`, which already had exactly those two rules.
    // If a later change moves them to their own table, the rules have to be
    // written again — and this is the line that should make somebody notice.
    final sql = File('supabase/migrations/'
            '20260918083013_a_business_can_show_its_qr_and_upi_at_the_door.sql')
        .readAsStringSync();
    expect(sql, contains('ALTER TABLE businesses'));
    expect(sql, contains('upi_qr_path'));
    expect(sql, contains('upi_ids'));
    // And the bucket an agent must be able to read.
    expect(sql, contains('business_payment_qr_member_select'));
    expect(sql, contains('app.is_active_agent'));
  });
}
